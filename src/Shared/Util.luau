--!strict
--[[
	Small typed helpers shared by every layer. This module must stay free of Roblox globals at load time so the
	core can be unit-tested with the standalone Luau runtime.
]]

--// Constants
const MAX_FORMAT_ITEMS = 8
const DURATION_UNIT_SECONDS = { 86400, 3600, 60, 1 }
const DURATION_UNIT_SUFFIXES = { "d", "h", "m", "s" }
const RICH_TEXT_ESCAPES: { [string]: string } = {
	["&"] = "&amp;",
	["<"] = "&lt;",
	[">"] = "&gt;",
	['"'] = "&quot;",
	["'"] = "&apos;",
}
--- Characters that force an inserted value to be quoted on the command line.
const QUOTE_TRIGGER_PATTERN = "[%s\"'|;&$\\{}]"

--// Helpers

const function formatNumber(value: number): string
	if value ~= value then
		return "NaN"
	elseif value == math.huge then
		return "inf"
	elseif value == -math.huge then
		return "-inf"
	elseif value == math.floor(value) and math.abs(value) < 1e15 then
		return string.format("%d", value)
	end
	-- Up to 4 decimals, trailing zeros trimmed.
	const text = string.format("%.4f", value):gsub("0+$", ""):gsub("%.$", "")
	return text
end

--// Util
const Util = {}

--- Removes leading and trailing whitespace.
function Util.Trim(text: string): string
	return (text:match("^%s*(.-)%s*$") or text)
end

function Util.StartsWith(text: string, prefix: string): boolean
	return text:sub(1, #prefix) == prefix
end

function Util.EndsWith(text: string, suffix: string): boolean
	return suffix == "" or text:sub(-#suffix) == suffix
end

--- Splits on a plain (non-pattern) separator. Empty segments are kept.
function Util.Split(text: string, separator: string): { string }
	const parts: { string } = {}
	if separator == "" then
		for _, codepoint in utf8.codes(text) do
			table.insert(parts, utf8.char(codepoint))
		end
		return parts
	end
	local start = 1
	while true do
		const found = text:find(separator, start, true)
		if found == nil then
			table.insert(parts, text:sub(start))
			return parts
		end
		table.insert(parts, text:sub(start, found - 1))
		start = found + #separator
	end
end

--- Escapes text for safe use inside a RichText label (prevents markup injection from user content).
function Util.EscapeRichText(text: string): string
	return (text:gsub("[&<>\"']", RICH_TEXT_ESCAPES))
end

--- True when `text` must be quoted to survive as a single command-line word.
function Util.NeedsQuoting(text: string): boolean
	return text == "" or text:find(QUOTE_TRIGGER_PATTERN) ~= nil or text:sub(1, 1) == "#" or text:sub(1, 1) == "-"
end

--- Quotes `text` as a double-quoted command-line string when necessary.
function Util.Quote(text: string, force: boolean?): string
	if not force and not Util.NeedsQuoting(text) then
		return text
	end
	const escaped = text:gsub("[\\\"$]", function(char: string): string
		return "\\" .. char
	end):gsub("\n", "\\n"):gsub("\t", "\\t")
	return '"' .. escaped .. '"'
end

--- Truncates to `maxChars` UTF-8 characters, appending an ellipsis when cut.
function Util.Truncate(text: string, maxChars: number): string
	const length = utf8.len(text)
	if length == nil or length <= maxChars then
		return text
	end
	const cut = utf8.offset(text, maxChars)
	if cut == nil then
		return text
	end
	return text:sub(1, cut - 1) .. "…"
end

function Util.FormatNumber(value: number): string
	return formatNumber(value)
end

--- Formats a duration in seconds as a compact human string (`250ms`, `4.2s`, `1h 30m`).
function Util.FormatDuration(seconds: number): string
	if seconds < 1 then
		return string.format("%dms", math.floor(seconds * 1000 + 0.5))
	elseif seconds < 60 then
		return formatNumber(math.floor(seconds * 10 + 0.5) / 10) .. "s"
	end
	const parts: { string } = {}
	local remaining = math.floor(seconds + 0.5)
	for index, size in DURATION_UNIT_SECONDS do
		if remaining >= size then
			const count = remaining // size
			remaining -= count * size
			table.insert(parts, tostring(count) .. DURATION_UNIT_SUFFIXES[index])
		end
	end
	return table.concat(parts, " ")
end

--- Formats any value for display (previews, echo lines, audit). Never errors.
function Util.FormatValue(value: unknown, depth: number?): string
	const level = depth or 0
	if value == nil then
		return "nil"
	elseif type(value) == "string" then
		return value
	elseif type(value) == "number" then
		return formatNumber(value)
	elseif type(value) == "boolean" then
		return if value then "true" else "false"
	elseif typeof(value) == "Instance" then
		if value:IsA("Player") then
			return value.Name
		end
		const ok, fullName = pcall(function(): string
			return value:GetFullName()
		end)
		return if ok then fullName else value.Name
	elseif typeof(value) == "EnumItem" then
		return value.Name
	elseif typeof(value) == "Color3" then
		return "#" .. value:ToHex():upper()
	elseif typeof(value) == "BrickColor" then
		return value.Name
	elseif typeof(value) == "Vector3" then
		return `{formatNumber(value.X)}, {formatNumber(value.Y)}, {formatNumber(value.Z)}`
	elseif typeof(value) == "Vector2" then
		return `{formatNumber(value.X)}, {formatNumber(value.Y)}`
	elseif typeof(value) == "CFrame" then
		const position = value.Position
		return `{formatNumber(position.X)}, {formatNumber(position.Y)}, {formatNumber(position.Z)}`
	elseif type(value) == "table" then
		if level >= 2 then
			return "{…}"
		end
		const items: { string } = {}
		const count = #value
		if count > 0 then
			-- `#value` is a border, so keys 1..count are all present.
			for key, item in pairs(value) do
				if type(key) == "number" and key >= 1 and key <= MAX_FORMAT_ITEMS and key == math.floor(key) then
					items[key] = Util.FormatValue(item, level + 1)
				end
			end
			if count > MAX_FORMAT_ITEMS then
				table.insert(items, `+{count - MAX_FORMAT_ITEMS} more`)
			end
			return table.concat(items, ", ")
		end
		local shown = 0
		for key, item in pairs(value) do
			shown += 1
			if shown > MAX_FORMAT_ITEMS then
				table.insert(items, "…")
				break
			end
			table.insert(items, `{Util.FormatValue(key, level + 1)}={Util.FormatValue(item, level + 1)}`)
		end
		table.sort(items)
		return "{" .. table.concat(items, ", ") .. "}"
	elseif type(value) == "function" then
		return "<function>"
	end
	return tostring(value)
end

--- Stable key identifying an executor (UserId, or "server" for console/server execution).
function Util.ExecutorKey(executor: Player?): string
	if executor == nil then
		return "server"
	end
	return tostring(executor.UserId)
end

--- Display name for an executor.
function Util.ExecutorName(executor: Player?): string
	if executor == nil then
		return "Server"
	end
	return executor.Name
end

--- Returns the keys of a string-keyed dictionary, sorted.
function Util.SortedKeys<V>(dictionary: { [string]: V }): { string }
	const keys: { string } = {}
	for key in dictionary do
		table.insert(keys, key)
	end
	table.sort(keys)
	return keys
end

--- `table.concat` for read-only arrays.
function Util.Join(list: { read string }, separator: string?): string
	const items: { string } = {}
	for _, item in list do
		table.insert(items, item)
	end
	return table.concat(items, separator or "")
end

--- Shallow copy of an array.
function Util.CopyArray<T>(array: { T }): { T }
	return table.move(array, 1, #array, 1, table.create(#array))
end

--- Clamps `value` into [minimum, maximum].
function Util.Clamp(value: number, minimum: number, maximum: number): number
	return math.max(minimum, math.min(maximum, value))
end

--- Levenshtein edit distance (bounded by `limit` for speed; returns limit + 1 when exceeded).
function Util.EditDistance(a: string, b: string, limit: number?): number
	const maxDistance = limit or math.huge
	const lengthA = #a
	const lengthB = #b
	if math.abs(lengthA - lengthB) > maxDistance then
		return maxDistance + 1
	end
	local previous = table.create(lengthB + 1, 0)
	local current = table.create(lengthB + 1, 0)
	for column = 0, lengthB do
		previous[column + 1] = column
	end
	for row = 1, lengthA do
		current[1] = row
		local rowMinimum = row
		const charA = a:byte(row)
		for column = 1, lengthB do
			const cost = if charA == b:byte(column) then 0 else 1
			const value = math.min(previous[column + 1] + 1, current[column] + 1, previous[column] + cost)
			current[column + 1] = value
			if value < rowMinimum then
				rowMinimum = value
			end
		end
		if rowMinimum > maxDistance then
			return maxDistance + 1
		end
		previous, current = current, previous
	end
	return previous[lengthB + 1]
end

return table.freeze(Util)
