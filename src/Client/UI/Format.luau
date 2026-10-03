--!strict
--[[
	Turns output blocks into log entries: RichText (monospace, so tables align with plain spaces), a plain-text
	copy for measuring/exporting, and the level/icon of the row. Pure, so it is unit tested headlessly.
]]

--// Imports
const Types = require("../../Shared/Types")
const Util = require("../../Shared/Util")

--// Types
export type EntryKind = "text" | "echo" | "swatch" | "progress"

export type Entry = {
	Kind: EntryKind,
	Level: Types.Level,
	Rich: string,
	Plain: string,
	--- False for tables and other aligned output (clipped instead of wrapped).
	Wrap: boolean,
	Color: Color3?,
	Fraction: number?,
	ProgressId: string?,
}

--- Hex colors used inside formatted text.
export type Colors = {
	read Accent: string,
	read Secondary: string,
	read Muted: string,
	read Link: string,
}

--// Constants
const MAX_CELL = 40
const MAX_KEY = 28
const BULLET = "•"
const RULE = "─"

--// Helpers

const escape = Util.EscapeRichText

const function width(text: string): number
	return utf8.len(text) or #text
end

const function pad(text: string, size: number): string
	const length = width(text)
	return if length >= size then text else text .. string.rep(" ", size - length)
end

const function colored(color: string, text: string): string
	return `<font color="{color}">{text}</font>`
end

const function titleLines(title: string?, colors: Colors, rich: { string }, plain: { string })
	if title and title ~= "" then
		table.insert(rich, colored(colors.Secondary, `<b>{escape(title)}</b>`))
		table.insert(plain, title)
	end
end

const function textEntry(level: Types.Level, rich: { string }, plain: { string }, wrap: boolean): Entry
	return {
		Kind = "text",
		Level = level,
		Rich = table.concat(rich, "\n"),
		Plain = table.concat(plain, "\n"),
		Wrap = wrap,
	}
end

--// Format
const Format = {}

--- Formats a table block as aligned monospace text.
function Format.Table(block: Types.TableBlock, colors: Colors): Entry
	const rich: { string } = {}
	const plain: { string } = {}
	titleLines(block.Title, colors, rich, plain)
	const columns = block.Columns
	const widths: { number } = {}
	for index, column in columns do
		widths[index] = math.min(MAX_CELL, width(column))
	end
	const rows: { { string } } = {}
	for _, row in block.Rows do
		const cells: { string } = {}
		for index = 1, math.max(#columns, #row) do
			const cell = Util.Truncate(row[index] or "", MAX_CELL)
			cells[index] = cell
			widths[index] = math.max(widths[index] or 0, width(cell))
		end
		table.insert(rows, cells)
	end
	const headerPlain: { string } = {}
	const headerRich: { string } = {}
	const rule: { string } = {}
	for index, size in widths do
		const header = pad(Util.Truncate(columns[index] or "", MAX_CELL), size)
		headerPlain[index] = header
		headerRich[index] = escape(header)
		rule[index] = string.rep(RULE, size)
	end
	if #columns > 0 then
		table.insert(plain, table.concat(headerPlain, "  "))
		table.insert(rich, colored(colors.Accent, table.concat(headerRich, "  ")))
		table.insert(plain, table.concat(rule, "  "))
		table.insert(rich, colored(colors.Muted, table.concat(rule, "  ")))
	end
	for _, cells in rows do
		const linePlain: { string } = {}
		const lineRich: { string } = {}
		for index, size in widths do
			const cell = pad(cells[index] or "", size)
			linePlain[index] = cell
			lineRich[index] = escape(cell)
		end
		table.insert(plain, (table.concat(linePlain, "  "):gsub("%s+$", "")))
		table.insert(rich, (table.concat(lineRich, "  "):gsub("%s+$", "")))
	end
	if #block.Rows == 0 then
		table.insert(plain, "(no rows)")
		table.insert(rich, colored(colors.Muted, "(no rows)"))
	end
	return textEntry("plain", rich, plain, false)
end

function Format.List(block: Types.ListBlock, colors: Colors): Entry
	const rich: { string } = {}
	const plain: { string } = {}
	titleLines(block.Title, colors, rich, plain)
	for _, item in block.Items do
		table.insert(plain, `{BULLET} {item}`)
		table.insert(rich, `{colored(colors.Muted, BULLET)} {escape(item)}`)
	end
	if #block.Items == 0 then
		table.insert(plain, "(empty)")
		table.insert(rich, colored(colors.Muted, "(empty)"))
	end
	return textEntry(block.Level or "plain", rich, plain, true)
end

function Format.KeyValue(block: Types.KeyValueBlock, colors: Colors): Entry
	const rich: { string } = {}
	const plain: { string } = {}
	titleLines(block.Title, colors, rich, plain)
	local keyWidth = 0
	for _, entry in block.Entries do
		keyWidth = math.max(keyWidth, math.min(MAX_KEY, width(entry.Key)))
	end
	for _, entry in block.Entries do
		const key = pad(Util.Truncate(entry.Key, MAX_KEY), keyWidth)
		table.insert(plain, `{key}  {entry.Value}`)
		table.insert(rich, `{colored(colors.Secondary, escape(key))}  {escape(entry.Value)}`)
	end
	return textEntry("plain", rich, plain, true)
end

--- Formats any block. Custom blocks are shown as their data unless a renderer converted them first.
function Format.Block(block: Types.Block, colors: Colors): Entry
	if block.Kind == "text" then
		const text = block.Text
		return {
			Kind = if block.Level == "echo" then "echo" else "text",
			Level = block.Level,
			Rich = if block.Rich then text else escape(text),
			Plain = if block.Rich then (text:gsub("<[^>]+>", "")) else text,
			Wrap = true,
		}
	elseif block.Kind == "table" then
		return Format.Table(block, colors)
	elseif block.Kind == "list" then
		return Format.List(block, colors)
	elseif block.Kind == "keyvalue" then
		return Format.KeyValue(block, colors)
	elseif block.Kind == "color" then
		return {
			Kind = "swatch",
			Level = "plain",
			Rich = escape(block.Label),
			Plain = block.Label,
			Wrap = true,
			Color = block.Color,
		}
	elseif block.Kind == "progress" then
		const fraction = block.Fraction
		const suffix = if fraction then `  {math.floor(fraction * 100 + 0.5)}%` else ""
		return {
			Kind = "progress",
			Level = "info",
			Rich = escape(block.Label) .. colored(colors.Muted, suffix),
			Plain = block.Label .. suffix,
			Wrap = false,
			Fraction = fraction,
			ProgressId = block.Id,
		}
	elseif block.Kind == "value" then
		const items = block.Items
		local rich = escape(block.Display)
		local plain = block.Display
		if items and #items > 1 then
			const escaped: { string } = {}
			for index, item in items do
				escaped[index] = escape(item)
			end
			rich = table.concat(escaped, colored(colors.Muted, " · "))
			plain = Util.Join(items, ", ")
		end
		if block.TypeName then
			rich ..= "  " .. colored(colors.Muted, ": " .. escape(block.TypeName))
			plain ..= "  : " .. block.TypeName
		end
		return { Kind = "text", Level = "plain", Rich = rich, Plain = plain, Wrap = true }
	elseif block.Kind == "link" then
		return {
			Kind = "text",
			Level = "info",
			Rich = `{escape(block.Text)}  {colored(colors.Link, `<u>{escape(block.Url)}</u>`)}`,
			Plain = `{block.Text}  {block.Url}`,
			Wrap = true,
		}
	end
	const text = Util.FormatValue(block.Data)
	return {
		Kind = "text",
		Level = "muted",
		Rich = colored(colors.Muted, escape(`[{block.Renderer}] {text}`)),
		Plain = `[{block.Renderer}] {text}`,
		Wrap = true,
	}
end

--- Plain-text export of entries (for `export-log`).
function Format.Export(entries: { { Entry: Entry, Time: number } }): string
	const lines: { string } = {}
	for _, item in entries do
		const entry = item.Entry
		const prefix = if entry.Kind == "echo" then "> " elseif entry.Level == "error" then "! " else "  "
		for line in (entry.Plain .. "\n"):gmatch("(.-)\n") do
			table.insert(lines, `[{os.date("%H:%M:%S", math.floor(item.Time))}] {prefix}{line}`)
		end
	end
	return table.concat(lines, "\n")
end

return table.freeze(Format)
