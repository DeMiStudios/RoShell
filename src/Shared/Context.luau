--!strict
--[[
	CommandContext: what a command handler receives as `ctx`.

	Output helpers (`Reply`, `Success`, `Info`, `Warn`, `Error`, `Table`, `List`, `KeyValue`, `Color`, `Link`)
	show their output immediately and return a `Reply`, so `return ctx:Success("Done")` and calling them in the
	middle of a long command both work without duplicating output. `ctx:Error(...)` returns a failed Reply that
	fails `&&` chains when returned. `ctx:Value(type, value)` returns a typed value for pipes and `$$`.
]]

--// Imports
const CancelToken = require("./CancelToken")
const Types = require("./Types")
const Util = require("./Util")

--// Types
type Context = Types.Context
type Reply = Types.Reply

export type ContextOptions = {
	Shell: Types.Shell,
	Executor: Player?,
	Command: Types.Command,
	Alias: string,
	RawText: string,
	Dry: boolean,
	Token: Types.CancelToken,
	Options: Types.RunOptions,
	Piped: Types.PipedInput?,
	Emit: (block: Types.Block) -> (),
	Prompt: ((prompt: Types.PromptRequest) -> Types.PromptAnswer)?,
	Data: unknown,
}

--// Constants
const MAX_UNDO = 50
const NO_BLOCKS: { Types.Block } = {}
table.freeze(NO_BLOCKS)

--// Globals
local lastProgressId = 0
-- Every Reply created here; lets `ToReply` recognize replies among the `Output` union without casts.
const knownReplies: { [unknown]: Reply } = setmetatable({}, { __mode = "k" })

--// Helpers

--- Freezes and records a reply (the typed parameter gives the literal its `Reply` type).
const function seal(value: Reply): Reply
	table.freeze(value)
	knownReplies[value] = value
	return value
end

const function reply(ok: boolean, message: string?): Reply
	return seal({ _reply = true, Ok = ok, Message = message, Value = nil, Blocks = NO_BLOCKS })
end

const function nextProgressId(): string
	lastProgressId += 1
	return `progress{lastProgressId}`
end

--- Reads a field of an untyped table.
const function field(value: unknown, key: string): unknown
	if type(value) == "table" then
		for name, item in pairs(value) do
			if name == key then
				return item
			end
		end
	end
	return nil
end

const function text(self: Context, value: string, level: Types.Level)
	self._emit({ Kind = "text", Text = value, Level = level })
end

--// Context class
const ContextClass = {}
ContextClass.__index = ContextClass

function ContextClass.Reply(self: Context, value: string, level: Types.Level?)
	text(self, value, level or "plain")
end

function ContextClass.Success(self: Context, value: string): Reply
	text(self, value, "success")
	return reply(true)
end

function ContextClass.Info(self: Context, value: string): Reply
	text(self, value, "info")
	return reply(true)
end

function ContextClass.Warn(self: Context, value: string): Reply
	text(self, value, "warning")
	return reply(true)
end

function ContextClass.Error(self: Context, value: string): Reply
	text(self, value, "error")
	return reply(false, value)
end

function ContextClass.Table(self: Context, data: Types.TableData): Reply
	const rows: { Types.TableRow } = {}
	for _, row in data.Rows do
		table.insert(rows, table.freeze(table.clone(row)))
	end
	self._emit({ Kind = "table", Title = data.Title, Columns = table.freeze(table.clone(data.Columns)), Rows = rows })
	return reply(true)
end

function ContextClass.List(self: Context, items: { string }, title: string?): Reply
	self._emit({ Kind = "list", Title = title, Items = table.freeze(table.clone(items)) })
	return reply(true)
end

function ContextClass.KeyValue(self: Context, entries: { { Key: string, Value: string } }, title: string?): Reply
	const frozen: { Types.KeyValueEntry } = {}
	for _, entry in entries do
		table.insert(frozen, { Key = entry.Key, Value = entry.Value })
	end
	self._emit({ Kind = "keyvalue", Title = title, Entries = frozen })
	return reply(true)
end

function ContextClass.Color(self: Context, color: Color3, label: string?): Reply
	self._emit({ Kind = "color", Color = color, Label = label or Util.FormatValue(color) })
	return reply(true)
end

function ContextClass.Link(self: Context, label: string, url: string): Reply
	self._emit({ Kind = "link", Text = label, Url = url })
	return reply(true)
end

function ContextClass.Block(self: Context, block: Types.Block)
	self._emit(block)
end

function ContextClass.Value<T>(self: Context, valueType: Types.Type<T>, value: T, display: string?): Reply
	return seal({
		_reply = true,
		Ok = true,
		Value = value,
		ValueType = valueType,
		Display = display or Util.FormatValue(value),
		Blocks = NO_BLOCKS,
	})
end

function ContextClass.Prompt(self: Context, prompt: Types.PromptRequest): Types.PromptAnswer
	const ask = self._prompt
	if ask == nil or self.Token:IsCancelled() then
		return nil
	end
	return ask(prompt)
end

function ContextClass.Confirm(self: Context, message: string, destructive: boolean?): boolean
	if self.Options.Yes then
		return true
	end
	return self:Prompt({ Kind = "confirm", Message = message, Destructive = destructive }) == "yes"
end

function ContextClass.Choose(self: Context, message: string, choices: { string }): string?
	const answer = self:Prompt({ Kind = "choice", Message = message, Choices = choices })
	if answer and table.find(choices, answer) then
		return answer
	end
	return nil
end

function ContextClass.Input(self: Context, message: string, placeholder: string?): string?
	return self:Prompt({ Kind = "text", Message = message, Placeholder = placeholder })
end

function ContextClass.Progress(self: Context, options: Types.ProgressOptions)
	const id = self._progressId or nextProgressId()
	self._progressId = id
	self._emit({
		Kind = "progress",
		Id = id,
		Label = options.Label or self.Command.Name,
		Fraction = if options.Fraction then Util.Clamp(options.Fraction, 0, 1) else nil,
	})
end

function ContextClass.Cancelled(self: Context): boolean
	return self.Token:IsCancelled()
end

function ContextClass.CheckCancelled(self: Context)
	if self.Token:IsCancelled() then
		error(CancelToken.Marker, 0)
	end
end

function ContextClass.GetStore(self: Context, name: string): Types.Store
	return self.Shell.Registry:GetStore(name)
end

function ContextClass.GetData(self: Context): unknown
	return self._data
end

function ContextClass.GetEnv<T>(self: Context, key: Types.EnvKey<T>): T?
	return key._get(self.Shell.Registry)
end

function ContextClass.Broadcast(self: Context, message: string, options: Types.BroadcastOptions?)
	const broadcast = self.Shell._broadcast
	if broadcast then
		broadcast(message, options, self.Executor)
	else
		text(self, message, if options and options.Level then options.Level else "info")
	end
end

function ContextClass.Log(self: Context, message: string)
	table.insert(self._logs, message)
end

function ContextClass.Undoable(self: Context, action: Types.UndoAction)
	const session = self.Shell:GetSession(self.Executor)
	table.insert(session.Undo, action)
	if #session.Undo > MAX_UNDO then
		table.remove(session.Undo, 1)
	end
	table.clear(session.Redo)
end

function ContextClass.Run(self: Context, commandText: string): Types.RunResult
	return self.Shell.Dispatcher:Run({
		Text = commandText,
		Executor = self.Executor,
		Options = { Depth = (self.Options.Depth or 0) + 1, Yes = self.Options.Yes },
		Token = self.Token,
		OnBlock = self._emit,
		OnPrompt = self._prompt,
	})
end

function ContextClass.SendEvent(self: Context, player: Player, name: string, payload: unknown)
	const send = self.Shell._sendEvent
	if send then
		send(player, name, payload)
	end
end

table.freeze(ContextClass)

--// Context module
const ContextModule = {}

--- Creates a command context (used by the dispatcher).
function ContextModule.new(options: ContextOptions): Context
	return setmetatable(
		{
			Shell = options.Shell,
			Executor = options.Executor,
			Command = options.Command,
			Alias = options.Alias,
			RawText = options.RawText,
			IsClient = options.Shell.IsClient,
			IsServer = options.Shell.IsServer,
			Dry = options.Dry,
			Token = options.Token,
			Options = options.Options,
			Piped = options.Piped,
			_emit = options.Emit,
			_prompt = options.Prompt,
			_progressId = nil :: string?,
			_data = options.Data,
			_logs = {},
		},
		ContextClass
	)
end

--- Normalizes whatever a handler returned into a Reply.
function ContextModule.ToReply(output: Types.Output): Reply
	if output == nil then
		return reply(true)
	elseif type(output) == "string" then
		return seal({
			_reply = true,
			Ok = true,
			Value = nil,
			Blocks = { { Kind = "text", Text = output, Level = "plain" } },
		})
	end
	const known = knownReplies[output]
	if known then
		return known
	end
	-- Result<unknown, string>
	if field(output, "Ok") == true then
		const value = field(output, "Value")
		return seal({ _reply = true, Ok = true, Value = value, Display = Util.FormatValue(value), Blocks = NO_BLOCKS })
	end
	const message = tostring(field(output, "Error") or "Failed")
	return seal({
		_reply = true,
		Ok = false,
		Message = message,
		Value = nil,
		Blocks = { { Kind = "text", Text = message, Level = "error" } },
	})
end

--- True when a value is a Reply created by RoShell.
function ContextModule.IsReply(value: unknown): boolean
	return knownReplies[value] ~= nil
end

return table.freeze(ContextModule)
