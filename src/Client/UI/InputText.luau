--!strict
--[[
	Cleans what the console's single-line TextBox holds. Pure, so it is unit tested headlessly.

	- Tab characters never stay (Tab completes instead).
	- A change that only adds line breaks is the Enter key's own character: on a real keyboard it can land in the
	  box right after the console recaptures focus, or at the caret just before focus is lost. It is dropped
	  silently, wherever it landed.
	- Pasted text with a single line of content keeps its text without the breaks.
	- Pasted text with two or more non-empty lines is a script: the caller keeps the previous text and offers to run
	  it.
]]

--// Types
export type Cleaned =
	--- Single-line text to keep, with the caret adjusted for removed characters.
	{ Kind: "text", Text: string, Cursor: number }
	--- Several lines (breaks normalized to "\n") offered as a script.
	| { Kind: "script", Text: string, Lines: number }

--// Helpers

const function countLines(text: string): number
	local lines = 0
	for line in (text .. "\n"):gmatch("(.-)\n") do
		if line:match("%S") then
			lines += 1
		end
	end
	return lines
end

--// InputText
const InputText = {}

--- Cleans `text` with the caret at byte `cursor` (values below 1 mean "no caret": the end is used). `previous` is
--- the text before this change; when removing the line breaks gives it back, the breaks were the Enter key's.
function InputText.Clean(text: string, cursor: number, previous: string?): Cleaned
	const caret = if cursor >= 1 then math.min(cursor, #text + 1) else #text + 1
	if not text:find("[\r\n\t]") then
		return { Kind = "text", Text = text, Cursor = caret }
	end
	const removedBefore = select(2, text:sub(1, caret - 1):gsub("[\r\n\t]", ""))
	const cleaned = (text:gsub("[\r\n\t]", ""))
	const flattened: Cleaned = { Kind = "text", Text = cleaned, Cursor = math.max(1, caret - removedBefore) }
	if cleaned == previous or not text:find("[\r\n]") then
		return flattened
	end
	const normalized = (text:gsub("\r\n?", "\n"))
	const lines = countLines(normalized)
	if lines >= 2 then
		return { Kind = "script", Text = normalized, Lines = lines }
	end
	return flattened
end

--- Number of non-empty lines in `text`.
InputText.CountLines = countLines

return table.freeze(InputText)
