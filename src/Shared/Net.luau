--!strict
--[[
	Network schema and safety helpers shared by the server and client.

	Everything that crosses the network arrives as `unknown` and is narrowed here, field by field, with size
	limits. Values sent the other way are sanitized (no functions/threads, bounded depth and size). The server never
	trusts client-parsed values: a run request only carries text (re-parsed on the server), an opaque data
	payload, and references to values the server itself produced for that player.
]]

--// Imports
const Constants = require("./Constants")
const Types = require("./Types")

--// Types
export type RunPayload = {
	Id: number,
	Text: string,
	Dry: boolean,
	Yes: boolean,
	IsHuman: boolean,
	Data: unknown,
	PipeRef: string?,
	PipeText: string?,
}

export type PromptAnswerPayload = { Id: number, PromptId: number, Answer: string? }

export type UserDataPayload = { Key: string, Value: unknown }

export type ResultPayload = {
	Ok: boolean,
	Command: string?,
	Message: string?,
	Display: string?,
	Ref: string?,
	TypeName: string?,
	Value: unknown,
	Duration: number,
	Cancelled: boolean,
	--- Number of blocks the server streamed for this run. Blocks travel on the RemoteEvent and results on the
	--- RemoteFunction, which Roblox does not order relative to each other, so the client waits for this many.
	Blocks: number,
}

export type Bucket = { Tokens: number, Updated: number }

--// Constants
const MAX_DATA_DEPTH = 4
const MAX_DATA_ENTRIES = 256
const MAX_STRING = 4096
const MAX_KEY_LENGTH = 64
--- User data keys a client may write.
const USER_DATA_KEYS: { [string]: true } = {
	History = true,
	Aliases = true,
	Binds = true,
	Variables = true,
	Settings = true,
}

--// Helpers

--- Reads a field of an untyped table without trusting its metatable.
const function field(value: unknown, key: string): unknown
	if type(value) ~= "table" then
		return nil
	end
	for name, item in pairs(value) do
		if name == key then
			return item
		end
	end
	return nil
end

const function readString(value: unknown, maxLength: number): string?
	if type(value) == "string" and #value <= maxLength then
		return value
	end
	return nil
end

const function readBoolean(value: unknown): boolean
	return value == true
end

const function readInteger(value: unknown): number?
	if type(value) == "number" and value == math.floor(value) and value >= 0 and value < 2 ^ 31 then
		return value
	end
	return nil
end

--// Net
const Net = {}

Net.UserDataKeys = USER_DATA_KEYS

--- Copies `value` into a network-safe shape (primitives, Roblox datatypes and Instances, nested tables), dropping
--- anything else and bounding depth/size. Returns nil when nothing safe remains.
function Net.Sanitize(value: unknown, depth: number?): unknown
	const level = depth or 0
	const kind = typeof(value)
	if value == nil or kind == "boolean" or kind == "number" then
		return value
	elseif type(value) == "string" then
		return if #value <= MAX_STRING then value else value:sub(1, MAX_STRING)
	elseif kind == "function" or kind == "thread" or kind == "userdata" or kind == "buffer" then
		return nil
	elseif type(value) == "table" then
		if level >= MAX_DATA_DEPTH then
			return nil
		end
		const copy: { [unknown]: unknown } = {}
		local count = 0
		for key, item in pairs(value) do
			count += 1
			if count > MAX_DATA_ENTRIES then
				break
			end
			const keyKind = type(key)
			if keyKind == "string" or keyKind == "number" then
				copy[key] = Net.Sanitize(item, level + 1)
			end
		end
		return copy
	end
	-- Roblox datatypes (Vector3, Color3, CFrame, EnumItem, Instance, ...) replicate as-is.
	return value
end

--- Validates a run request.
function Net.ReadRun(payload: unknown): RunPayload?
	const id = readInteger(field(payload, "Id"))
	const text = readString(field(payload, "Text"), Constants.MaxInputLength)
	if id == nil or text == nil then
		return nil
	end
	const pipe = field(payload, "Pipe")
	return {
		Id = id,
		Text = text,
		Dry = readBoolean(field(payload, "Dry")),
		Yes = readBoolean(field(payload, "Yes")),
		IsHuman = readBoolean(field(payload, "IsHuman")),
		Data = Net.Sanitize(field(payload, "Data")),
		PipeRef = readString(field(pipe, "Ref"), 32),
		PipeText = readString(field(pipe, "Text"), MAX_STRING),
	}
end

--- Validates a prompt answer.
function Net.ReadPromptAnswer(payload: unknown): PromptAnswerPayload?
	const id = readInteger(field(payload, "Id"))
	const promptId = readInteger(field(payload, "PromptId"))
	if id == nil or promptId == nil then
		return nil
	end
	return { Id = id, PromptId = promptId, Answer = readString(field(payload, "Answer"), 1000) }
end

--- Validates a user data write (history, aliases, binds, variables, settings).
function Net.ReadUserData(payload: unknown): UserDataPayload?
	const key = readString(field(payload, "Key"), MAX_KEY_LENGTH)
	if key == nil or not USER_DATA_KEYS[key] then
		return nil
	end
	return { Key = key, Value = Net.Sanitize(field(payload, "Value")) }
end

--- Validates a cancel request.
function Net.ReadCancel(payload: unknown): number?
	return readInteger(field(payload, "Id"))
end

--- Reads a result sent by the server.
function Net.ReadResult(payload: unknown): ResultPayload?
	const ok = field(payload, "Ok")
	if type(ok) ~= "boolean" then
		return nil
	end
	const duration = field(payload, "Duration")
	const blocks = readInteger(field(payload, "Blocks"))
	return {
		Ok = ok,
		Command = readString(field(payload, "Command"), 200),
		Message = readString(field(payload, "Message"), MAX_STRING),
		Display = readString(field(payload, "Display"), MAX_STRING),
		Ref = readString(field(payload, "Ref"), 32),
		TypeName = readString(field(payload, "TypeName"), 200),
		Value = field(payload, "Value"),
		Duration = if type(duration) == "number" then duration else 0,
		Cancelled = field(payload, "Cancelled") == true,
		Blocks = blocks or 0,
	}
end

--- Reads a block sent by the server (only the fields each kind needs; unknown kinds are dropped).
function Net.ReadBlock(payload: unknown): Types.Block?
	const kind = field(payload, "Kind")
	if kind == "text" then
		const text = readString(field(payload, "Text"), MAX_STRING * 4)
		const level = field(payload, "Level")
		if text == nil then
			return nil
		end
		return {
			Kind = "text",
			Text = text,
			Level = if level == "info"
					or level == "success"
					or level == "warning"
					or level == "error"
					or level == "muted"
					or level == "echo" then level
				else "plain",
			Rich = field(payload, "Rich") == true,
		}
	elseif kind == "list" then
		const items: { string } = {}
		const raw = field(payload, "Items")
		if type(raw) == "table" then
			for _, item in pairs(raw) do
				const text = readString(item, MAX_STRING)
				if text then
					table.insert(items, text)
				end
			end
		end
		const level = field(payload, "Level")
		return {
			Kind = "list",
			Title = readString(field(payload, "Title"), 200),
			Items = items,
			Level = if level == "info" or level == "success" or level == "warning" or level == "error" then level
				else nil,
		}
	elseif kind == "table" then
		const columns: { string } = {}
		const rows: { Types.TableRow } = {}
		const rawColumns = field(payload, "Columns")
		if type(rawColumns) == "table" then
			for _, column in pairs(rawColumns) do
				table.insert(columns, readString(column, 200) or "")
			end
		end
		const rawRows = field(payload, "Rows")
		if type(rawRows) == "table" then
			for _, rawRow in pairs(rawRows) do
				const row: { string } = {}
				if type(rawRow) == "table" then
					for _, cell in pairs(rawRow) do
						table.insert(row, readString(cell, 1000) or "")
					end
				end
				table.insert(rows, row)
			end
		end
		return { Kind = "table", Title = readString(field(payload, "Title"), 200), Columns = columns, Rows = rows }
	elseif kind == "keyvalue" then
		const entries: { Types.KeyValueEntry } = {}
		const raw = field(payload, "Entries")
		if type(raw) == "table" then
			for _, entry in pairs(raw) do
				table.insert(entries, {
					Key = readString(field(entry, "Key"), 200) or "",
					Value = readString(field(entry, "Value"), MAX_STRING) or "",
				})
			end
		end
		return { Kind = "keyvalue", Title = readString(field(payload, "Title"), 200), Entries = entries }
	elseif kind == "color" then
		const color = field(payload, "Color")
		if typeof(color) ~= "Color3" then
			return nil
		end
		return { Kind = "color", Color = color, Label = readString(field(payload, "Label"), 200) or "" }
	elseif kind == "progress" then
		const fraction = field(payload, "Fraction")
		return {
			Kind = "progress",
			Id = readString(field(payload, "Id"), 64) or "progress",
			Label = readString(field(payload, "Label"), 200) or "",
			Fraction = if type(fraction) == "number" then math.clamp(fraction, 0, 1) else nil,
		}
	elseif kind == "value" then
		local items: { string }? = nil
		const raw = field(payload, "Items")
		if type(raw) == "table" then
			const list: { string } = {}
			for _, item in pairs(raw) do
				const text = readString(item, 1000)
				if text then
					table.insert(list, text)
				end
			end
			items = list
		end
		return {
			Kind = "value",
			Display = readString(field(payload, "Display"), MAX_STRING) or "",
			TypeName = readString(field(payload, "TypeName"), 200),
			Items = items,
		}
	elseif kind == "link" then
		return {
			Kind = "link",
			Text = readString(field(payload, "Text"), 500) or "",
			Url = readString(field(payload, "Url"), 2000) or "",
		}
	elseif kind == "custom" then
		return {
			Kind = "custom",
			Renderer = readString(field(payload, "Renderer"), 100) or "",
			Data = Net.Sanitize(field(payload, "Data")),
		}
	end
	return nil
end

--- Reads a prompt request sent by the server.
function Net.ReadPrompt(payload: unknown): Types.PromptRequest?
	const kind = field(payload, "Kind")
	const message = readString(field(payload, "Message"), MAX_STRING)
	if message == nil or (kind ~= "confirm" and kind ~= "choice" and kind ~= "text") then
		return nil
	end
	local choices: { string }? = nil
	const raw = field(payload, "Choices")
	if type(raw) == "table" then
		const list: { string } = {}
		for _, choice in pairs(raw) do
			const text = readString(choice, 200)
			if text then
				table.insert(list, text)
			end
		end
		choices = list
	end
	const timeout = field(payload, "Timeout")
	return {
		Kind = kind,
		Title = readString(field(payload, "Title"), 200),
		Message = message,
		Choices = choices,
		Default = readString(field(payload, "Default"), 200),
		Placeholder = readString(field(payload, "Placeholder"), 200),
		Destructive = field(payload, "Destructive") == true,
		Timeout = if type(timeout) == "number" then timeout else nil,
	}
end

--- Token bucket rate limiter: returns true when a request may proceed.
function Net.Take(bucket: Bucket, now: number, capacity: number, perSecond: number): boolean
	bucket.Tokens = math.min(capacity, bucket.Tokens + (now - bucket.Updated) * perSecond)
	bucket.Updated = now
	if bucket.Tokens < 1 then
		return false
	end
	bucket.Tokens -= 1
	return true
end

--- Field reader exposed for adapters that parse engine results.
Net.Field = field

return table.freeze(Net)
