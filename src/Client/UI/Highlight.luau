--!strict
--[[
	Syntax highlighting for the input bar and echoed lines. Pure: classifies every byte of the input from the
	lexer tokens (strings, variables, operators, comments, flags) and the live evaluation (command names, argument
	types, errors), then renders RichText with font colors only, so the overlay lines up exactly with the
	transparent TextBox drawn on top of it.
]]

--// Imports
const Parser = require("../../Shared/Parser")
const Types = require("../../Shared/Types")

--// Types
export type SyntaxClass = "plain" | "command" | "argument" | "number" | "string" | "operator" | "flag" | "variable" | "comment" | "error" | "type"

export type Run = {
	Start: number,
	--- Exclusive end byte.
	End: number,
	Class: SyntaxClass,
	--- Theme token of the argument type (for `type` runs).
	Token: string?,
	Underline: boolean,
}

--- Returns `#rrggbb` for a class, or nil to keep the label's default color.
export type ColorResolver = (class: SyntaxClass, token: string?) -> string?

--// Constants
const SELECTOR_START: { [string]: true } = { ["%"] = true, ["~"] = true, ["?"] = true, ["!"] = true }

--// Helpers

const function escape(text: string): string
	return (text:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"):gsub('"', "&quot;"):gsub("'", "&apos;"))
end

const function typeClass(valueType: Types.TypeInfo?): (SyntaxClass, string?)
	if valueType == nil then
		return "argument", nil
	end
	local current: Types.TypeInfo = valueType
	-- Lists and optionals take the color of their element.
	while current.Element ~= nil and current.Color == nil do
		current = current.Element
	end
	if current.Kind == "number" or current.Kind == "range" then
		return "number", nil
	end
	if current.Color ~= nil then
		return "type", current.Color
	end
	return "argument", nil
end

--// Highlight
const Highlight = {}

--- Splits `text` into classified runs. Errors inside `lenient` (the word still being typed) are not painted.
function Highlight.Classify(text: string, evaluation: Types.EvaluateResult?, lenient: Types.Span?): { Run }
	const length = #text
	if length == 0 then
		return {}
	end
	const classes: { SyntaxClass } = table.create(length, "plain")
	const tokens: { string | false } = table.create(length, false)
	const underline: { boolean } = table.create(length, false)
	const locked: { boolean } = table.create(length, false)

	const function isLenient(index: number): boolean
		return lenient ~= nil and index >= lenient.Start and index < lenient.End
	end

	const function paint(first: number, stop: number, class: SyntaxClass, token: string?, lock: boolean)
		for index = math.max(1, first), math.min(length, stop - 1) do
			if class == "error" and isLenient(index) then
				continue
			end
			if not locked[index] then
				classes[index] = class
				tokens[index] = token or false
				if lock then
					locked[index] = true
				end
			end
		end
	end

	-- Lexical classes (locked: semantics never recolor strings, variables or operators).
	const parsed = Parser.Parse(text)
	for _, token in parsed.Tokens do
		const kind = token.Kind
		if kind == "Comment" then
			paint(token.Start, token.End, "comment", nil, true)
		elseif kind == "QuoteOpen" or kind == "QuotedText" or kind == "QuoteClose" then
			paint(token.Start, token.End, "string", nil, true)
		elseif kind == "Variable" or kind == "EmbedOpen" or kind == "EmbedClose" then
			paint(token.Start, token.End, "variable", nil, true)
		elseif kind == "Pipe" or kind == "And" or kind == "Or" or kind == "Semicolon" then
			paint(token.Start, token.End, "operator", nil, true)
		elseif kind == "Text" and token.SpaceBefore and text:sub(token.Start, token.Start + 1) == "--" then
			const equals = text:find("=", token.Start, true)
			const stop = if equals and equals < token.End then equals + 1 else token.End
			paint(token.Start, stop, "flag", nil, true)
		end
	end

	-- Semantic classes from the live evaluation.
	if evaluation then
		for _, command in evaluation.Commands do
			const nameSpan = command.NameSpan
			paint(nameSpan.Start, nameSpan.End, if command.Command then "command" else "error", nil, false)
			for _, resolved in command.Args do
				const span = resolved.Span
				if span == nil or not resolved.Present then
					continue
				end
				if not resolved.Ok and not resolved.Deferred then
					paint(span.Start, span.End, "error", nil, false)
					continue
				end
				const valueType: Types.TypeInfo = resolved.Type or resolved.Arg.Type
				const class, token = typeClass(valueType)
				paint(span.Start, span.End, class, token, false)
				if valueType.Listable then
					-- List syntax: separators, wildcards and selector prefixes.
					local itemStart = true
					for index = span.Start, math.min(length, span.End - 1) do
						const char = text:sub(index, index)
						if char == "," then
							paint(index, index + 1, "operator", nil, false)
							itemStart = true
						elseif char == "*" or (itemStart and SELECTOR_START[char]) then
							paint(index, index + 1, "operator", nil, false)
							itemStart = char ~= "*"
						else
							itemStart = false
						end
					end
				end
			end
		end
		for _, diagnostic in evaluation.Diagnostics do
			if diagnostic.Severity == "error" then
				const span = diagnostic.Span
				for index = math.max(1, span.Start), math.min(length, span.End - 1) do
					if isLenient(index) then
						continue
					end
					underline[index] = true
					if not locked[index] then
						classes[index] = "error"
						tokens[index] = false
					end
				end
			end
		end
	end

	const runs: { Run } = {}
	local start = 1
	for index = 2, length + 1 do
		if index > length
			or classes[index] ~= classes[start]
			or tokens[index] ~= tokens[start]
			or underline[index] ~= underline[start] then
			const token = tokens[start]
			runs[#runs + 1] = {
				Start = start,
				End = index,
				Class = classes[start],
				Token = if token then token else nil,
				Underline = underline[start],
			}
			start = index
		end
	end
	return runs
end

--- Renders runs as RichText. `ghost` (completion preview) is appended faintly after the text.
function Highlight.Render(text: string, runs: { Run }, colorOf: ColorResolver, ghost: string?, ghostColor: string?): string
	const parts: { string } = {}
	for _, run in runs do
		local segment = escape(text:sub(run.Start, run.End - 1))
		if run.Underline then
			segment = `<u>{segment}</u>`
		end
		const color = colorOf(run.Class, run.Token)
		if color then
			segment = `<font color="{color}">{segment}</font>`
		end
		parts[#parts + 1] = segment
	end
	if ghost and ghost ~= "" then
		parts[#parts + 1] = `<font color="{ghostColor or "#808080"}" transparency="0.35">{escape(ghost)}</font>`
	end
	return table.concat(parts)
end

return table.freeze(Highlight)
