--!strict
--[[
	Parser: tokens -> AST. Recovers from every error (trailing operators, empty commands, unterminated quotes,
	unclosed `${`) and always returns a best-effort tree plus diagnostics, so the command bar can highlight and
	complete partial input.

	AST shape:
		Script    = { Statements: { Chain } }                       -- separated by `;` or newlines
		Chain     = { Pipelines: { Pipeline }, Operators: { "&&" | "||" } }
		Pipeline  = { Commands: { CommandNode } }                   -- separated by `|`
		Command   = { Words: { Word } }
		Word      = { Parts: { Part } }                             -- adjacent parts without whitespace
		Part      = Text | Variable | Embed
]]

--// Imports
const Lexer = require("./Lexer")
const Types = require("./Types")

--// Types
type Span = Types.Span
type Token = Lexer.Token

export type TextPart = { Kind: "Text", Value: string, Quoted: boolean, Span: Span }
export type VariablePart = {
	Kind: "Variable",
	Name: string,
	Args: { string }?,
	Quoted: boolean,
	Span: Span,
}
export type EmbedPart = {
	Kind: "Embed",
	Script: Script,
	Quoted: boolean,
	Span: Span,
	Terminated: boolean,
}
export type Part = TextPart | VariablePart | EmbedPart

export type Word = {
	Parts: { Part },
	Span: Span,
	--- True when every part is quoted (operators and wildcards are then disabled for this word).
	Quoted: boolean,
	--- True when the word contains only text (no variables or embeds), so `Value` is final.
	Static: boolean,
	--- Concatenated text of the word (variables/embeds rendered as their source).
	Value: string,
	--- When the word begins with a quote: the quote style, its opening span and whether it was closed.
	OpenQuote: { Quote: string, Span: Span, Terminated: boolean }?,
}

export type CommandNode = { Words: { Word }, Span: Span }
export type Pipeline = { Commands: { CommandNode }, Span: Span }
export type ChainOperator = "&&" | "||"
export type Chain = {
	Pipelines: { Pipeline },
	Operators: { ChainOperator },
	Span: Span,
}
export type Script = { Statements: { Chain }, Span: Span }

export type ParseOutput = {
	Text: string,
	Script: Script,
	Tokens: { Token },
	Diagnostics: { Types.Diagnostic },
}

--// Globals
-- One-entry memo: typing moves the cursor far more often than it changes text.
local lastText: string? = nil
local lastOutput: ParseOutput? = nil

--// Parser
const Parser = {}

--- Parses `text` into an AST. Never errors.
function Parser.Parse(text: string): ParseOutput
	if text == lastText and lastOutput then
		return lastOutput
	end

	const lexed = Lexer.Tokenize(text)
	const tokens = lexed.Tokens
	const diagnostics: { Types.Diagnostic } = table.clone(lexed.Diagnostics)
	const count = #tokens
	local index = 1

	const function peek(): Token?
		return tokens[index]
	end

	const function report(message: string, span: Span, code: string?)
		diagnostics[#diagnostics + 1] = { Severity = "error", Message = message, Span = span, Code = code or "syntax" }
	end

	const function skipComments()
		while index <= count and tokens[index].Kind == "Comment" do
			index += 1
		end
	end

	const function spanAt(position: number): Span
		return { Start = position, End = position }
	end

	-- Forward declaration for recursion through embeds.
	local parseScript: (insideEmbed: boolean, startByte: number) -> Script

	const function parseWord(): Word
		const parts: { Part } = {}
		const first = tokens[index]
		local openQuote: { Quote: string, Span: Span, Terminated: boolean }? = nil
		local isFirst = true
		local allQuoted = true
		local static = true
		const valuePieces: { string } = {}
		local finish = first.Start

		while index <= count do
			const token = tokens[index]
			if not Lexer.IsWordToken(token.Kind) or (not isFirst and token.SpaceBefore) then
				break
			end
			if token.Kind == "Text" then
				parts[#parts + 1] = {
					Kind = "Text",
					Value = token.Value,
					Quoted = false,
					Span = { Start = token.Start, End = token.End },
				}
				table.insert(valuePieces, token.Value)
				allQuoted = false
				finish = token.End
				index += 1
			elseif token.Kind == "Variable" then
				parts[#parts + 1] = {
					Kind = "Variable",
					Name = token.Value,
					Args = token.Args,
					Quoted = false,
					Span = { Start = token.Start, End = token.End },
				}
				table.insert(valuePieces, text:sub(token.Start, token.End - 1))
				allQuoted = false
				static = false
				finish = token.End
				index += 1
			elseif token.Kind == "EmbedOpen" then
				index += 1
				const script = parseScript(true, token.End)
				const closer = peek()
				local terminated = false
				local embedEnd = script.Span.End
				if closer and closer.Kind == "EmbedClose" then
					terminated = true
					embedEnd = closer.End
					index += 1
				end
				parts[#parts + 1] = {
					Kind = "Embed",
					Script = script,
					Quoted = false,
					Span = { Start = token.Start, End = embedEnd },
					Terminated = terminated,
				}
				table.insert(valuePieces, text:sub(token.Start, embedEnd - 1))
				allQuoted = false
				static = false
				finish = embedEnd
			elseif token.Kind == "QuoteOpen" then
				const quote = token.Quote or '"'
				if isFirst then
					openQuote = {
						Quote = quote,
						Span = { Start = token.Start, End = token.End },
						Terminated = token.Terminated,
					}
				end
				index += 1
				finish = token.End
				-- An empty string still produces a (quoted, empty) text part.
				local producedPart = false
				while index <= count do
					const inner = tokens[index]
					if inner.Kind == "QuoteClose" then
						finish = inner.End
						index += 1
						break
					elseif inner.Kind == "QuotedText" then
						parts[#parts + 1] = {
							Kind = "Text",
							Value = inner.Value,
							Quoted = true,
							Span = { Start = inner.Start, End = inner.End },
						}
						table.insert(valuePieces, inner.Value)
						producedPart = true
						finish = inner.End
						index += 1
					elseif inner.Kind == "Variable" then
						parts[#parts + 1] = {
							Kind = "Variable",
							Name = inner.Value,
							Args = inner.Args,
							Quoted = true,
							Span = { Start = inner.Start, End = inner.End },
						}
						table.insert(valuePieces, text:sub(inner.Start, inner.End - 1))
						static = false
						producedPart = true
						finish = inner.End
						index += 1
					elseif inner.Kind == "EmbedOpen" then
						index += 1
						const script = parseScript(true, inner.End)
						const closer = peek()
						local terminated = false
						local embedEnd = script.Span.End
						if closer and closer.Kind == "EmbedClose" then
							terminated = true
							embedEnd = closer.End
							index += 1
						end
						parts[#parts + 1] = {
							Kind = "Embed",
							Script = script,
							Quoted = true,
							Span = { Start = inner.Start, End = embedEnd },
							Terminated = terminated,
						}
						table.insert(valuePieces, text:sub(inner.Start, embedEnd - 1))
						static = false
						producedPart = true
						finish = embedEnd
					else
						-- Unterminated string: the lexer already reported it; stop at the first foreign token.
						break
					end
				end
				if not producedPart then
					parts[#parts + 1] = {
						Kind = "Text",
						Value = "",
						Quoted = true,
						Span = { Start = finish, End = finish },
					}
				end
			else
				break
			end
			isFirst = false
		end

		return {
			Parts = parts,
			Span = { Start = first.Start, End = finish },
			Quoted = allQuoted and #parts > 0,
			Static = static,
			Value = table.concat(valuePieces),
			OpenQuote = openQuote,
		}
	end

	const function parseCommand(startByte: number): CommandNode
		skipComments()
		const words: { Word } = {}
		while index <= count and Lexer.IsWordToken(tokens[index].Kind) do
			table.insert(words, parseWord())
			skipComments()
		end
		if #words == 0 then
			const token = peek()
			const at = if token then token.Start else #text + 1
			return { Words = words, Span = spanAt(math.max(startByte, at)) }
		end
		return { Words = words, Span = { Start = words[1].Span.Start, End = words[#words].Span.End } }
	end

	const function parsePipeline(startByte: number): Pipeline
		const commands: { CommandNode } = { parseCommand(startByte) }
		while true do
			const token = peek()
			if token == nil or token.Kind ~= "Pipe" then
				break
			end
			index += 1
			const command = parseCommand(token.End)
			if #command.Words == 0 then
				report("Expected a command after '|'", { Start = token.Start, End = token.End })
			end
			table.insert(commands, command)
		end
		if #commands[1].Words == 0 and #commands > 1 then
			report("Expected a command before '|'", commands[1].Span)
		end
		return { Commands = commands, Span = { Start = commands[1].Span.Start, End = commands[#commands].Span.End } }
	end

	const function parseChain(startByte: number): Chain
		const pipelines: { Pipeline } = { parsePipeline(startByte) }
		const operators: { ChainOperator } = {}
		while true do
			const token = peek()
			if token == nil or (token.Kind ~= "And" and token.Kind ~= "Or") then
				break
			end
			index += 1
			const operator: ChainOperator = if token.Kind == "And" then "&&" else "||"
			table.insert(operators, operator)
			const pipeline = parsePipeline(token.End)
			if #pipeline.Commands[1].Words == 0 then
				report(`Expected a command after '{operator}'`, { Start = token.Start, End = token.End })
			end
			table.insert(pipelines, pipeline)
		end
		if #pipelines[1].Commands[1].Words == 0 and #pipelines > 1 then
			report("Expected a command before '" .. operators[1] .. "'", pipelines[1].Span)
		end
		return {
			Pipelines = pipelines,
			Operators = operators,
			Span = { Start = pipelines[1].Span.Start, End = pipelines[#pipelines].Span.End },
		}
	end

	parseScript = function(insideEmbed: boolean, startByte: number): Script
		const statements: { Chain } = {}
		local cursor = startByte
		while index <= count do
			const token = tokens[index]
			if token.Kind == "Semicolon" or token.Kind == "Newline" or token.Kind == "Comment" then
				index += 1
				cursor = token.End
			elseif token.Kind == "EmbedClose" then
				if insideEmbed then
					break
				end
				-- A stray `}` outside an embed cannot be produced by the lexer; skip defensively.
				index += 1
			elseif token.Kind == "Pipe" or token.Kind == "And" or token.Kind == "Or" then
				-- Operator with nothing before it.
				const chain = parseChain(cursor)
				table.insert(statements, chain)
				cursor = chain.Span.End
			else
				const chain = parseChain(cursor)
				table.insert(statements, chain)
				cursor = chain.Span.End
				const following = peek()
				if following
					and following.Kind ~= "Semicolon"
					and following.Kind ~= "Newline"
					and following.Kind ~= "Comment"
					and following.Kind ~= "EmbedClose" then
					-- Defensive: unexpected token after a complete statement; skip it to guarantee progress.
					report("Unexpected token", { Start = following.Start, End = following.End })
					index += 1
				end
			end
		end
		const finish = if #statements > 0 then statements[#statements].Span.End else cursor
		return { Statements = statements, Span = { Start = startByte, End = math.max(finish, cursor) } }
	end

	const script = parseScript(false, 1)
	script.Span = { Start = 1, End = #text + 1 }

	const output: ParseOutput = { Text = text, Script = script, Tokens = tokens, Diagnostics = diagnostics }
	lastText = text
	lastOutput = output
	return output
end

--- Calls `visitor` for every command node in the script, including commands inside embeds (depth-first,
--- outer commands before the commands embedded in their words).
function Parser.ForEachCommand(script: Script, visitor: (command: CommandNode, depth: number) -> ())
	const function visit(node: Script, depth: number)
		for _, chain in node.Statements do
			for _, pipeline in chain.Pipelines do
				for _, command in pipeline.Commands do
					visitor(command, depth)
					for _, word in command.Words do
						for _, part in word.Parts do
							if part.Kind == "Embed" then
								visit(part.Script, depth + 1)
							end
						end
					end
				end
			end
		end
	end
	visit(script, 0)
end

--- Counts the commands of a script (including embedded ones).
function Parser.CountCommands(script: Script): number
	local total = 0
	Parser.ForEachCommand(script, function()
		total += 1
	end)
	return total
end

return table.freeze(Parser)
