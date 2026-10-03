--!strict
--[[
	`RoShell.Server`: the authoritative side. Owns the remotes, re-parses and re-validates everything a client asks
	for, enforces permissions, rate limits and payload caps, streams output and prompts to the executor, holds
	result values clients can reference, persists per-user data, and writes the audit log.

		local server = RoShell.Server.new({ Storage = RoShell.Storage.DataStore("RoShell") })
		server.Registry:RegisterDefaultCommands()
		server.Registry:RegisterCommandsIn(ReplicatedStorage.Commands)
		server.Permissions:SetGroup("Admin", RoShell.Permissions.Users({ 123 }))
		server:Start()
]]

--// Imports
const Audit = require("@self/Audit")
const CancelToken = require("./Shared/CancelToken")
const Constants = require("./Shared/Constants")
const Keys = require("./Shared/Keys")
const Net = require("./Shared/Net")
const Platform = require("./Shared/Platform")
const Scheduler = require("@self/Scheduler")
const Shell = require("./Shared/Shell")
const Types = require("./Shared/Types")
const Util = require("./Shared/Util")

--// Types
export type ServerOptions = {
	--- Namespace for remotes and logs (default "RoShell"); lets several shells coexist.
	Name: string?,
	--- Allow every command in Studio (default true).
	StudioBypass: boolean?,
	--- Default command timeout in seconds.
	Timeout: number?,
	Storage: Types.StorageAdapter?,
	Audit: Types.AuditSink?,
	Telemetry: Types.TelemetrySink?,
	Locale: { [string]: string }?,
	--- Remote requests per player: burst size and refill per second (default 20 and 6).
	RateLimit: { Burst: number, PerSecond: number }?,
	--- MessagingService topic for `Scope = "global"` broadcasts.
	BroadcastTopic: string?,
	--- Engine abstraction (tests).
	Platform: Types.PlatformInfo?,
}

export type Server = {
	read Shell: Types.Shell,
	read Registry: Types.Registry,
	read Dispatcher: Types.Dispatcher,
	read Permissions: Types.PermissionManager,
	read Locale: Types.Locale,
	read Scheduler: Scheduler.Scheduler,
	read Audit: Types.AuditSink,
	--- Creates the remotes and starts serving clients. Returns the server for chaining.
	read Start: (self: Server) -> Server,
	--- Runs a command line on the server (as `executor`, or as the server console when nil).
	read Run: (self: Server, text: string, executor: Player?) -> Types.RunResult,
	--- Shows a message to every player (and every server with `Scope = "global"`).
	read Broadcast: (self: Server, message: string, options: Types.BroadcastOptions?, from: Player?) -> (),
	--- Sends a custom event to a client (`client:OnEvent(name, handler)`).
	read SendEvent: (self: Server, player: Player, name: string, payload: unknown) -> (),
	--- Recomputes and sends the list of commands players may see (after permission changes).
	read RefreshVisibility: (self: Server, player: Player?) -> (),
	_options: ServerOptions,
	_started: boolean,
	_function: RemoteFunction?,
	_event: RemoteEvent?,
	_runs: { [Player]: { [number]: Types.CancelToken } },
	_prompts: { [Player]: { [number]: (answer: string?) -> () } },
	_buckets: { [Player]: Net.Bucket },
	_nextPrompt: number,
}

--// Constants
const MAX_USER_DATA_BYTES = 200000
const DEFAULT_BURST = 20
const DEFAULT_RATE = 6

--// Helpers

const function userScope(player: Player): string
	return `user:{player.UserId}`
end

const function warnMessage(message: string)
	warn(`[{Constants.Name}] {message}`)
end

--// Server class
const ServerClass = {}
ServerClass.__index = ServerClass

const function fire(self: Server, player: Player, kind: string, payload: unknown)
	const event = self._event
	if event and player.Parent then
		event:FireClient(player, kind, payload)
	end
end

const function allowRequest(self: Server, player: Player): boolean
	const now = os.clock()
	local bucket = self._buckets[player]
	const limits = self._options.RateLimit
	const burst = if limits then limits.Burst else DEFAULT_BURST
	if bucket == nil then
		bucket = { Tokens = burst, Updated = now }
		self._buckets[player] = bucket
	end
	return Net.Take(bucket, now, burst, if limits then limits.PerSecond else DEFAULT_RATE)
end

--- Asks a client a question and waits for the answer (or nil on timeout/cancel/leave).
const function remotePrompt(
	self: Server,
	player: Player,
	runId: number,
	token: Types.CancelToken,
	prompt: Types.PromptRequest
): Types.PromptAnswer
	self._nextPrompt += 1
	const promptId = self._nextPrompt
	const gate = self.Shell.Platform.Gate()
	local done = false
	local answer: string? = nil
	const pending = self._prompts[player] or {}
	self._prompts[player] = pending
	const function finish(value: string?)
		if done then
			return
		end
		done = true
		answer = value
		pending[promptId] = nil
		gate.Open()
	end
	pending[promptId] = finish
	const disconnect = token:OnCancel(function()
		finish(nil)
	end)
	task.delay(prompt.Timeout or 60, function()
		finish(nil)
	end)
	fire(self, player, "Prompt", { Id = runId, PromptId = promptId, Prompt = prompt })
	gate.Wait()
	disconnect()
	return answer
end

const function handleRun(self: Server, player: Player, payload: Net.RunPayload): Net.ResultPayload
	const shell = self.Shell
	const runs = self._runs[player] or {}
	self._runs[player] = runs
	const token = CancelToken.new()
	runs[payload.Id] = token

	local piped: Types.PipedInput? = nil
	if payload.PipeRef then
		const held = shell:GetSession(player).Held[payload.PipeRef]
		if held and held.Expires >= shell.Platform.Clock() then
			piped = { Value = held.Value, Type = held.Type, Display = held.Display }
		end
	elseif payload.PipeText then
		piped = { Value = nil, Display = payload.PipeText }
	end

	local sent = 0
	const result = shell.Dispatcher:Run({
		Text = payload.Text,
		Executor = player,
		Options = { Dry = payload.Dry, Yes = payload.Yes, Data = payload.Data, IsHuman = payload.IsHuman },
		Token = token,
		Piped = piped,
		OnBlock = function(block: Types.Block)
			sent += 1
			fire(self, player, "Block", { Id = payload.Id, Block = block })
		end,
		OnPrompt = function(prompt: Types.PromptRequest): Types.PromptAnswer
			return remotePrompt(self, player, payload.Id, token, prompt)
		end,
	})
	runs[payload.Id] = nil

	const last = result.Last
	if last == nil then
		return { Ok = result.Ok, Duration = 0, Cancelled = result.Cancelled, Value = nil, Blocks = sent }
	end
	local ref: string? = nil
	if last.Value ~= nil then
		ref = Shell.Hold(shell, player, last)
	end
	const valueType = last.ValueType
	return {
		Ok = last.Ok and not result.Cancelled,
		Command = last.Command,
		Message = last.Message,
		Display = last.Display,
		Ref = ref,
		TypeName = if valueType then valueType.Name else nil,
		Value = Net.Sanitize(last.Value),
		Duration = last.Duration,
		Cancelled = result.Cancelled,
		Blocks = sent,
	}
end

const function visibleCommands(self: Server, player: Player): { string }
	const names: { string } = {}
	for _, command in self.Registry:GetCommands() do
		if self.Permissions:CanSee(player, command) then
			table.insert(names, command.Name)
		end
	end
	return names
end

const function loadUserData(self: Server, player: Player): { [string]: unknown }
	const data: { [string]: unknown } = {}
	for key in Net.UserDataKeys do
		const ok, value = pcall(self.Shell.Storage.Get, self.Shell.Storage, userScope(player), key)
		if ok then
			data[key] = value
		end
	end
	return data
end

const function handleInvoke(self: Server, player: Player, kind: unknown, payload: unknown): unknown
	if not allowRequest(self, player) then
		return { Error = "rate" }
	end
	if kind == "Handshake" then
		return {
			Protocol = Constants.ProtocolVersion,
			Name = self.Shell.Name,
			Visible = visibleCommands(self, player),
			UserData = loadUserData(self, player),
			IsStudio = self.Shell.Platform.IsStudio(),
		}
	elseif kind == "Run" then
		const run = Net.ReadRun(payload)
		if run == nil then
			return { Ok = false, Message = "Invalid request", Duration = 0, Cancelled = false, Blocks = 0 }
		end
		return handleRun(self, player, run)
	end
	return nil
end

const function handleEvent(self: Server, player: Player, kind: unknown, payload: unknown)
	if not allowRequest(self, player) then
		return
	end
	if kind == "Cancel" then
		const id = Net.ReadCancel(payload)
		const runs = self._runs[player]
		const token = if id and runs then runs[id] else nil
		if token then
			token:Cancel("Cancelled by user")
		end
	elseif kind == "PromptAnswer" then
		const answer = Net.ReadPromptAnswer(payload)
		const pending = self._prompts[player]
		const resolve = if answer and pending then pending[answer.PromptId] else nil
		if answer and resolve then
			resolve(answer.Answer)
		end
	elseif kind == "SaveUserData" then
		const data = Net.ReadUserData(payload)
		if data == nil then
			return
		end
		const ok, encoded = pcall(function(): string
			return game:GetService("HttpService"):JSONEncode(data.Value)
		end)
		if not ok or #encoded > MAX_USER_DATA_BYTES then
			return
		end
		pcall(self.Shell.Storage.Set, self.Shell.Storage, userScope(player), data.Key, data.Value)
	end
end

function ServerClass.Start(self: Server): Server
	if self._started then
		return self
	end
	self._started = true
	const ReplicatedStorage = game:GetService("ReplicatedStorage")
	const Players = game:GetService("Players")
	const folderName = self.Shell.Name .. "Remotes"
	const existing = ReplicatedStorage:FindFirstChild(folderName)
	if existing then
		existing:Destroy()
	end
	const folder = Instance.new("Folder")
	folder.Name = folderName
	const remoteFunction = Instance.new("RemoteFunction")
	remoteFunction.Name = "Function"
	remoteFunction.Parent = folder
	const remoteEvent = Instance.new("RemoteEvent")
	remoteEvent.Name = "Event"
	remoteEvent.Parent = folder
	self._function = remoteFunction
	self._event = remoteEvent

	remoteFunction.OnServerInvoke = function(player: Player, kind: unknown, payload: unknown): unknown
		const ok, result = pcall(handleInvoke, self, player, kind, payload)
		if not ok then
			warnMessage(`request from {player.Name} failed: {result}`)
			return { Ok = false, Message = "Server error", Duration = 0, Cancelled = false }
		end
		return result
	end
	remoteEvent.OnServerEvent:Connect(function(player: Player, kind: unknown, payload: unknown)
		const ok, err = pcall(handleEvent, self, player, kind, payload)
		if not ok then
			warnMessage(`event from {player.Name} failed: {err}`)
		end
	end)

	Players.PlayerRemoving:Connect(function(player: Player)
		const runs = self._runs[player]
		if runs then
			for _, token in runs do
				token:Cancel("Player left")
			end
		end
		const prompts = self._prompts[player]
		if prompts then
			for _, resolve in table.clone(prompts) do
				resolve(nil)
			end
		end
		self._runs[player] = nil
		self._prompts[player] = nil
		self._buckets[player] = nil
		self.Scheduler:CancelAll(player)
		self.Shell._sessions[Util.ExecutorKey(player)] = nil
	end)

	-- Hot reload: when commands change, tell clients what they can see now.
	self.Registry.Changed:Connect(function(change: Types.RegistryChange)
		if change == "commands" or change == "all" then
			task.defer(function()
				self:RefreshVisibility(nil)
			end)
		end
	end)

	-- Cross-server broadcasts.
	const topic = self._options.BroadcastTopic or (self.Shell.Name .. "Broadcast")
	task.spawn(function()
		pcall(function()
			game:GetService("MessagingService"):SubscribeAsync(topic, function(message: { Data: unknown })
				const data = message.Data
				const text = Net.Field(data, "Text")
				if type(text) == "string" then
					const level = Net.Field(data, "Level")
					remoteEvent:FireAllClients("Announcement", {
						Text = text,
						Level = if type(level) == "string" then level else "info",
						From = Net.Field(data, "From"),
					})
				end
			end)
		end)
	end)

	folder.Parent = ReplicatedStorage
	return self
end

function ServerClass.Run(self: Server, text: string, executor: Player?): Types.RunResult
	return self.Dispatcher:Run({
		Text = text,
		Executor = executor,
		Options = { Yes = executor == nil },
		OnBlock = function(block: Types.Block)
			if executor then
				fire(self, executor, "Notify", { Block = block })
			elseif block.Kind == "text" then
				print(`[{self.Shell.Name}] {block.Text}`)
			end
		end,
	})
end

function ServerClass.Broadcast(self: Server, message: string, options: Types.BroadcastOptions?, from: Player?)
	const payload = {
		Text = message,
		Level = if options and options.Level then options.Level else "info",
		From = if from then from.Name else nil,
	}
	if options and options.Scope == "global" then
		const topic = self._options.BroadcastTopic or (self.Shell.Name .. "Broadcast")
		const ok = pcall(function()
			game:GetService("MessagingService"):PublishAsync(topic, payload)
		end)
		if ok then
			return
		end
	end
	const event = self._event
	if event then
		event:FireAllClients("Announcement", payload)
	end
end

function ServerClass.SendEvent(self: Server, player: Player, name: string, payload: unknown)
	fire(self, player, "Custom", { Name = name, Payload = Net.Sanitize(payload) })
end

function ServerClass.RefreshVisibility(self: Server, player: Player?)
	const players = if player then { player } else game:GetService("Players"):GetPlayers()
	for _, target in players do
		task.spawn(function()
			fire(self, target, "Visible", { Visible = visibleCommands(self, target) })
		end)
	end
end

table.freeze(ServerClass)

--// Server module
const ServerModule = {}

--- Creates the server shell. Register commands/permissions, then call `:Start()`.
function ServerModule.new(options: ServerOptions?): Server
	const opts: ServerOptions = options or {}
	const platform = opts.Platform or Platform.Roblox()
	assert(
		platform.GetLocalPlayer() == nil or not game:GetService("RunService"):IsClient(),
		"RoShell.Server must be created on the server"
	)
	const shell = Shell.new({
		IsServer = true,
		IsClient = false,
		Platform = platform,
		Options = { Name = opts.Name, StudioBypass = opts.StudioBypass, Timeout = opts.Timeout },
		Storage = opts.Storage,
		Locale = opts.Locale,
	})
	const audit = opts.Audit or Audit.Memory()
	shell._audit = audit
	shell._telemetry = opts.Telemetry

	local server: Server
	const scheduler = Scheduler.new(shell, function(owner: Player?, block: Types.Block)
		if owner then
			fire(server, owner, "Notify", { Block = block })
		elseif block.Kind == "text" then
			print(`[{shell.Name}] {block.Text}`)
		end
	end)
	server = setmetatable(
		{
			Shell = shell,
			Registry = shell.Registry,
			Dispatcher = shell.Dispatcher,
			Permissions = shell.Permissions,
			Locale = shell.Locale,
			Scheduler = scheduler,
			Audit = audit,
			_options = opts,
			_started = false,
			_function = nil :: RemoteFunction?,
			_event = nil :: RemoteEvent?,
			_runs = {},
			_prompts = {},
			_buckets = {},
			_nextPrompt = 0,
		},
		ServerClass
	)

	shell._broadcast = function(message: string, broadcastOptions: Types.BroadcastOptions?, executor: Player?)
		server:Broadcast(message, broadcastOptions, executor)
	end
	shell._sendEvent = function(player: Player, name: string, payload: unknown)
		server:SendEvent(player, name, payload)
	end
	shell.Registry:AddEnv(Keys.Scheduler, scheduler)
	shell.Registry:AddEnv(Keys.Audit, audit)
	return server
end

return table.freeze(ServerModule)
