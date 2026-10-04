--!strict
--[[
	Cleans what the console's single-line TextBox holds, and splits its highlighted rendering into the pieces the
	input bar draws. Pure, so it is unit tested headlessly.

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

--- A top-level piece of RichText (see `Chunks`).
export type Chunk = {
	--- The piece's markup, tags balanced.
	Rich: string,
	--- Its text: tags removed, escapes decoded.
	Plain: string,
}

--// Helpers

const function decode(text: string): string
	return (text:gsub("&lt;", "<"):gsub("&gt;", ">"):gsub("&quot;", '"'):gsub("&apos;", "'"):gsub("&amp;", "&"))
end

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

--- Splits RichText into its top-level pieces: runs of unstyled text and balanced tag groups
--- (`<font color="…">…</font>`), each with its text (tags removed, escapes decoded).
---
--- RichText shapes every styled run on its own, so a highlighted line is a fraction of a pixel wider per run than
--- the same text unstyled, and a line with many runs drifts away from the TextBox's caret. The input bar draws
--- each piece at the width of the plain text before it instead, which keeps them aligned.
function InputText.Chunks(rich: string): { Chunk }
	const chunks: { Chunk } = {}
	const plain: { string } = {}
	local depth = 0
	local chunkStart = 1
	local index = 1
	const length = #rich
	const function flush(stop: number)
		if stop >= chunkStart then
			table.insert(chunks, { Rich = rich:sub(chunkStart, stop), Plain = table.concat(plain) })
		end
		chunkStart = stop + 1
		table.clear(plain)
	end
	while index <= length do
		const open = rich:find("<", index, true)
		const textStop = if open then open - 1 else length
		if textStop >= index then
			table.insert(plain, decode(rich:sub(index, textStop)))
		end
		const close = if open then rich:find(">", open, true) else nil
		if open == nil or close == nil then
			break
		end
		if rich:sub(open + 1, open + 1) == "/" then
			depth = math.max(0, depth - 1)
			if depth == 0 then
				flush(close)
			end
		elseif rich:sub(close - 1, close - 1) ~= "/" then
			if depth == 0 and open > chunkStart then
				flush(open - 1)
			end
			depth += 1
		end
		index = close + 1
	end
	flush(length)
	return chunks
end

--- Number of non-empty lines in `text`.
InputText.CountLines = countLines

return table.freeze(InputText)
