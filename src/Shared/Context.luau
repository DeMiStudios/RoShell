--!strict
--[[
	CommandContext: what a command handler receives as `ctx`.

	Output helpers (`Reply`, `Success`, `Info`, `Warn`, `Error`, `Table`, `List`, `KeyValue`, `Color`, `Link`)
	show their output immediately and return a `Reply`, so `return ctx:Success("Done")` and calling them in the
	middle of a long command both work without duplicating output. `ctx:Error(...)` returns a failed Reply that
	fails `&&` chains when returned. `ctx:Value(type, value)` returns a typed value for pipes and `$$`.
--]]

--// Imports
const CancelToken = require(script.Parent.CancelToken)
const TypeBuilder = require(script.Parent.TypeBuilder)
const TypeFunctions = require(script.Parent.TypeFunctions)
const Types = require(script.Parent.Types)
const Util = require(script.Parent.Util)

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

--// Functions
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
	if typeof(value) == "table" then
		for name, item in value do
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

--// Context Class
const Context = {}
Context.__index = Context

function Context.Reply(self: Context, value: string, level: Types.Level?)
	text(self, value, level or "plain")
end

function Context.Success(self: Context, value: string): Reply
	text(self, value, "success")
	return reply(true)
end

function Context.Info(self: Context, value: string): Reply
	text(self, value, "info")
	return reply(true)
end

function Context.Warn(self: Context, value: string): Reply
	text(self, value, "warning")
	return reply(true)
end

function Context.Error(self: Context, value: string): Reply
	text(self, value, "error")
	return reply(false, value)
end

function Context.Table(self: Context, data: Types.TableData): Reply
	const rows: { Types.TableRow } = {}
	for _, row in data.Rows do
		table.insert(rows, table.freeze(table.clone(row)))
	end
	self._emit({ Kind = "table", Title = data.Title, Columns = table.freeze(table.clone(data.Columns)), Rows = rows })
	return reply(true)
end

function Context.List(self: Context, items: { string }, title: string?): Reply
	self._emit({ Kind = "list", Title = title, Items = table.freeze(table.clone(items)) })
	return reply(true)
end

function Context.KeyValue(self: Context, entries: { { Key: string, Value: string } }, title: string?): Reply
	const frozen: { Types.KeyValueEntry } = {}
	for _, entry in entries do
		table.insert(frozen, { Key = entry.Key, Value = entry.Value })
	end
	self._emit({ Kind = "keyvalue", Title = title, Entries = frozen })
	return reply(true)
end

function Context.Color(self: Context, color: Color3, label: string?): Reply
	self._emit({ Kind = "color", Color = color, Label = label or Util.FormatValue(color) })
	return reply(true)
end

function Context.Link(self: Context, label: string, url: string): Reply
	self._emit({ Kind = "link", Text = label, Url = url })
	return reply(true)
end

function Context.Block(self: Context, block: Types.Block)
	self._emit(block)
end

function Context.Value<Ty>(self: Context, valueType: Ty, value: TypeFunctions.ValueOf<Ty>, display: string?): Reply
	return seal({
		_reply = true,
		Ok = true,
		Value = value,
		-- Every type object is created by a TypeBuilder constructor, whose registry recovers it as a `Type<unknown>`.
		ValueType = TypeBuilder.Lookup(valueType),
		Display = display or Util.FormatValue(value),
		Blocks = NO_BLOCKS,
	})
end

function Context.Prompt(self: Context, prompt: Types.PromptRequest): Types.PromptAnswer
	const ask = self._prompt
	if ask == nil or self.Token:IsCancelled() then
		return nil
	end
	return ask(prompt)
end

function Context.Confirm(self: Context, message: string, destructive: boolean?): boolean
	if self.Options.Yes then
		return true
	end
	return self:Prompt({ Kind = "confirm", Message = message, Destructive = destructive }) == "yes"
end

function Context.Choose(self: Context, message: string, choices: { string }): string?
	const answer = self:Prompt({ Kind = "choice", Message = message, Choices = choices })
	if answer and table.find(choices, answer) then
		return answer
	end
	return nil
end

function Context.Input(self: Context, message: string, placeholder: string?): string?
	return self:Prompt({ Kind = "text", Message = message, Placeholder = placeholder })
end

function Context.Progress(self: Context, options: Types.ProgressOptions)
	const id = self._progressId or nextProgressId()
	self._progressId = id
	self._emit({
		Kind = "progress",
		Id = id,
		Label = options.Label or self.Command.Name,
		Fraction = if options.Fraction then Util.Clamp(options.Fraction, 0, 1) else nil,
	})
end

function Context.Cancelled(self: Context): boolean
	return self.Token:IsCancelled()
end

function Context.CheckCancelled(self: Context)
	if self.Token:IsCancelled() then
		error(CancelToken.Marker, 0)
	end
end

function Context.GetStore(self: Context, name: string): Types.Store
	return self.Shell.Registry:GetStore(name)
end

function Context.GetData(self: Context): unknown
	return self._data
end

function Context.GetEnv<T>(self: Context, key: Types.EnvKey<T>): T?
	return key._get(self.Shell.Registry)
end

function Context.Broadcast(self: Context, message: string, options: Types.BroadcastOptions?): (boolean, string?)
	const broadcast = self.Shell._broadcast
	if broadcast then
		return broadcast(message, options, self.Executor)
	end
	-- No server (a client-only shell, tests): the message is shown here only.
	text(self, message, if options and options.Level then options.Level else "info")
	if options and options.Scope == "global" then
		return false, "there is no server to send it through"
	end
	return true, nil
end

function Context.Log(self: Context, message: string)
	table.insert(self._logs, message)
end

function Context.Undoable(self: Context, action: Types.UndoAction)
	const session = self.Shell:GetSession(self.Executor)
	table.insert(session.Undo, action)
	if #session.Undo > MAX_UNDO then
		table.remove(session.Undo, 1)
	end
	table.clear(session.Redo)
end

function Context.Run(self: Context, commandText: string): Types.RunResult
	return self.Shell.Dispatcher:Run({
		Text = commandText,
		Executor = self.Executor,
		Options = { Depth = (self.Options.Depth or 0) + 1, Yes = self.Options.Yes },
		Token = self.Token,
		OnBlock = self._emit,
		OnPrompt = self._prompt,
	})
end

function Context.SendEvent(self: Context, player: Player, name: string, payload: unknown)
	const send = self.Shell._sendEvent
	if send then
		send(player, name, payload)
	end
end

--- Creates a command context (used by the dispatcher).
function Context.new(options: ContextOptions): Context
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
		Context
	)
end

--- Normalizes whatever a handler returned into a Reply.
function Context.ToReply(output: Types.Output): Reply
	if output == nil then
		return reply(true)
	elseif typeof(output) == "string" then
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
function Context.IsReply(value: unknown): boolean
	return knownReplies[value] ~= nil
end

return table.freeze(Context)
