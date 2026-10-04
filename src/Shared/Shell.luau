--!strict
--[[
	The shell core shared by `RoShell.Server`, `RoShell.Client` and `RoShell.Test`: registry, dispatcher,
	permissions, locale, platform, storage and per-executor sessions. No global state: several shells can coexist
	(each one is reachable from its handle through ShellDirectory).
]]

--// Imports
const BuiltInTypes = require("./BuiltInTypes")
const Constants = require("./Constants")
const Dispatcher = require("./Dispatcher")
const Functions = require("./Functions")
const Locale = require("./Locale")
const Permissions = require("./Permissions")
const Registry = require("./Registry")
const ShellDirectory = require("./ShellDirectory")
const Storage = require("./Storage")
const Types = require("./Types")
const Util = require("./Util")

--// Types
type Shell = Types.Shell

export type ShellConfig = {
	IsServer: boolean,
	IsClient: boolean,
	Platform: Types.PlatformInfo,
	Options: Types.ShellOptions?,
	Storage: Types.StorageAdapter?,
	Locale: { [string]: string }?,
}

--// Shell class
const ShellClass = {}
ShellClass.__index = ShellClass

function ShellClass.GetSession(self: Shell, executor: Player?): Types.Session
	const key = Util.ExecutorKey(executor)
	const existing = self._sessions[key]
	if existing then
		return existing
	end
	const session: Types.Session = {
		Variables = {},
		Last = nil,
		Undo = {},
		Redo = {},
		Held = {},
		History = {},
	}
	self._sessions[key] = session
	return session
end

table.freeze(ShellClass)

--// Shell module
const ShellModule = {}

--- Creates a shell core.
function ShellModule.new(config: ShellConfig): Shell
	const options: Types.ShellOptions = config.Options or {}
	const handle: Types.ShellHandle = table.freeze({
		Name = options.Name or Constants.Name,
		Id = ShellDirectory.NextId(),
	})
	const shell: Shell = setmetatable(
		{
			Name = handle.Name,
			Id = handle.Id,
			Handle = handle,
			IsServer = config.IsServer,
			IsClient = config.IsClient,
			Registry = Registry.new(handle),
			Dispatcher = Dispatcher.new(handle),
			Permissions = Permissions.Manager(handle),
			Locale = Locale.new(config.Locale),
			Platform = config.Platform,
			Options = options,
			Storage = config.Storage or Storage.Memory(),
			_sessions = {},
			_transport = nil :: Types.Transport?,
			_audit = nil :: Types.AuditSink?,
			_telemetry = nil :: Types.TelemetrySink?,
			_broadcast = nil :: ((message: string, options: Types.BroadcastOptions?, executor: Player?) -> (boolean, string?))?,
			_sendEvent = nil :: ((player: Player, name: string, payload: unknown) -> ())?,
			_nextRef = 0,
		},
		ShellClass
	)
	ShellDirectory.Register(shell)
	shell.Registry:RegisterTypes(BuiltInTypes.All)
	for _, definition in Functions.All do
		shell.Registry:RegisterFunction(definition)
	end
	return shell
end

--- Stores a value on the server so a client can reference it (`$:id`). Returns the reference id.
function ShellModule.Hold(shell: Shell, executor: Player?, result: Types.CommandResult, lifetime: number?): string
	shell._nextRef += 1
	const id = tostring(shell._nextRef)
	const session = shell:GetSession(executor)
	session.Held[id] = {
		Value = result.Value,
		Type = result.ValueType,
		Display = result.Display or "",
		Expires = shell.Platform.Clock() + (lifetime or 600),
	}
	-- Bound memory: drop expired references.
	const now = shell.Platform.Clock()
	for key, held in session.Held do
		if held.Expires < now then
			session.Held[key] = nil
		end
	end
	return id
end

--- Releases a shell (unregisters it from the directory).
function ShellModule.Destroy(shell: Shell)
	ShellDirectory.Unregister(shell)
end

return table.freeze(ShellModule)
