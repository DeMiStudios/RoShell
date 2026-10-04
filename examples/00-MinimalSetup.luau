--!strict
--[[
	The whole setup: one line on the server, one on the client.

	Server (a Script in ServerScriptService):

		local RoShell = require(game.ReplicatedStorage.RoShell)
		RoShell.Server.new({ Admins = { 156 } }):Start()

	Client (a LocalScript in StarterPlayerScripts):

		local RoShell = require(game.ReplicatedStorage:WaitForChild("RoShell"))
		RoShell.Client.new():Start()

	Every player gets the built-in commands open to everyone (help, history, aliases, themes, settings...) and the
	listed admins get everything (kick, teleport, announce...). In Studio every command is allowed, for testing.

	Your own commands: put their modules in a folder in ReplicatedStorage and name it on the server. Clients load
	the same folder by themselves.

		RoShell.Server.new({ Admins = { 156 }, Commands = game.ReplicatedStorage.Commands }):Start()

	Nothing else is required. Players' history, aliases, binds, variables and console settings live in memory for
	the life of the server unless you pass `Storage = RoShell.Storage.DataStore("RoShell")` to keep them between
	sessions. Roles, group rules, hooks, middleware and audit sinks are in 05-ServerSetup.luau.
]]

const ReplicatedStorage = game:GetService("ReplicatedStorage")

const RoShell = require(ReplicatedStorage.RoShell)

return {
	--- From a server Script.
	Server = function(): RoShell.Server
		return RoShell.Server.new({
			-- User ids and/or rules: `{ 156, RoShell.Permissions.Group(1234567, 250) }`.
			Admins = { 156 },
			Commands = ReplicatedStorage:FindFirstChild("Commands"),
		}):Start()
	end,

	--- From a LocalScript.
	Client = function(): RoShell.Client
		return RoShell.Client.new():Start()
	end,
}
