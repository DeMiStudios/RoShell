--!strict
--[[
	Dispatcher: evaluates (live validation) and runs input scripts.

	Run semantics:
	- Statements (`;` / newline) run in order. In a chain, `a && b` runs b when a succeeded and `a || b` when it
	  failed. In a pipeline `a | b`, a's value is piped into b's pipe argument; a failure stops the pipeline.
	- `${ ... }` embedded commands run first and substitute their result as a single argument value (structured
	  values pass through when the types match). Variables: `$name` (set with `set`), `$$` (last result),
	  `$1..$9`/`$@` (alias parameters), `$fn(args)` (registered functions), `$:id` (server-held values).
	- Each command: resolve -> permissions -> cooldown/rate limit -> validation -> `--dry` preview ->
	  confirmations -> hooks -> middleware -> handler (with timeout and cancellation) -> hooks, audit, telemetry.
	- On a client shell, `ClientRun` runs locally (falling back to the server when it returns nil); `Run` goes
	  through the transport with all variables and embeds already substituted. The server re-parses everything.
]]

--// Imports
const CancelToken = require("./CancelToken")
const Constants = require("./Constants")
const Context = require("./Context")
const Parser = require("./Parser")
const Resolver = require("./Resolver")
const ShellDirectory = require("./ShellDirectory")
const Types = require("./Types")
const Util = require("./Util")

--// Types
type Dispatcher = Types.Dispatcher
type CommandResult = Types.CommandResult
type Shell = Types.Shell

type RunState = {
	Shell: Shell,
	Request: Types.RunRequest,
	Options: Types.RunOptions,
	Token: Types.CancelToken,
	Session: Types.Session,
	Results: { CommandResult },
	Executed: number,
	--- Blocks emitted so far (a command's return value is only displayed when it printed nothing itself).
	Emitted: number,
	Emit: (block: Types.Block) -> (),
}

--// Constants
const NO_BLOCKS: { Types.Block } = {}
table.freeze(NO_BLOCKS)

--// Helpers

const function failure(command: string?, message: string, cancelled: boolean?): CommandResult
	return table.freeze({
		Ok = false,
		Command = command,
		Message = message,
		Value = nil,
		Blocks = { { Kind = "text", Text = message, Level = "error" } :: Types.Block },
		Duration = 0,
		Cancelled = cancelled == true,
	})
end

const function firstError(diagnostics: { read Types.Diagnostic }): string?
	for _, item in diagnostics do
		if item.Severity == "error" then
			return item.Message
		end
	end
	return nil
end

--- Text of the blocks of a result (used as piped/substituted text when there is no structured value).
const function resultText(result: CommandResult): string
	if result.Display then
		return result.Display
	end
	const lines: { string } = {}
	for _, block in result.Blocks do
		if block.Kind == "text" then
			table.insert(lines, block.Text)
		elseif block.Kind == "list" then
			const items: { string } = {}
			for _, item in block.Items do
				table.insert(items, item)
			end
			table.insert(lines, table.concat(items, ","))
		elseif block.Kind == "value" then
			table.insert(lines, block.Display)
		end
	end
	return table.concat(lines, "\n")
end

--- Escapes text so it survives as one bare (unquoted) word, keeping operator characters intact.
const function escapeBare(text: string): string
	if text == "" then
		return '""'
	end
	local escaped = text:gsub("([%s\"'|;$\\{}])", "\\%1")
	if escaped:sub(1, 1) == "#" then
		escaped = "\\" .. escaped
	end
	return escaped
end

--- Runs `callback` in its own thread, honoring cancellation and a timeout. Returns ok, error/result.
const function runGuarded<T>(shell: Shell, token: Types.CancelToken, timeout: number, callback: () -> T): (boolean, T?, string?)
	if not coroutine.isyieldable() then
		-- Called from a non-yieldable context (e.g. a plain unit test): run inline.
		const ok, result = xpcall(callback, function(message: unknown): string
			return tostring(message) .. "\n" .. debug.traceback(nil, 2)
		end)
		if ok then
			return true, result, nil
		end
		return false, nil, tostring(result)
	end

	const platform = shell.Platform
	-- The caller may be an engine callback (OnServerInvoke); the gate parks it in an engine-safe way.
	const gate = platform.Gate()
	local finished = false
	local okResult = false
	local value: T? = nil
	local errorMessage: string? = nil

	const function wake()
		gate.Open()
	end

	const worker = platform.Spawn(function()
		const ok, result = xpcall(callback, function(message: unknown): string
			if CancelToken.IsCancellation(message) then
				return CancelToken.Marker
			end
			return tostring(message) .. "\n" .. debug.traceback(nil, 2)
		end)
		finished = true
		okResult = ok
		if ok then
			value = result
		else
			errorMessage = tostring(result)
		end
		wake()
	end)

	if not finished then
		const disconnect = token:OnCancel(function()
			wake()
		end)
		const timer = if timeout > 0 then platform.Delay(timeout, wake) else nil
		gate.Wait()
		disconnect()
		if timer then
			platform.Cancel(timer)
		end
	end

	if not finished then
		platform.Cancel(worker)
		return false, nil, if token:IsCancelled() then CancelToken.Marker else "timeout"
	end
	return okResult, value, errorMessage
end

--// Dispatcher class
const DispatcherClass = {}
DispatcherClass.__index = DispatcherClass

--- Variables, references and functions available without side effects (live validation).
const function liveProvider(shell: Shell, executor: Player?, session: Types.Session): Resolver.Provider
	return {
		Variable = function(part: Parser.VariablePart): Resolver.Substitution
			if part.Args or part.Name == "$" or part.Name:sub(1, 1) == ":" then
				return { Text = "", Deferred = true, Value = nil }
			end
			if tonumber(part.Name) or part.Name == "@" then
				return { Text = "$" .. part.Name, Deferred = false, Value = nil }
			end
			const value = session.Variables[part.Name]
			if value ~= nil then
				return { Text = value, Deferred = false, Value = nil }
			end
			if shell.Registry:GetFunction(part.Name) then
				return { Text = "", Deferred = true, Value = nil }
			end
			return {
				Text = "",
				Deferred = false,
				Value = nil,
				Error = shell.Locale:Get("resolve.unknownVariable", { name = part.Name }),
			}
		end,
		Embed = function(): Resolver.Substitution
			return { Text = "", Deferred = true, Value = nil }
		end,
	}
end

function DispatcherClass.Evaluate(self: Dispatcher, request: Types.EvaluateRequest): Types.EvaluateResult
	const shell = ShellDirectory.Expect(self._handle)
	const parsed = Parser.Parse(request.Text)
	const diagnostics: { Types.Diagnostic } = table.clone(parsed.Diagnostics)
	const commands: { Types.EvaluatedCommand } = {}
	const provider = liveProvider(shell, request.Executor, shell:GetSession(request.Executor))

	const function walk(script: Parser.Script)
		for _, chain in script.Statements do
			for _, pipeline in chain.Pipelines do
				for position, node in pipeline.Commands do
					if #node.Words == 0 then
						continue
					end
					const resolution = Resolver.Resolve(node, {
						Shell = shell,
						Executor = request.Executor,
						Final = false,
						Provider = provider,
						PipeExpected = position > 1,
					})
					for _, item in resolution.Diagnostics do
						table.insert(diagnostics, item)
					end
					table.insert(commands, {
						Command = resolution.Command,
						Name = resolution.Name,
						Span = node.Span,
						NameSpan = resolution.NameSpan,
						Args = resolution.Args,
						Diagnostics = resolution.Diagnostics,
						Ok = resolution.Ok,
					})
					for _, word in node.Words do
						for _, part in word.Parts do
							if part.Kind == "Embed" then
								walk(part.Script)
							end
						end
					end
				end
			end
		end
	end
	walk(parsed.Script)

	return { Ok = firstError(diagnostics) == nil, Commands = commands, Diagnostics = diagnostics }
end

--- Builds the side-effecting provider for one command execution. Results are memoized per part so a part is
--- evaluated once even when both the resolver and the remote text builder ask for it.
const function executionProvider(state: RunState, run: (text: string, options: Types.RunOptions) -> Types.RunResult): Resolver.Provider
	const shell = state.Shell
	const session = state.Session
	const params = state.Options.Params or {}
	const memo: { [unknown]: Resolver.Substitution } = {}
	const sourceText = state.Request.Text

	const function variable(part: Parser.VariablePart): Resolver.Substitution
		const name = part.Name
		if part.Args then
			const definition = shell.Registry:GetFunction(name)
			if definition == nil then
				return {
					Text = "",
					Deferred = false,
					Value = nil,
					Error = shell.Locale:Get("resolve.unknownFunction", { name = name }),
				}
			end
			const ok, text = pcall(definition.Call, {
				Args = part.Args,
				Executor = state.Request.Executor,
				Shell = shell.Handle,
				Platform = shell.Platform,
			})
			if not ok then
				return { Text = "", Deferred = false, Value = nil, Error = `${name}() failed: {text}` }
			end
			return { Text = text, Deferred = false, Value = nil }
		elseif name == "$" then
			const last = session.Last
			if last == nil then
				return { Text = "", Deferred = false, Value = nil }
			end
			return {
				Text = resultText(last),
				Deferred = false,
				Value = last.Value,
				Type = last.ValueType,
				Ref = last.Ref,
			}
		elseif name == "@" or tonumber(name) then
			-- Positional parameters only exist while an alias runs; elsewhere `$1` is literal text, so alias bodies
			-- can be written in double quotes (`alias hi = "echo Hello $1"`).
			if state.Options.Params == nil then
				return { Text = "$" .. name, Deferred = false, Value = nil }
			end
			if name == "@" then
				return { Text = table.concat(params, " "), Deferred = false, Value = nil }
			end
			return { Text = params[tonumber(name) :: number] or "", Deferred = false, Value = nil }
		elseif name:sub(1, 1) == ":" then
			const held = session.Held[name:sub(2)]
			if held == nil or held.Expires < shell.Platform.Clock() then
				return { Text = "", Deferred = false, Value = nil, Error = `Reference ${name} has expired` }
			end
			return { Text = held.Display, Deferred = false, Value = held.Value, Type = held.Type }
		end
		const value = session.Variables[name]
		if value ~= nil then
			return { Text = value, Deferred = false, Value = nil }
		end
		const definition = shell.Registry:GetFunction(name)
		if definition then
			const ok, text = pcall(definition.Call, {
				Args = {},
				Executor = state.Request.Executor,
				Shell = shell.Handle,
				Platform = shell.Platform,
			})
			if ok then
				return { Text = text, Deferred = false, Value = nil }
			end
			return { Text = "", Deferred = false, Value = nil, Error = `${name} failed: {text}` }
		end
		return {
			Text = "",
			Deferred = false,
			Value = nil,
			Error = shell.Locale:Get("resolve.unknownVariable", { name = name }),
		}
	end

	const function embed(part: Parser.EmbedPart): Resolver.Substitution
		const inner = sourceText:sub(part.Span.Start + 2, part.Span.End - 2)
		const result = run(inner, {
			Depth = (state.Options.Depth or 0) + 1,
			Params = state.Options.Params,
			Yes = state.Options.Yes,
			Quiet = true,
		})
		const last = result.Last
		if not result.Ok or last == nil then
			const message = if last and last.Message then last.Message else firstError(result.Diagnostics) or "failed"
			return { Text = "", Deferred = false, Value = nil, Error = `Embedded command failed: {message}` }
		end
		return { Text = resultText(last), Deferred = false, Value = last.Value, Type = last.ValueType, Ref = last.Ref }
	end

	return {
		Variable = function(part: Parser.VariablePart): Resolver.Substitution
			const cached = memo[part]
			if cached then
				return cached
			end
			const result = variable(part)
			memo[part] = result
			return result
		end,
		Embed = function(part: Parser.EmbedPart): Resolver.Substitution
			const cached = memo[part]
			if cached then
				return cached
			end
			const result = embed(part)
			memo[part] = result
			return result
		end,
	}
end

--- Rebuilds the source text of a command with every variable and embed substituted (for the server).
const function remoteText(node: Parser.CommandNode, provider: Resolver.Provider): string
	const words: { string } = {}
	for _, word in node.Words do
		const substitution = Resolver.Substitute(word, 0, provider)
		if substitution.Ref then
			table.insert(words, "$:" .. substitution.Ref)
		elseif word.Quoted then
			table.insert(words, Util.Quote(substitution.Text, true))
		else
			table.insert(words, escapeBare(substitution.Text))
		end
	end
	return table.concat(words, " ")
end

--- Checks cooldowns and rate limits. Returns a failure message when blocked.
const function checkLimits(self: Dispatcher, shell: Shell, command: Types.Command, executor: Player?): string?
	if executor == nil then
		return nil
	end
	const now = shell.Platform.Clock()
	const executorKey = Util.ExecutorKey(executor)
	if command.Cooldown and command.Cooldown > 0 then
		const key = `{executorKey}:{command._id}`
		const readyAt = self._cooldowns[key]
		if readyAt and readyAt > now then
			return shell.Locale:Get("run.cooldown", { command = command.Name, seconds = math.ceil(readyAt - now) })
		end
		self._cooldowns[key] = now + command.Cooldown
	end
	const limit = command.RateLimit
	if limit then
		const key = if limit.Scope == "global" then `global:{command._id}` else `{executorKey}:{command._id}`
		local bucket = self._rateBuckets[key]
		if bucket == nil then
			bucket = { Tokens = limit.Count, Updated = now }
			self._rateBuckets[key] = bucket
		end
		const refill = (now - bucket.Updated) * (limit.Count / limit.Per)
		bucket.Tokens = math.min(limit.Count, bucket.Tokens + refill)
		bucket.Updated = now
		if bucket.Tokens < 1 then
			const wait = (1 - bucket.Tokens) / (limit.Count / limit.Per)
			return shell.Locale:Get("run.rateLimited", { command = command.Name, seconds = math.ceil(wait) })
		end
		bucket.Tokens -= 1
	end
	return nil
end

--- Converts a handler's output into a result, emitting its remaining blocks.
const function finish(
	state: RunState,
	command: Types.Command,
	output: Types.Output,
	started: number,
	showValue: boolean,
	emittedBefore: number
): CommandResult
	const reply = Context.ToReply(output)
	const blocks: { Types.Block } = {}
	for _, block in reply.Blocks do
		table.insert(blocks, block)
		state.Emit(block)
	end
	const printed = state.Emitted > emittedBefore
	const plain = reply.Value
	if showValue and not printed and type(plain) == "string" and reply.Display == plain then
		-- Plain string results read best as plain output.
		const block: Types.Block = { Kind = "text", Text = plain, Level = "plain" }
		state.Emit(block)
		table.insert(blocks, block)
	elseif showValue and not printed and reply.Value ~= nil and reply.Display then
		local items: { string }? = nil
		const value = reply.Value
		if type(value) == "table" and #value > 1 then
			const labels: { string } = {}
			for _, item in pairs(value) do
				table.insert(labels, Util.FormatValue(item))
			end
			items = labels
		end
		const valueType = reply.ValueType
		const block: Types.Block = {
			Kind = "value",
			Display = reply.Display,
			TypeName = if valueType then valueType.Name else nil,
			Items = items,
		}
		state.Emit(block)
		table.insert(blocks, block)
	end
	return table.freeze({
		Ok = reply.Ok,
		Command = command.Name,
		Message = reply.Message,
		Value = reply.Value,
		ValueType = reply.ValueType,
		Display = reply.Display,
		Blocks = blocks,
		Duration = state.Shell.Platform.Clock() - started,
		Cancelled = false,
	})
end

--- Runs one command node.
const function runCommand(
	self: Dispatcher,
	state: RunState,
	node: Parser.CommandNode,
	piped: Types.PipedInput?,
	showValue: boolean
): CommandResult
	const shell = state.Shell
	const locale = shell.Locale
	const executor = state.Request.Executor
	const token = state.Token
	const started = shell.Platform.Clock()
	const emittedBefore = state.Emitted

	state.Executed += 1
	if state.Executed > Constants.MaxCommandsPerScript then
		return failure(nil, locale:Get("run.tooManyCommands", { count = Constants.MaxCommandsPerScript }))
	end
	if token:IsCancelled() then
		return failure(nil, locale:Get("run.cancelled"), true)
	end

	const nestedRun = function(text: string, options: Types.RunOptions): Types.RunResult
		return self:Run({
			Text = text,
			Executor = executor,
			Options = options,
			Token = token,
			OnBlock = function(block: Types.Block)
				-- Embedded commands are quiet except for errors.
				if block.Kind == "text" and block.Level == "error" then
					state.Emit(block)
				end
			end,
			OnPrompt = state.Request.OnPrompt,
		})
	end
	const provider = executionProvider(state, nestedRun)
	const resolution = Resolver.Resolve(node, {
		Shell = shell,
		Executor = executor,
		Final = true,
		Provider = provider,
		Piped = piped,
	})
	const command = resolution.Command
	if command == nil or not resolution.Ok then
		const message = firstError(resolution.Diagnostics) or locale:Get("resolve.emptyCommand")
		const result = failure(if command then command.Name else resolution.Name, message)
		state.Emit(result.Blocks[1])
		return result
	end
	const values = resolution.Values
	const rawText = state.Request.Text:sub(node.Span.Start, node.Span.End - 1)
	if state.Request.OnCommand then
		state.Request.OnCommand(command.Name, rawText)
	end

	-- Aliases / macros expand into their body with $1..$9 bound to the given words.
	if command._isAlias and command._aliasBody then
		const depth = (state.Options.Depth or 0) + 1
		if depth > Constants.MaxAliasDepth then
			return failure(command.Name, locale:Get("run.aliasDepth", { count = Constants.MaxAliasDepth }))
		end
		const params: { string } = {}
		const rawParams = values.args
		if type(rawParams) == "table" then
			for _, item in pairs(rawParams) do
				table.insert(params, tostring(item))
			end
		end
		const result = self:Run({
			Text = command._aliasBody,
			Executor = executor,
			Options = { Depth = depth, Params = params, Yes = state.Options.Yes or resolution.Yes, IsHuman = false },
			Token = token,
			OnBlock = state.Emit,
			OnPrompt = state.Request.OnPrompt,
			OnCommand = state.Request.OnCommand,
		})
		return result.Last or failure(command.Name, locale:Get("resolve.emptyCommand"))
	end

	-- Permissions and limits.
	const allowed, denial = shell.Permissions:CanRun(executor, command, values)
	if not allowed then
		const result = failure(command.Name, denial or locale:Get("run.permissionDenied", { command = command.Name }))
		state.Emit(result.Blocks[1])
		return result
	end
	const limited = checkLimits(self, shell, command, executor)
	if limited then
		const result = failure(command.Name, limited)
		state.Emit(result.Blocks[1])
		return result
	end

	const dry = resolution.Dry or state.Options.Dry == true
	const yes = resolution.Yes or state.Options.Yes == true
	const runOptions: Types.RunOptions = {
		Dry = dry,
		Yes = yes,
		Data = state.Options.Data,
		IsHuman = state.Options.IsHuman,
		Params = state.Options.Params,
		Depth = state.Options.Depth,
	}
	const remote = shell.IsClient and command._run ~= nil and command._clientRun == nil
	const ctx = Context.new({
		Shell = shell,
		Executor = executor,
		Command = command,
		Alias = resolution.Name,
		RawText = rawText,
		Dry = dry,
		Token = token,
		Options = runOptions,
		Piped = piped,
		Emit = state.Emit,
		Prompt = state.Request.OnPrompt,
		Data = state.Options.Data,
	})

	-- Cross-argument validation, before dry runs and confirmations (never ask about a line that cannot run).
	const validate = command._validate
	if validate then
		const ok, valid, message = pcall(validate, ctx, values)
		if not ok or not valid then
			const result = failure(command.Name, if ok then message or "Invalid arguments" else tostring(valid))
			state.Emit(result.Blocks[1])
			return result
		end
	end

	-- Dry runs.
	if dry and not remote then
		const preview = command._preview
		if not command.SupportsDryRun or preview == nil then
			const result = failure(command.Name, locale:Get("run.dryUnsupported", { command = command.Name }))
			state.Emit(result.Blocks[1])
			return result
		end
		const ok, lines = pcall(preview, ctx, values)
		if not ok then
			return failure(command.Name, locale:Get("run.error", { command = command.Name, message = tostring(lines) }))
		end
		state.Emit({
			Kind = "list",
			Title = locale:Get("run.dryRun", { command = command.Name }),
			Items = lines,
			Level = "info",
		})
		return table.freeze({
			Ok = true,
			Command = command.Name,
			Value = nil,
			Blocks = NO_BLOCKS,
			Duration = shell.Platform.Clock() - started,
			Cancelled = false,
		})
	end

	-- Confirmations run where the handler runs.
	if not remote and not yes then
		if command.Destructive
			and not ctx:Confirm(locale:Get("run.confirmDestructive", { command = command.Name }), true) then
			const result = failure(command.Name, locale:Get("run.declined"), true)
			state.Emit(result.Blocks[1])
			return result
		end
		for _, arg in command.Args do
			const threshold = arg.Options.RequireConfirmAbove
			const value = values[arg.Name]
			if threshold and type(value) == "table" and #value > threshold then
				if not ctx:Confirm(locale:Get("run.confirmMany", { count = #value, plural = arg.Type.Name }), true) then
					const result = failure(command.Name, locale:Get("run.declined"), true)
					state.Emit(result.Blocks[1])
					return result
				end
			end
		end
	end

	-- BeforeRun hooks (global, then the command's own).
	const registry = shell.Registry
	for _, entry in registry._beforeRun do
		const blocked = entry.Hook(ctx)
		if blocked then
			const result = failure(command.Name, blocked)
			state.Emit(result.Blocks[1])
			return result
		end
	end
	if command.Hooks and command.Hooks.BeforeRun then
		const blocked = command.Hooks.BeforeRun(ctx)
		if blocked then
			const result = failure(command.Name, blocked)
			state.Emit(result.Blocks[1])
			return result
		end
	end

	const timeout = command.Timeout or shell.Options.Timeout or Constants.DefaultTimeout

	const function invoke(): CommandResult
		if shell.IsClient then
			const clientRun = command._clientRun
			if clientRun then
				const ok, output, err = runGuarded(shell, token, timeout, function(): Types.Output
					return clientRun(ctx, values)
				end)
				if not ok then
					if err and CancelToken.IsCancellation(err) then
						return failure(command.Name, locale:Get("run.cancelled"), true)
					elseif err == "timeout" then
						return failure(
							command.Name,
							locale:Get("run.timeout", { command = command.Name, seconds = timeout })
						)
					end
					return failure(
						command.Name,
						locale:Get("run.error", { command = command.Name, message = err or "error" })
					)
				end
				if output ~= nil or command._run == nil then
					return finish(state, command, output, started, showValue, emittedBefore)
				end
			end
			if command._run then
				const transport = shell._transport
				if transport == nil then
					return failure(command.Name, locale:Get("run.notConnected"))
				end
				local data: unknown = state.Options.Data
				if command._data then
					const ok, collected = pcall(command._data, ctx, values)
					if ok then
						data = collected
					end
				end
				-- A piped server value is forwarded by reference; anything else as text the server re-parses.
				const pipeRef = if piped then piped.Ref else nil
				const pipe: { Ref: string?, Text: string? }? = if piped then {
						Ref = pipeRef,
						Text = if pipeRef then nil else piped.Display,
					}
					else nil
				return transport:RunRemote(
					{
						Text = remoteText(node, provider),
						Options = { Dry = dry, Yes = yes, Data = data, IsHuman = state.Options.IsHuman },
						Pipe = pipe,
					},
					token,
					state.Emit,
					state.Request.OnPrompt
				)
			end
			return failure(command.Name, locale:Get("run.noImplementation", { command = command.Name }))
		end

		const handler = command._run
		if handler == nil then
			return failure(command.Name, locale:Get("run.clientOnly", { command = command.Name }))
		end
		const ok, output, err = runGuarded(shell, token, timeout, function(): Types.Output
			return handler(ctx, values)
		end)
		if not ok then
			if err and CancelToken.IsCancellation(err) then
				return failure(command.Name, locale:Get("run.cancelled"), true)
			elseif err == "timeout" then
				return failure(command.Name, locale:Get("run.timeout", { command = command.Name, seconds = timeout }))
			end
			return failure(command.Name, locale:Get("run.error", { command = command.Name, message = err or "error" }))
		end
		return finish(state, command, output, started, showValue, emittedBefore)
	end

	-- Middleware wraps the invocation (lowest priority outermost).
	local chain: () -> CommandResult = invoke
	for index = #registry._middleware, 1, -1 do
		const middleware = registry._middleware[index].Middleware
		const nextHandler = chain
		chain = function(): CommandResult
			return middleware(ctx, nextHandler)
		end
	end
	local result = chain()
	if not result.Ok and result.Message and #result.Blocks > 0 and result.Blocks[1].Kind == "text" then
		-- Failures produced by `failure()` inside invoke have not been emitted yet.
		const first = result.Blocks[1]
		if first.Kind == "text" and first.Level == "error" and first.Text == result.Message and not remote then
			state.Emit(first)
		end
	end
	if remote and not result.Ok and result.Message and #result.Blocks > 0 then
		-- Remote failures carry their blocks from the server; they were emitted through the transport.
		result = result
	end

	-- AfterRun / OnError hooks, audit, telemetry.
	for _, entry in registry._afterRun do
		pcall(entry.Hook, ctx, result)
	end
	if command.Hooks and command.Hooks.AfterRun then
		pcall(command.Hooks.AfterRun, ctx, result)
	end
	if not result.Ok then
		for _, entry in registry._onError do
			pcall(entry.Hook, ctx, result.Message or "")
		end
		if command.Hooks and command.Hooks.OnError then
			pcall(command.Hooks.OnError, ctx, result.Message or "")
		end
	end
	const audit = shell._audit
	if audit and shell.IsServer then
		const formatted: { [string]: string } = {}
		for _, resolved in resolution.Args do
			if resolved.Present then
				formatted[resolved.Arg.Name] = resolved.Display or Util.FormatValue(resolved.Value)
			end
		end
		pcall(audit.Write, audit, {
			Time = shell.Platform.Now(),
			Executor = Util.ExecutorName(executor),
			ExecutorId = if executor then executor.UserId else nil,
			Raw = rawText,
			Command = command.Name,
			Args = formatted,
			Ok = result.Ok,
			Result = result.Message or result.Display,
			Duration = result.Duration,
		})
	end
	const telemetry = shell._telemetry
	if telemetry then
		pcall(telemetry.Record, telemetry, {
			Command = command.Name,
			Ok = result.Ok,
			Duration = result.Duration,
			Executor = executor,
		})
	end
	return result
end

const function runPipeline(self: Dispatcher, state: RunState, pipeline: Parser.Pipeline, initial: Types.PipedInput?): CommandResult
	local piped = initial
	local result: CommandResult? = nil
	for index, node in pipeline.Commands do
		const isLast = index == #pipeline.Commands
		result = runCommand(self, state, node, piped, isLast and not state.Options.Quiet)
		const current = result :: CommandResult
		table.insert(state.Results, current)
		if not current.Ok then
			return current
		end
		if not isLast then
			piped = {
				Value = current.Value,
				Type = current.ValueType,
				Display = resultText(current),
				Ref = current.Ref,
			}
		end
	end
	return result or failure(nil, ShellDirectory.Expect(self._handle).Locale:Get("resolve.emptyCommand"))
end

function DispatcherClass.Run(self: Dispatcher, request: Types.RunRequest): Types.RunResult
	const shell = ShellDirectory.Expect(self._handle)
	const options: Types.RunOptions = request.Options or {}
	const token = request.Token or CancelToken.new()
	const results: { CommandResult } = {}
	const collected: { Types.Block } = {}
	const onBlock = request.OnBlock

	if #request.Text > Constants.MaxInputLength then
		const result = failure(nil, shell.Locale:Get("run.inputTooLong"))
		if onBlock then
			onBlock(result.Blocks[1])
		end
		return { Ok = false, Results = { result }, Last = result, Diagnostics = {}, Cancelled = false }
	end

	const parsed = Parser.Parse(request.Text)
	const syntaxError = firstError(parsed.Diagnostics)
	if syntaxError then
		const result = failure(nil, shell.Locale:Get("run.syntaxError", { message = syntaxError }))
		if onBlock then
			onBlock(result.Blocks[1])
		end
		return { Ok = false, Results = { result }, Last = result, Diagnostics = parsed.Diagnostics, Cancelled = false }
	end

	const session = shell:GetSession(request.Executor)
	-- Declared first so `Emit` can count into it.
	local state: RunState
	state = {
		Shell = shell,
		Request = request,
		Options = options,
		Token = token,
		Session = session,
		Results = results,
		Executed = 0,
		Emitted = 0,
		Emit = function(block: Types.Block)
			state.Emitted += 1
			table.insert(collected, block)
			if onBlock then
				onBlock(block)
			end
		end,
	}

	local last: CommandResult? = nil
	local initialPipe = request.Piped
	for _, chain in parsed.Script.Statements do
		if token:IsCancelled() then
			break
		end
		local chainResult = runPipeline(self, state, chain.Pipelines[1], initialPipe)
		initialPipe = nil
		for index, operator in chain.Operators do
			if token:IsCancelled() then
				break
			end
			if (operator == "&&" and chainResult.Ok) or (operator == "||" and not chainResult.Ok) then
				chainResult = runPipeline(self, state, chain.Pipelines[index + 1], nil)
			end
		end
		last = chainResult
	end

	if (options.Depth or 0) == 0 and last then
		session.Last = last
	end
	const cancelled = token:IsCancelled()
	return {
		Ok = last ~= nil and last.Ok and not cancelled,
		Results = results,
		Last = last,
		Diagnostics = parsed.Diagnostics,
		Cancelled = cancelled,
	}
end

table.freeze(DispatcherClass)

--// Dispatcher module
const DispatcherModule = {}

function DispatcherModule.new(handle: Types.ShellHandle): Dispatcher
	return setmetatable({ _cooldowns = {}, _rateBuckets = {}, _handle = handle }, DispatcherClass)
end

DispatcherModule.EscapeBare = escapeBare
DispatcherModule.ResultText = resultText

return table.freeze(DispatcherModule)
