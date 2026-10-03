--!strict
--[[
	RoShell: a typed, extensible command console for Roblox.

		local RoShell = require(ReplicatedStorage.RoShell)

		-- Server
		local server = RoShell.Server.new()
		server.Registry:RegisterDefaultCommands()
		server.Registry:RegisterCommandsIn(ServerScriptService.Commands)
		server:Start()

		-- Client
		local client = RoShell.Client.new()
		client.Registry:RegisterDefaultCommands()
		client:Start()

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
]]

--// Imports
const Audit = require("@self/Server/Audit")
const BuiltInTypes = require("@self/Shared/BuiltInTypes")
const Client = require("@self/Client")
const Command = require("@self/Shared/Command")
const Constants = require("@self/Shared/Constants")
const DataStoreStorage = require("@self/Server/DataStoreStorage")
const Docs = require("@self/Shared/Docs")
const Fuzzy = require("@self/Shared/Fuzzy")
const Keys = require("@self/Shared/Keys")
const Permissions = require("@self/Shared/Permissions")
const Result = require("@self/Shared/Result")
const Server = require("@self/Server")
const ShellDirectory = require("@self/Shared/ShellDirectory")
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
export type Server = Server.Server
export type ServerOptions = Server.ServerOptions
export type Client = Client.Client
export type ClientOptions = Client.ClientOptions

--// RoShell
const RoShell = {
	Name = Constants.Name,
	Version = Constants.Version,

	Server = Server,
	Client = Client,

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

--- Declares a plugin: a bundle of commands, types, hooks and middleware registered with
--- `registry:RegisterPlugin(plugin)`.
function RoShell.Plugin(plugin: Types.Plugin): Types.Plugin
	return plugin
end

--- Finds a live shell by name (`"RoShell"` by default) and side.
function RoShell.GetShell(name: string?, side: ("server" | "client")?): Types.Shell?
	return ShellDirectory.Find(name or Constants.Name, side)
end

return table.freeze(RoShell)
