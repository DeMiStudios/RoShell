--!strict
--[[
	Lexer: input text -> tokens with byte spans. Never errors; problems are reported as diagnostics and the token
	stream stays usable (unterminated strings and embeds are closed implicitly at end of input).

	See docs/GRAMMAR.md for the full grammar. Summary:
	- Words are made of adjacent parts: bare text, quoted strings, variables (`$name`, `$$`, `$1`, `$@`,
	  `$fn(a, b)`, `$:ref`) and embedded commands (`${ ... }`). Whitespace separates words.
	- `"..."` processes escapes and interpolates `$var`/`${...}`; `'...'` processes escapes only;
	  `"""..."""` is raw and may span lines.
	- Operators: `&&`, `||`, `|`, `;`, and newline (a statement separator).
	- `#` starts a comment when it begins a word and is followed by whitespace or the end of the line.
]]

--// Imports
const Types = require("./Types")

--// Types
export type TokenKind = "Text" | "QuoteOpen" | "QuotedText" | "QuoteClose" | "Variable" | "EmbedOpen" | "EmbedClose" | "Pipe" | "And" | "Or" | "Semicolon" | "Newline" | "Comment"

export type Token = {
	Kind: TokenKind,
	Start: number,
	--- Exclusive end byte.
	End: number,
	--- Processed value: unescaped text for Text/QuotedText, the quote for quote tokens, the name for variables.
	Value: string,
	--- True when whitespace (or the start of a statement) precedes the token, i.e. it starts a new word.
	SpaceBefore: boolean,
	--- Quote style for quote tokens and the parts inside them (`"`, `'` or `"""`).
	Quote: string?,
	--- Arguments of a function-call variable (`$random(1, 10)`).
	Args: { string }?,
	--- False for quotes/embeds/calls that were not closed before the end of input.
	Terminated: boolean,
}

export type LexOutput = {
	Text: string,
	Tokens: { Token },
	Diagnostics: { Types.Diagnostic },
}

type Mode = "normal" | "double" | "embed"

--// Constants
const BYTE_SPACE = string.byte(" ")
const BYTE_TAB = string.byte("\t")
const BYTE_CR = string.byte("\r")
const BYTE_NEWLINE = string.byte("\n")
const BYTE_HASH = string.byte("#")
const BYTE_SEMICOLON = string.byte(";")
const BYTE_PIPE = string.byte("|")
const BYTE_AMPERSAND = string.byte("&")
const BYTE_DOUBLE_QUOTE = string.byte('"')
const BYTE_SINGLE_QUOTE = string.byte("'")
const BYTE_DOLLAR = string.byte("$")
const BYTE_BACKSLASH = string.byte("\\")
const BYTE_OPEN_BRACE = string.byte("{")
const BYTE_CLOSE_BRACE = string.byte("}")
const BYTE_OPEN_PAREN = string.byte("(")
const BYTE_AT = string.byte("@")
const BYTE_COLON = string.byte(":")

const SIMPLE_ESCAPES: { [string]: string } = {
	n = "\n",
	t = "\t",
	r = "\r",
	["0"] = "\0",
	["\\"] = "\\",
	['"'] = '"',
	["'"] = "'",
	["$"] = "$",
	["`"] = "`",
}

--// Helpers

const function isSpace(byte: number?): boolean
	return byte == BYTE_SPACE or byte == BYTE_TAB or byte == BYTE_CR
end

const function isIdentifierStart(byte: number?): boolean
	if byte == nil then
		return false
	end
	return (byte >= 65 and byte <= 90) or (byte >= 97 and byte <= 122) or byte == 95
end

const function isIdentifierChar(byte: number?): boolean
	if byte == nil then
		return false
	end
	return isIdentifierStart(byte) or (byte >= 48 and byte <= 57)
end

const function isDigit(byte: number?): boolean
	return byte ~= nil and byte >= 48 and byte <= 57
end

--// Lexer
const Lexer = {}

--- Tokenizes `text`.
function Lexer.Tokenize(text: string): LexOutput
	const tokens: { Token } = {}
	const diagnostics: { Types.Diagnostic } = {}
	const length = #text
	local position = 1
	-- Each frame is a lexing mode; embeds push a frame and `}` pops it.
	const modes: { Mode } = { "normal" }
	const openers: { Token } = {}
	local spaceBefore = true

	const function emit(
		kind: TokenKind,
		startByte: number,
		endByte: number,
		value: string,
		quote: string?,
		terminated: boolean?
	): Token
		const token: Token = {
			Kind = kind,
			Start = startByte,
			End = endByte,
			Value = value,
			SpaceBefore = spaceBefore,
			Quote = quote,
			Terminated = if terminated == nil then true else terminated,
		}
		table.insert(tokens, token)
		spaceBefore = false
		return token
	end

	const function report(message: string, startByte: number, endByte: number)
		diagnostics[#diagnostics + 1] = {
			Severity = "error",
			Message = message,
			Span = { Start = startByte, End = endByte },
			Code = "syntax",
		}
	end

	--- Reads an escape sequence starting at the backslash; returns the produced text and the next position.
	const function readEscape(at: number): (string, number)
		const nextChar = text:sub(at + 1, at + 1)
		if nextChar == "" then
			return "\\", at + 1
		end
		const simple = SIMPLE_ESCAPES[nextChar]
		if simple then
			return simple, at + 2
		end
		if nextChar == "u" then
			const hex = text:match("^{(%x+)}", at + 2)
			if hex then
				const codepoint = tonumber(hex, 16)
				if codepoint and codepoint <= 0x10FFFF then
					return utf8.char(codepoint), at + 3 + #hex + 1
				end
			end
			report("Invalid unicode escape (expected \\u{XXXX})", at, at + 2)
			return "u", at + 2
		elseif nextChar == "x" then
			const hex = text:match("^%x%x", at + 2)
			if hex then
				return string.char(tonumber(hex, 16) :: number), at + 4
			end
			report("Invalid hex escape (expected \\xHH)", at, at + 2)
			return "x", at + 2
		elseif nextChar == "\n" then
			-- Line continuation.
			return "", at + 2
		end
		-- Unknown escapes keep the escaped character.
		const charEnd = utf8.offset(text, 2, at + 1) or (at + 2)
		return text:sub(at + 1, charEnd - 1), charEnd
	end

	--- Lexes `$...` at `position` (in any mode). Returns true if it produced a token.
	const function lexDollar(): boolean
		const startByte = position
		const nextByte = text:byte(position + 1)
		if nextByte == BYTE_OPEN_BRACE then
			const opener = emit("EmbedOpen", startByte, startByte + 2, "${")
			opener.Terminated = false
			table.insert(openers, opener)
			modes[#modes + 1] = "embed"
			position = startByte + 2
			spaceBefore = true
			return true
		elseif nextByte == BYTE_DOLLAR then
			emit("Variable", startByte, startByte + 2, "$")
			position = startByte + 2
			return true
		elseif nextByte == BYTE_AT then
			emit("Variable", startByte, startByte + 2, "@")
			position = startByte + 2
			return true
		elseif nextByte == BYTE_COLON and isIdentifierChar(text:byte(position + 2)) then
			local finish = position + 2
			while isIdentifierChar(text:byte(finish)) do
				finish += 1
			end
			emit("Variable", startByte, finish, text:sub(startByte + 1, finish - 1))
			position = finish
			return true
		elseif isDigit(nextByte) then
			emit("Variable", startByte, startByte + 2, text:sub(startByte + 1, startByte + 1))
			position = startByte + 2
			return true
		elseif isIdentifierStart(nextByte) then
			local finish = position + 1
			while isIdentifierChar(text:byte(finish)) do
				finish += 1
			end
			const name = text:sub(startByte + 1, finish - 1)
			if text:byte(finish) == BYTE_OPEN_PAREN then
				-- Function call: arguments are raw, comma separated, up to the closing parenthesis.
				const closing = text:find(")", finish + 1, true)
				const endByte = if closing then closing + 1 else length + 1
				const inner = text:sub(finish + 1, (closing or (length + 1)) - 1)
				const args: { string } = {}
				if inner:match("%S") then
					for argument in (inner .. ","):gmatch("([^,]*),") do
						table.insert(args, (argument:match("^%s*(.-)%s*$") or argument))
					end
				end
				const token = emit("Variable", startByte, endByte, name, nil, closing ~= nil)
				token.Args = args
				if not closing then
					report(`Unclosed '(' in call to ${name}`, finish, finish + 1)
				end
				position = endByte
				return true
			end
			emit("Variable", startByte, finish, name)
			position = finish
			return true
		end
		return false
	end

	while position <= length do
		const mode = modes[#modes]
		const byte = text:byte(position)

		if mode == "double" then
			if byte == BYTE_DOUBLE_QUOTE then
				emit("QuoteClose", position, position + 1, '"', '"')
				const opener = table.remove(openers)
				if opener then
					opener.Terminated = true
				end
				table.remove(modes)
				position += 1
			elseif byte == BYTE_DOLLAR and lexDollar() then
				-- Variable or embed inside a double-quoted string.
				if modes[#modes] ~= "embed" then
					spaceBefore = false
				end
			else
				-- Quoted text run up to the next quote, escape or `$`.
				const startByte = position
				const pieces: { string } = {}
				while position <= length do
					const current = text:byte(position)
					if current == BYTE_DOUBLE_QUOTE then
						break
					elseif current == BYTE_DOLLAR then
						const following = text:byte(position + 1)
						if following == BYTE_OPEN_BRACE
							or following == BYTE_DOLLAR
							or following == BYTE_AT
							or isDigit(following)
							or isIdentifierStart(following)
							or (following == BYTE_COLON and isIdentifierChar(text:byte(position + 2))) then
							break
						end
						table.insert(pieces, "$")
						position += 1
					elseif current == BYTE_BACKSLASH then
						const produced, nextPosition = readEscape(position)
						table.insert(pieces, produced)
						position = nextPosition
					else
						local runEnd = position
						while runEnd <= length do
							const runByte = text:byte(runEnd)
							if runByte == BYTE_DOUBLE_QUOTE or runByte == BYTE_DOLLAR or runByte == BYTE_BACKSLASH then
								break
							end
							runEnd += 1
						end
						table.insert(pieces, text:sub(position, runEnd - 1))
						position = runEnd
					end
				end
				const token = emit("QuotedText", startByte, position, table.concat(pieces), '"')
				token.SpaceBefore = false
			end
			continue
		end

		-- Normal and embed modes.
		if isSpace(byte) then
			spaceBefore = true
			position += 1
		elseif byte == BYTE_BACKSLASH and text:byte(position + 1) == BYTE_NEWLINE then
			-- Line continuation outside quotes.
			spaceBefore = true
			position += 2
		elseif byte == BYTE_NEWLINE then
			spaceBefore = true
			emit("Newline", position, position + 1, "\n")
			spaceBefore = true
			position += 1
		elseif byte == BYTE_SEMICOLON then
			emit("Semicolon", position, position + 1, ";")
			spaceBefore = true
			position += 1
		elseif byte == BYTE_PIPE then
			if text:byte(position + 1) == BYTE_PIPE then
				emit("Or", position, position + 2, "||")
				position += 2
			else
				emit("Pipe", position, position + 1, "|")
				position += 1
			end
			spaceBefore = true
		elseif byte == BYTE_AMPERSAND and text:byte(position + 1) == BYTE_AMPERSAND then
			emit("And", position, position + 2, "&&")
			spaceBefore = true
			position += 2
		elseif byte == BYTE_HASH
			and spaceBefore
			and (position == length or isSpace(text:byte(position + 1)) or text:byte(position + 1) == BYTE_NEWLINE) then
			const newline = text:find("\n", position, true)
			const endByte = if newline then newline else length + 1
			emit("Comment", position, endByte, text:sub(position, endByte - 1))
			spaceBefore = true
			position = endByte
		elseif byte == BYTE_CLOSE_BRACE and mode == "embed" then
			emit("EmbedClose", position, position + 1, "}")
			const opener = table.remove(openers)
			if opener then
				opener.Terminated = true
			end
			table.remove(modes)
			position += 1
			-- After `}` the word continues unless whitespace follows (e.g. `${a}b`); inside a double-quoted
			-- string the outer quote continues.
			spaceBefore = false
		elseif byte == BYTE_DOUBLE_QUOTE and text:sub(position, position + 2) == '"""' then
			const startByte = position
			const closing = text:find('"""', position + 3, true)
			const contentEnd = if closing then closing else length + 1
			const opener = emit("QuoteOpen", startByte, startByte + 3, '"""', '"""', closing ~= nil)
			emit("QuotedText", startByte + 3, contentEnd, text:sub(startByte + 3, contentEnd - 1), '"""')
			if closing then
				emit("QuoteClose", closing, closing + 3, '"""', '"""')
				position = closing + 3
			else
				report("Unterminated raw string", startByte, startByte + 3)
				position = length + 1
			end
			opener.Terminated = closing ~= nil
		elseif byte == BYTE_DOUBLE_QUOTE then
			const opener = emit("QuoteOpen", position, position + 1, '"', '"', false)
			table.insert(openers, opener)
			modes[#modes + 1] = "double"
			position += 1
		elseif byte == BYTE_SINGLE_QUOTE then
			const startByte = position
			emit("QuoteOpen", startByte, startByte + 1, "'", "'")
			const opener = tokens[#tokens]
			position += 1
			const contentStart = position
			const pieces: { string } = {}
			local closed = false
			while position <= length do
				const current = text:byte(position)
				if current == BYTE_SINGLE_QUOTE then
					closed = true
					break
				elseif current == BYTE_BACKSLASH then
					const produced, nextPosition = readEscape(position)
					table.insert(pieces, produced)
					position = nextPosition
				else
					local runEnd = position
					while runEnd <= length do
						const runByte = text:byte(runEnd)
						if runByte == BYTE_SINGLE_QUOTE or runByte == BYTE_BACKSLASH then
							break
						end
						runEnd += 1
					end
					table.insert(pieces, text:sub(position, runEnd - 1))
					position = runEnd
				end
			end
			emit("QuotedText", contentStart, position, table.concat(pieces), "'")
			if closed then
				emit("QuoteClose", position, position + 1, "'", "'")
				position += 1
			else
				report("Unterminated string", startByte, startByte + 1)
			end
			opener.Terminated = closed
		elseif byte == BYTE_DOLLAR and lexDollar() then
			continue -- lexDollar consumed the variable/embed.
		else
			-- Bare text run.
			const startByte = position
			const pieces: { string } = {}
			while position <= length do
				const current = text:byte(position)
				if isSpace(current)
					or current == BYTE_NEWLINE
					or current == BYTE_SEMICOLON
					or current == BYTE_PIPE
					or current == BYTE_DOUBLE_QUOTE
					or current == BYTE_SINGLE_QUOTE
					or (current == BYTE_AMPERSAND and text:byte(position + 1) == BYTE_AMPERSAND)
					or (current == BYTE_CLOSE_BRACE and mode == "embed") then
					break
				elseif current == BYTE_DOLLAR then
					const following = text:byte(position + 1)
					if following == BYTE_OPEN_BRACE
						or following == BYTE_DOLLAR
						or following == BYTE_AT
						or isDigit(following)
						or isIdentifierStart(following)
						or (following == BYTE_COLON and isIdentifierChar(text:byte(position + 2))) then
						break
					end
					table.insert(pieces, "$")
					position += 1
				elseif current == BYTE_BACKSLASH then
					if text:byte(position + 1) == BYTE_NEWLINE then
						break
					end
					-- Outside quotes a backslash makes the next character literal.
					const nextChar = text:sub(position + 1, position + 1)
					if nextChar == "" then
						table.insert(pieces, "\\")
						position += 1
					else
						const charEnd = utf8.offset(text, 2, position + 1) or (position + 2)
						table.insert(pieces, text:sub(position + 1, charEnd - 1))
						position = charEnd
					end
				else
					table.insert(pieces, string.char(current :: number))
					position += 1
				end
			end
			emit("Text", startByte, position, table.concat(pieces))
		end
	end

	-- Close anything left open at the end of input.
	for index = #openers, 1, -1 do
		const opener = openers[index]
		if opener.Kind == "EmbedOpen" then
			report("Unclosed '${' (missing '}')", opener.Start, opener.End)
		else
			report("Unterminated string", opener.Start, opener.End)
		end
	end

	return { Text = text, Tokens = tokens, Diagnostics = diagnostics }
end

--- True when `kind` can start or continue a word.
function Lexer.IsWordToken(kind: TokenKind): boolean
	return kind == "Text" or kind == "QuoteOpen" or kind == "Variable" or kind == "EmbedOpen"
end

return table.freeze(Lexer)
