--!strict
--[[
	The server half of `RoShell.new`: the authoritative side. Owns the remotes, re-parses and re-validates
	everything a client asks for, enforces permissions, rate limits and payload caps, streams output and prompts to
	the executor, holds result values clients can reference, persists per-user data, writes the audit log, and
	describes to each player the commands whose code stays on the server (see Shared/Manifest.luau).
--]]

--// Services
const HttpService = game:GetService("HttpService")
const MessagingService = game:GetService("MessagingService")
const Players = game:GetService("Players")
const ReplicatedFirst = game:GetService("ReplicatedFirst")
const ReplicatedStorage = game:GetService("ReplicatedStorage")

--// Imports
const Audit = require(script.Audit)
const CancelToken = require(script.Parent.Shared.CancelToken)
const Constants = require(script.Parent.Shared.Constants)
const Keys = require(script.Parent.Shared.Keys)
const Manifest = require(script.Parent.Shared.Manifest)
const Net = require(script.Parent.Shared.Net)
const Permissions = require(script.Parent.Shared.Permissions)
const Registry = require(script.Parent.Shared.Registry)
const Scheduler = require(script.Scheduler)
const Shell = require(script.Parent.Shared.Shell)
const Types = require(script.Parent.Shared.Types)
const Util = require(script.Parent.Shared.Util)

--// Types
export type ServerOptions = {
	Admins: { number | Types.Permission }?,
	Commands: (Instance | { Instance })?,
	DefaultCommands: (boolean | { string })?,
	Name: string?,
	StudioBypass: boolean?,
	Timeout: number?,
	Storage: Types.StorageAdapter?,
	Audit: Types.AuditSink?,
	Telemetry: Types.TelemetrySink?,
	Locale: { [string]: string }?,
	RateLimit: { Burst: number, PerSecond: number }?,
	BroadcastTopic: string?,
	Platform: Types.PlatformInfo,
}

type ServerData = {
	read Shell: Types.Shell,
	read Scheduler: Scheduler.Scheduler,
	read Audit: Types.AuditSink,
	_options: ServerOptions,
	_started: boolean,
	_visibilityQueued: boolean,
	-- Players whose command descriptions are rebuilt soon (after they ran something).
	_describeQueued: { [Player]: true },
	_event: RemoteEvent?,
	_runs: { [Player]: { [number]: Types.CancelToken } },
	_prompts: { [Player]: { [number]: (answer: string?) -> () } },
	_buckets: { [Player]: Net.Bucket },
	_nextPrompt: number,
	-- Tags this server's broadcasts, so its own messages coming back through MessagingService are not shown twice.
	_serverId: string,
	-- Why subscribing to other servers' broadcasts failed (reported with the next global broadcast).
	_subscribeError: string?,
}

--// Constants
const MAX_USER_DATA_BYTES = 200000
const DEFAULT_BURST = 20
const DEFAULT_RATE = 6
const PUBLISH_TIMEOUT = 10 -- Longest wait (in seconds) for MessagingService to accept a global broadcast.
const DESCRIBE_DELAY = 0.5 -- Seconds after a run before the runner's command descriptions are rebuilt (bursts send one).
-- Why global broadcasts cannot work in a place file that was never published (MessagingService never answers).
const UNPUBLISHED = "other servers need a published place (MessagingService does not run in unpublished places)"

--// Functions
const function userScope(player: Player): string
	return `user:{player.UserId}`
end

const function warnMessage(message: string)
	warn(`[{Constants.Name}] {message}`)
end

-- `{ 156, RoShell.Permissions.Group(1234567, 250) }` -> one rule granting any of the users or rules.
const function adminRule(admins: { number | Types.Permission }): Types.Permission
	const users: { number } = {}
	const rules: { Types.Permission } = {}
	for _, entry in admins do
		if typeof(entry) == "number" then
			table.insert(users, entry)
		else
			table.insert(rules, entry)
		end
	end
	if #users > 0 then
		table.insert(rules, 1, Permissions.Users(users))
	end
	return if #rules == 1 then rules[1] else Permissions.Any(rules)
end

-- An engine error without its script location (`ServerScriptService.X:12: message` -> `message`).
const function errorText(err: unknown): string
	return (tostring(err):gsub("^[^:]*:%d+: ", ""))
end

-- Publishes to other servers, waiting at most PUBLISH_TIMEOUT seconds for MessagingService to accept it.
const function publish(topic: string, payload: { [string]: unknown }): (boolean, string?)
	if game.PlaceId == 0 then
		return false, UNPUBLISHED
	end
	local finished = false
	local ok = false
	local problem: string? = nil
	task.spawn(function()
		const success, err = pcall(MessagingService.PublishAsync, MessagingService, topic, payload)
		ok = success
		problem = if success then nil else errorText(err)
		finished = true
	end)
	const deadline = os.clock() + PUBLISH_TIMEOUT
	while not finished and os.clock() < deadline do
		task.wait(0.1)
	end
	if not finished then
		return false, `MessagingService did not answer within {PUBLISH_TIMEOUT} seconds`
	end
	return ok, problem
end

-- Command folders that replicate, sent in the handshake: clients load the same modules without being told.
const function sharedContainers(registry: Types.Registry): { Instance }
	const containers: { Instance } = {}
	for _, entry in registry._containers do
		const container = entry.Container
		if container:IsDescendantOf(ReplicatedStorage) or container:IsDescendantOf(ReplicatedFirst) then
			table.insert(containers, container)
		end
	end
	return containers
end

--// Server Class
const Server = {}
Server.__index = Server

export type Server = setmetatable<ServerData, typeof(Server)>

--- Creates the server half of a shell. `RoShell.new` calls this on the server.
function Server.new(options: ServerOptions): Server
	const shell = Shell.new({
		IsServer = true,
		IsClient = false,
		Platform = options.Platform,
		Options = { Name = options.Name, StudioBypass = options.StudioBypass, Timeout = options.Timeout },
		Storage = options.Storage,
		Locale = options.Locale,
	})
	const audit = options.Audit or Audit.Memory()
	shell._audit = audit
	shell._telemetry = options.Telemetry
	const admins = options.Admins
	if admins then
		shell.Permissions:SetAdmins(adminRule(admins))
	end

	local self: Server
	const scheduler = Scheduler.new(shell, function(owner: Player?, block: Types.Block)
		if owner then
			self:_fire(owner, "Notify", { Block = block })
		elseif block.Kind == "text" then
			print(`[{shell.Name}] {block.Text}`)
		end
	end)
	const data: ServerData = {
		Shell = shell,
		Scheduler = scheduler,
		Audit = audit,
		_options = options,
		_started = false,
		_visibilityQueued = false,
		_describeQueued = {},
		_event = nil,
		_runs = {},
		_prompts = {},
		_buckets = {},
		_nextPrompt = 0,
		_serverId = HttpService:GenerateGUID(false),
		_subscribeError = nil,
	}
	self = setmetatable(data, Server)

	shell._broadcast = function(message: string, broadcastOptions: Types.BroadcastOptions?, executor: Player?): (boolean, string?)
		return self:Broadcast(message, broadcastOptions, executor)
	end
	shell._sendEvent = function(player: Player, name: string, payload: unknown)
		self:SendEvent(player, name, payload)
	end
	shell.Registry:AddEnv(Keys.Scheduler, scheduler)
	shell.Registry:AddEnv(Keys.Audit, audit)
	return self
end

--- Registers the commands, creates the remotes and starts serving clients.
function Server.Start(self: Server)
	if self._started then
		return
	end
	self._started = true
	const shell = self.Shell
	Registry.Setup(shell.Registry, {
		DefaultCommands = self._options.DefaultCommands,
		Commands = self._options.Commands,
	})

	const folderName = shell.Name .. "Remotes"
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
	self._event = remoteEvent

	remoteFunction.OnServerInvoke = function(player: Player, kind: unknown, payload: unknown): unknown
		const ok, result = pcall(self._handleInvoke, self, player, kind, payload)
		if not ok then
			warnMessage(`request from {player.Name} failed: {result}`)
			return { Ok = false, Message = "Server error", Duration = 0, Cancelled = false }
		end
		return result
	end
	remoteEvent.OnServerEvent:Connect(function(player: Player, kind: unknown, payload: unknown)
		const ok, err = pcall(self._handleEvent, self, player, kind, payload)
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
		self._describeQueued[player] = nil
		self.Scheduler:CancelAll(player)
		shell._sessions[Util.ExecutorKey(player)] = nil
	end)

	-- Hot reload: when commands change, tell clients what they can see now.
	shell.Registry.Changed:Connect(function(change: Types.RegistryChange)
		if change == "commands" or change == "all" then
			self:_queueRefresh()
		end
	end)

	-- Permission changes (new admins, roles, group rules) change what each player may see.
	shell.Permissions.Changed:Connect(function()
		self:_queueRefresh()
	end)

	-- Cross-server broadcasts: show what other servers publish (this server's own were shown when sent).
	task.spawn(function()
		if game.PlaceId == 0 then
			self._subscribeError = UNPUBLISHED
			return
		end
		const ok, err = pcall(function()
			MessagingService:SubscribeAsync(self:_broadcastTopic(), function(message: { Data: unknown })
				const data = message.Data
				const text = Net.Field(data, "Text")
				if typeof(text) ~= "string" or Net.Field(data, "Server") == self._serverId then
					return
				end
				const level = Net.Field(data, "Level")
				const from = Net.Field(data, "From")
				remoteEvent:FireAllClients("Announcement", {
					Text = text,
					Level = if typeof(level) == "string" then level else "info",
					From = if typeof(from) == "string" then from else nil,
				})
			end)
		end)
		if not ok then
			self._subscribeError = errorText(err)
		end
	end)

	folder.Parent = ReplicatedStorage
end

--- Runs a command line on the server (as `executor`, or as the server console when nil).
function Server.Run(self: Server, text: string, executor: Player?): Types.RunResult
	return self.Shell.Dispatcher:Run({
		Text = text,
		Executor = executor,
		Options = { Yes = executor == nil },
		OnBlock = function(block: Types.Block)
			if executor then
				self:_fire(executor, "Notify", { Block = block })
			elseif block.Kind == "text" then
				print(`[{self.Shell.Name}] {block.Text}`)
			end
		end,
	})
end

--- Shows a message to every player of this server right away, and with `Scope = "global"` publishes it to the
--- other servers through MessagingService. Returns false and why when publishing failed.
function Server.Broadcast(self: Server, message: string, options: Types.BroadcastOptions?, from: Player?): (boolean, string?)
	const level: Types.Level = if options and options.Level then options.Level else "info"
	const sender = if from then from.Name else nil
	-- This server's players see it right away, whatever happens to the other servers.
	const event = self._event
	if event then
		event:FireAllClients("Announcement", { Text = message, Level = level, From = sender })
	end
	if options == nil or options.Scope ~= "global" then
		return true, nil
	end
	const ok, problem = publish(self:_broadcastTopic(), {
		Text = message,
		Level = level,
		From = sender,
		Server = self._serverId,
	})
	if not ok then
		return false, problem
	end
	const subscribeError = self._subscribeError
	if subscribeError then
		-- Published, but this server cannot hear other servers (they may not hear each other either).
		return false, `sent, but receiving broadcasts failed here: {subscribeError}`
	end
	return true, nil
end

--- Sends a custom event to a client (`shell:OnEvent(name, handler)` there).
function Server.SendEvent(self: Server, player: Player, name: string, payload: unknown)
	self:_fire(player, "Custom", { Name = name, Payload = Net.Sanitize(payload) })
end

--- Recomputes and sends what players may see and run (after permission changes).
function Server.RefreshVisibility(self: Server, player: Player?)
	const targets = if player then { player } else Players:GetPlayers()
	for _, target in targets do
		task.spawn(function()
			self:_fire(target, "Visible", {
				Visible = self:_visibleCommands(target),
				Remote = Manifest.Describe(self.Shell, target),
			})
		end)
	end
end

function Server._fire(self: Server, player: Player, kind: string, payload: unknown)
	const event = self._event
	if event and player.Parent then
		event:FireClient(player, kind, payload)
	end
end

-- Several changes in a row (a hot reload registers every command again) send one update.
function Server._queueRefresh(self: Server)
	if self._visibilityQueued then
		return
	end
	self._visibilityQueued = true
	task.defer(function()
		self._visibilityQueued = false
		self:RefreshVisibility(nil)
	end)
end

-- Rebuilds one player's command descriptions shortly (clients ignore descriptions that did not change).
function Server._queueDescribe(self: Server, player: Player)
	if self._describeQueued[player] then
		return
	end
	self._describeQueued[player] = true
	task.delay(DESCRIBE_DELAY, function()
		if self._describeQueued[player] then
			self._describeQueued[player] = nil
			self:RefreshVisibility(player)
		end
	end)
end

function Server._broadcastTopic(self: Server): string
	return self._options.BroadcastTopic or (self.Shell.Name .. "Broadcast")
end

function Server._allowRequest(self: Server, player: Player): boolean
	const now = os.clock()
	const limits = self._options.RateLimit
	const burst = if limits then limits.Burst else DEFAULT_BURST
	local bucket = self._buckets[player]
	if bucket == nil then
		bucket = { Tokens = burst, Updated = now }
		self._buckets[player] = bucket
	end
	return Net.Take(bucket, now, burst, if limits then limits.PerSecond else DEFAULT_RATE)
end

-- The commands the player's console allows: every command the player may run, hidden ones included.
function Server._visibleCommands(self: Server, player: Player): { string }
	return Manifest.Runnable(self.Shell, player)
end

function Server._loadUserData(self: Server, player: Player): { [string]: unknown }
	const storage = self.Shell.Storage
	const data: { [string]: unknown } = {}
	for key in Net.UserDataKeys do
		const ok, value = pcall(storage.Get, storage, userScope(player), key)
		if ok then
			data[key] = value
		end
	end
	return data
end

-- Asks a client a question and waits for the answer (or nil on timeout, cancel or leave).
function Server._prompt(
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
	const function Finish(value: string?)
		if done then
			return
		end
		done = true
		answer = value
		pending[promptId] = nil
		gate.Open()
	end
	pending[promptId] = Finish
	const disconnect = token:OnCancel(function()
		Finish(nil)
	end)
	task.delay(prompt.Timeout or 60, Finish, nil)
	self:_fire(player, "Prompt", { Id = runId, PromptId = promptId, Prompt = prompt })
	gate.Wait()
	disconnect()
	return answer
end

function Server._handleRun(self: Server, player: Player, payload: Net.RunPayload): Net.ResultPayload
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
			self:_fire(player, "Block", { Id = payload.Id, Block = block })
		end,
		OnPrompt = function(prompt: Types.PromptRequest): Types.PromptAnswer
			return self:_prompt(player, payload.Id, token, prompt)
		end,
	})
	runs[payload.Id] = nil
	-- What the command changed may show in its own completions (values of custom types), so describe again.
	self:_queueDescribe(player)

	const last = result.Last
	if last == nil then
		return { Ok = result.Ok, Duration = 0, Cancelled = result.Cancelled, Value = nil, Blocks = sent }
	end
	const ref = if last.Value ~= nil then Shell.Hold(shell, player, last) else nil
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

function Server._handleInvoke(self: Server, player: Player, kind: unknown, payload: unknown): unknown
	if not self:_allowRequest(player) then
		return { Error = "rate" }
	end
	if kind == "Handshake" then
		const shell = self.Shell
		return {
			Protocol = Constants.ProtocolVersion,
			Name = shell.Name,
			Visible = self:_visibleCommands(player),
			UserData = self:_loadUserData(player),
			IsStudio = shell.Platform.IsStudio(),
			Commands = sharedContainers(shell.Registry),
			Remote = Manifest.Describe(shell, player),
		}
	elseif kind == "Run" then
		const run = Net.ReadRun(payload)
		if run == nil then
			return { Ok = false, Message = "Invalid request", Duration = 0, Cancelled = false, Blocks = 0 }
		end
		return self:_handleRun(player, run)
	end
	return nil
end

function Server._handleEvent(self: Server, player: Player, kind: unknown, payload: unknown)
	if not self:_allowRequest(player) then
		return
	end
	if kind == "Cancel" then
		const id = Net.ReadCancel(payload)
		const runs = self._runs[player]
		const token = if id and runs then runs[id] else nil
		if token then
			token:Cancel("Canceled by user")
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
		const ok, encoded = pcall(HttpService.JSONEncode, HttpService, data.Value)
		if not ok or #encoded > MAX_USER_DATA_BYTES then
			return
		end
		const storage = self.Shell.Storage
		pcall(storage.Set, storage, userScope(player), data.Key, data.Value)
	end
end

return table.freeze(Server)
