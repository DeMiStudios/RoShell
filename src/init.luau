--!strict
--[[
	RoShell: a typed, extensible command console for Roblox. One module serves both sides:

		const RoShell = require(ReplicatedStorage.Packages.RoShell)

		-- Server (a Script): the built-in commands, yours (from anywhere), and who may run everything.
		RoShell.new({ Admins = { 156 }, Commands = ServerStorage.Commands }):Start()

		-- Client (a LocalScript): the console, with every command the server lets this player run.
		RoShell.new():Start()

	Commands are typed end to end:

		return RoShell.Command({
			Name = "give",
			Args = {
				{ targets = RoShell.Arg(RoShell.Types.Players) },
				{ amount = RoShell.Default(RoShell.Types.Integer, 1) },
			},
		}):Run(function(ctx, args)
			-- args.targets: { Player }, args.amount: number
		end)
--]]

--// Services
const RunService = game:GetService("RunService")

--// Imports
const Audit = require("@self/Server/Audit")
const BuiltInTypes = require("@self/Shared/BuiltInTypes")
const Client = require("@self/Client")
const Command = require("@self/Shared/Command")
const Constants = require("@self/Shared/Constants")
const DataStoreStorage = require("@self/Server/DataStoreStorage")
const Docs = require("@self/Shared/Docs")
const Fuzzy = require("@self/Shared/Fuzzy")
const Keymap = require("@self/Client/UI/Keymap")
const Keys = require("@self/Shared/Keys")
const Permissions = require("@self/Shared/Permissions")
const Platform = require("@self/Shared/Platform")
const Registry = require("@self/Shared/Registry")
const Result = require("@self/Shared/Result")
const Scheduler = require("@self/Server/Scheduler")
const Server = require("@self/Server")
const Settings = require("@self/Client/Settings")
const ShellDirectory = require("@self/Shared/ShellDirectory")
const Signal = require("@self/Shared/Signal")
const Storage = require("@self/Shared/Storage")
const Test = require("@self/Shared/Test")
const Theme = require("@self/Client/UI/Theme")
const TypeBuilder = require("@self/Shared/TypeBuilder")
const Types = require("@self/Shared/Types")

--// Types
export type Command = Types.Command
export type CommandBuilder<V> = Types.CommandBuilder<V>
export type Context = Types.Context
export type Type<T> = Types.Type<T>
export type Shell = Types.Shell
export type Registry = Types.Registry
export type Block = Types.Block
export type Level = Types.Level
export type Permission = Types.Permission
export type Plugin = Types.Plugin
export type StorageAdapter = Types.StorageAdapter
export type AuditSink = Types.AuditSink
export type EnvKey<T> = Types.EnvKey<T>
export type RunResult = Types.RunResult
export type MapEntry<V> = TypeBuilder.MapEntry<V>
export type ThemeOptions = Types.ThemeOptions
export type OutputRenderer = Types.OutputRenderer
export type CommandHooks = Types.CommandHooks
export type Candidate<T> = Types.Candidate<T>
export type Keymap = Keymap.Keymap
export type Settings = Settings.Settings
export type Scheduler = Scheduler.Scheduler

--- Everything `RoShell.new` accepts. Every field is optional, and each side ignores the other side's options, so
--- one table can serve both.
export type Options = {
	--- Your commands: a folder (or ModuleScript) or a list of them, loaded on `Start` (subfolders at any depth).
	--- They can live anywhere. On the server, players receive a description of the commands they may run, so the
	--- console completes and checks them while their code stays on the server (ServerStorage keeps it private).
	--- A client loads the folders it can reach itself (those it lists here and the server's replicated ones).
	Commands: (Instance | { Instance })?,
	--- The built-in commands, registered on `Start`: true (default) for all, a list of groups (`{ "Help",
	--- "Utility" }`), or false for none. Calling `Registry:RegisterDefaultCommands()` yourself also works.
	DefaultCommands: (boolean | { string })?,
	--- Namespace for remotes and logs (default "RoShell"); lets several shells coexist. Both sides must agree.
	Name: string?,
	--- Allow every command in Studio (default true).
	StudioBypass: boolean?,
	--- Message overrides by key (e.g. `{ ["run.cancelled"] = "Annulé" }`).
	Locale: { [string]: string }?,
	--- Engine abstraction (tests). Also decides the side: a platform with a local player makes a client.
	Platform: Types.PlatformInfo?,

	--- (Server) Players who may run every command: user ids and/or permission rules, e.g.
	--- `{ 156, RoShell.Permissions.Group(1234567, 250) }`. Other players get what the commands' own rules allow.
	Admins: { number | Types.Permission }?,
	--- (Server) Default command timeout in seconds.
	Timeout: number?,
	--- (Server) Where players' history, aliases, binds, variables and console settings are kept. Default: in
	--- memory, for the life of the server. `RoShell.Storage.DataStore("RoShell")` keeps them between sessions.
	Storage: Types.StorageAdapter?,
	--- (Server) Where every command run is recorded (default: `RoShell.Audit.Memory()`).
	Audit: Types.AuditSink?,
	--- (Server) Receives timing and outcome events for analytics.
	Telemetry: Types.TelemetrySink?,
	--- (Server) Remote requests per player: burst size and refill per second (default 20 and 6).
	RateLimit: { Burst: number, PerSecond: number }?,
	--- (Server) MessagingService topic for `Scope = "global"` broadcasts.
	BroadcastTopic: string?,

	--- (Client) Create the console UI (default true). Without it the client still runs commands from code and binds.
	Interface: boolean?,
	--- (Client) Keys that toggle the console (default F2 and `).
	ActivationKeys: { Enum.KeyCode }?,
	--- (Client) Require pressing an activation key 5 times quickly to open the console the first time.
	MashToEnable: boolean?,
	--- (Client) Hide the console when clicking outside of it (default true).
	HideOnLostFocus: boolean?,
	--- (Client) Free the mouse while the console is open (first-person games).
	ActivationUnlocksMouse: boolean?,
	--- (Client) Show a floating button to open the console on touch and gamepad devices (default true).
	TouchButton: boolean?,
	--- (Client) Title shown in the console header.
	PlaceName: string?,
	--- (Client) Remapped console keys (whole actions are replaced), e.g.
	--- `{ Palette = { { Key = Enum.KeyCode.P, Ctrl = true } } }`.
	Keymap: Keymap.Keymap?,
	--- (Client) Initial values for settings the player has not changed (e.g. `{ theme = "Graphite" }`).
	Settings: { [string]: string | number | boolean }?,
}

type RoShellData = {
	--- The shell core: registry, dispatcher, permissions, locale, platform, storage and sessions.
	read Shell: Types.Shell,
	--- Commands, types, hooks, middleware, selectors, `$functions`, plugins and themes.
	read Registry: Types.Registry,
	--- Parses, checks and runs command lines.
	read Dispatcher: Types.Dispatcher,
	--- Admins, roles and per-group rules. On clients it mirrors what the server allows.
	read Permissions: Types.PermissionManager,
	read Locale: Types.Locale,
	--- True on the server (and in edit-mode plugins).
	read IsServer: boolean,
	--- True on clients.
	read IsClient: boolean,
	--- (Server) Scheduled commands (`in`, `every`, `repeat`). Nil on clients.
	read Scheduler: Scheduler.Scheduler?,
	--- (Server) The audit sink every command run is written to. Nil on clients.
	read Audit: Types.AuditSink?,
	--- (Client) The player's console settings. Nil on the server.
	read Settings: Settings.Settings?,
	--- (Client) Fires when the console opens or closes.
	read Toggled: Types.Signal<boolean>,
	--- (Client) Fires after each line typed in the console finishes.
	read Executed: Types.Signal<string, Types.RunResult>,
	_server: Server.Server?,
	_client: Client.Client?,
}

--// Constants
const IS_STUDIO = RunService:IsStudio()

--// Functions
-- Errors in Studio, warns with a traceback in live servers. Both report from the caller's frame.
const function safeAssert<T>(condition: T, message: string?): T
	if not condition then
		const text = message or "Assertion failed!"
		if IS_STUDIO then
			error(text, 3)
		end
		warn(debug.traceback(text, 3))
	end
	return condition
end

const function wrongSide(serverOnly: boolean, method: string)
	safeAssert(false, `[{Constants.Name}] {method} is {if serverOnly then "server" else "client"}-only`)
end

--// RoShell Class
const RoShellClass = {}
RoShellClass.__index = RoShellClass

--- A shell made by `RoShell.new`: the server side or a player's console, depending on where it was created.
export type RoShell = setmetatable<RoShellData, typeof(RoShellClass)>

--- Registers the commands and starts: the server creates its remotes and serves players, a client connects to the
--- server and opens the console. Returns the shell, so `RoShell.new(options):Start()` is the whole setup.
function RoShellClass.Start(self: RoShell): RoShell
	const server = self._server
	if server then
		server:Start()
	end
	const client = self._client
	if client then
		client:Start()
	end
	return self
end

--- Runs a command line from code, without echo or history. On the server it runs as `executor` (or as the server
--- console when nil); on a client it runs as the local player.
function RoShellClass.Run(self: RoShell, text: string, executor: Player?): Types.RunResult
	assert(typeof(text) == "string", `Expected "text" parameter to be a string`)
	const client = self._client
	if client then
		safeAssert(
			executor == nil or executor == self.Shell.Platform.GetLocalPlayer(),
			`[{Constants.Name}] Run on a client always runs as the local player`
		)
		return client:Run(text)
	end
	return (self._server :: Server.Server):Run(text, executor)
end

--- (Server) Shows a message to every player of this server right away, and with `Scope = "global"` publishes it
--- to the other servers through MessagingService. Returns false and why when publishing failed.
function RoShellClass.Broadcast(self: RoShell, message: string, options: Types.BroadcastOptions?, from: Player?): (boolean, string?)
	const server = self._server
	if not server then
		wrongSide(true, "Broadcast")
		return false, "Broadcast is server-only"
	end
	return server:Broadcast(message, options, from)
end

--- (Server) Sends a custom event to a player's client, which handles it with `shell:OnEvent(name, handler)`.
function RoShellClass.SendEvent(self: RoShell, player: Player, name: string, payload: unknown)
	const server = self._server
	if not server then
		wrongSide(true, "SendEvent")
		return
	end
	server:SendEvent(player, name, payload)
end

--- (Server) Recomputes and sends what players may see and run. Permission changes made through `Permissions`
--- already do this; call it after changing what your own `Predicate` rules depend on.
function RoShellClass.RefreshVisibility(self: RoShell, player: Player?)
	const server = self._server
	if not server then
		wrongSide(true, "RefreshVisibility")
		return
	end
	server:RefreshVisibility(player)
end

--- (Client) Runs a command line as if it was typed in the console (echo and history).
function RoShellClass.Execute(self: RoShell, text: string)
	const client = self._client
	if not client then
		wrongSide(false, "Execute")
		return
	end
	client:Execute(text)
end

--- (Client) Opens the console.
function RoShellClass.Show(self: RoShell)
	const client = self._client
	if not client then
		wrongSide(false, "Show")
		return
	end
	client:Show()
end

--- (Client) Closes the console.
function RoShellClass.Hide(self: RoShell)
	const client = self._client
	if not client then
		wrongSide(false, "Hide")
		return
	end
	client:Hide()
end

--- (Client) Opens the console when it is closed, and closes it when it is open.
function RoShellClass.Toggle(self: RoShell)
	const client = self._client
	if not client then
		wrongSide(false, "Toggle")
		return
	end
	client:Toggle()
end

--- (Client) True while the console is open.
function RoShellClass.IsVisible(self: RoShell): boolean
	const client = self._client
	if not client then
		wrongSide(false, "IsVisible")
		return false
	end
	return client:IsVisible()
end

--- (Client) Enables or disables the console (a disabled console cannot be opened).
function RoShellClass.SetEnabled(self: RoShell, enabled: boolean)
	const client = self._client
	if not client then
		wrongSide(false, "SetEnabled")
		return
	end
	client:SetEnabled(enabled)
end

--- (Client) Keys that toggle the console.
function RoShellClass.SetActivationKeys(self: RoShell, keys: { Enum.KeyCode })
	const client = self._client
	if not client then
		wrongSide(false, "SetActivationKeys")
		return
	end
	client:SetActivationKeys(keys)
end

--- (Client) Free the mouse while the console is open (first-person games).
function RoShellClass.SetActivationUnlocksMouse(self: RoShell, enabled: boolean)
	const client = self._client
	if not client then
		wrongSide(false, "SetActivationUnlocksMouse")
		return
	end
	client:SetActivationUnlocksMouse(enabled)
end

--- (Client) Require pressing an activation key 5 times quickly to open the console the first time.
function RoShellClass.SetMashToEnable(self: RoShell, enabled: boolean)
	const client = self._client
	if not client then
		wrongSide(false, "SetMashToEnable")
		return
	end
	client:SetMashToEnable(enabled)
end

--- (Client) Hide the console when clicking outside of it.
function RoShellClass.SetHideOnLostFocus(self: RoShell, enabled: boolean)
	const client = self._client
	if not client then
		wrongSide(false, "SetHideOnLostFocus")
		return
	end
	client:SetHideOnLostFocus(enabled)
end

--- (Client) Title shown in the console header.
function RoShellClass.SetPlaceName(self: RoShell, name: string)
	const client = self._client
	if not client then
		wrongSide(false, "SetPlaceName")
		return
	end
	client:SetPlaceName(name)
end

--- (Client) Switches the console theme. Returns false when no theme has that name.
function RoShellClass.SetTheme(self: RoShell, name: string): boolean
	const client = self._client
	if not client then
		wrongSide(false, "SetTheme")
		return false
	end
	return client:SetTheme(name)
end

--- (Client) Handles custom events the server sends with `shell:SendEvent(player, name, payload)` or
--- `ctx:SendEvent(...)`.
function RoShellClass.OnEvent(self: RoShell, name: string, handler: (payload: unknown) -> ()): Types.Connection
	const client = self._client
	if not client then
		wrongSide(false, "OnEvent")
		-- A connection that never fires, so callers can still disconnect it.
		const never: Types.Signal<unknown> = Signal.new()
		return never:Connect(handler)
	end
	return client:OnEvent(name, handler)
end

--- (Client) The lines typed in the console, oldest first.
function RoShellClass.GetHistory(self: RoShell): { string }
	const client = self._client
	if not client then
		wrongSide(false, "GetHistory")
		return {}
	end
	return client:GetHistory()
end

--// RoShell
const RoShell = {
	Name = Constants.Name,
	Version = Constants.Version,

	--- `RoShell.Command({ Name, Args = { { name = RoShell.Arg(Type) }, ... } }):Run(function(ctx, args) end)`
	Command = Command.new,
	Arg = Command.Arg,
	Optional = Command.Optional,
	Default = Command.Default,
	DefaultFn = Command.DefaultFn,
	Rest = Command.Rest,
	Flag = Command.Flag,
	Dynamic = Command.Dynamic,
	Alias = Command.Alias,
	EnvKey = Command.EnvKey,
	--- Declares hooks in a module loaded by `registry:RegisterHooksIn(container)`.
	Hooks = Registry.Hooks,

	--- Type constructors (`RoShell.Type.Choice`, `.Dynamic`, `.Number`, `.List`, `.Struct`, ...).
	Type = TypeBuilder,
	--- Built-in types (`RoShell.Types.Players`, `.Duration`, `.Color3`, ...).
	Types = BuiltInTypes.Types,
	Keys = Keys,
	Permissions = Permissions,
	Storage = table.freeze({ Memory = Storage.Memory, DataStore = DataStoreStorage.new }),
	Audit = Audit,
	Theme = Theme,
	Docs = Docs,
	Test = Test,
	Fuzzy = Fuzzy,
	Result = Result,
}

--- Creates the shell for the side it runs on: the server (a Script) or the player's console (a LocalScript).
--- Register commands, types and permissions on it, then call `:Start()`.
function RoShell.new(options: Options?): RoShell
	assert(typeof(options) == "table" or options == nil, `Expected "options" parameter to be a table or nil`)
	const opts: Options = options or {}
	const platform = opts.Platform or Platform.Roblox()
	if platform.GetLocalPlayer() ~= nil then
		const client = Client.new({
			Commands = opts.Commands,
			DefaultCommands = opts.DefaultCommands,
			Name = opts.Name,
			StudioBypass = opts.StudioBypass,
			Interface = opts.Interface,
			ActivationKeys = opts.ActivationKeys,
			MashToEnable = opts.MashToEnable,
			HideOnLostFocus = opts.HideOnLostFocus,
			ActivationUnlocksMouse = opts.ActivationUnlocksMouse,
			TouchButton = opts.TouchButton,
			PlaceName = opts.PlaceName,
			Keymap = opts.Keymap,
			Settings = opts.Settings,
			Locale = opts.Locale,
			Platform = platform,
		})
		const shell = client.Shell
		const self: RoShellData = {
			Shell = shell,
			Registry = shell.Registry,
			Dispatcher = shell.Dispatcher,
			Permissions = shell.Permissions,
			Locale = shell.Locale,
			IsServer = false,
			IsClient = true,
			Scheduler = nil,
			Audit = nil,
			Settings = client.Settings,
			Toggled = client.Toggled,
			Executed = client.Executed,
			_server = nil,
			_client = client,
		}
		return setmetatable(self, RoShellClass)
	end

	const server = Server.new({
		Admins = opts.Admins,
		Commands = opts.Commands,
		DefaultCommands = opts.DefaultCommands,
		Name = opts.Name,
		StudioBypass = opts.StudioBypass,
		Timeout = opts.Timeout,
		Storage = opts.Storage,
		Audit = opts.Audit,
		Telemetry = opts.Telemetry,
		Locale = opts.Locale,
		RateLimit = opts.RateLimit,
		BroadcastTopic = opts.BroadcastTopic,
		Platform = platform,
	})
	const shell = server.Shell
	const self: RoShellData = {
		Shell = shell,
		Registry = shell.Registry,
		Dispatcher = shell.Dispatcher,
		Permissions = shell.Permissions,
		Locale = shell.Locale,
		IsServer = true,
		IsClient = false,
		Scheduler = server.Scheduler,
		Audit = server.Audit,
		Settings = nil,
		Toggled = Signal.new(),
		Executed = Signal.new(),
		_server = server,
		_client = nil,
	}
	return setmetatable(self, RoShellClass)
end

--- Declares a plugin: a bundle of commands, types, hooks and middleware registered with
--- `registry:RegisterPlugin(plugin)`.
function RoShell.Plugin(plugin: Types.Plugin): Types.Plugin
	return plugin
end

--- Finds a live shell core by name (`"RoShell"` by default) and side.
function RoShell.GetShell(name: string?, side: ("server" | "client")?): Types.Shell?
	return ShellDirectory.Find(name or Constants.Name, side)
end

return table.freeze(RoShell)
