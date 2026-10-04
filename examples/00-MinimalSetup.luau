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
	the same folders by themselves.

		RoShell.Server.new({ Admins = { 156 }, Commands = game.ReplicatedStorage.Commands }):Start()

	Organizing commands: a folder can hold subfolders as deep as you like, since every ModuleScript under it is
	loaded (a module returns one command or a list of them; modules that return anything else, such as shared
	helpers, are ignored). Several separate folders work too:

		ReplicatedStorage
		├─ Commands
		│  ├─ Moderation          kick.luau, ban.luau, mute.luau
		│  ├─ Economy             give.luau, take.luau
		│  │  └─ Shops            shop.luau
		│  └─ Fun                 dance.luau
		└─ MinigameCommands       round.luau, spectate.luau

		RoShell.Server.new({
			Admins = { 156 },
			Commands = { game.ReplicatedStorage.Commands, game.ReplicatedStorage.MinigameCommands },
		}):Start()

	Folders do not set permissions: give a command a `Group` (for example the name of its folder) and grant groups
	with `server.Permissions:SetGroup("Fun", RoShell.Permissions.Everyone())`. Keep command modules where clients can
	see them (ReplicatedStorage): the console completes and checks lines before the server runs them.

	Nothing else is required. Players' history, aliases, binds, variables and console settings live in memory for
	the life of the server unless you pass `Storage = RoShell.Storage.DataStore("RoShell")` to keep them between
	sessions. Roles, group rules, hooks, middleware and audit sinks are in 05-ServerSetup.luau.
]]

const ReplicatedStorage = game:GetService("ReplicatedStorage")

const RoShell = require(ReplicatedStorage.RoShell)

--- The folders of commands this place has (an example has to run in any place, so missing ones are skipped; in a
--- game, write `{ ReplicatedStorage.Commands, ReplicatedStorage.MinigameCommands }`).
const function existing(names: { string }): { Instance }
	const found: { Instance } = {}
	for _, name in names do
		const folder = ReplicatedStorage:FindFirstChild(name)
		if folder then
			table.insert(found, folder)
		end
	end
	return found
end

return {
	--- From a server Script.
	Server = function(): RoShell.Server
		const server = RoShell.Server.new({
			-- User ids and/or rules: `{ 156, RoShell.Permissions.Group(1234567, 250) }`.
			Admins = { 156 },
			-- Each folder (and everything nested in it) is loaded; clients get the same list.
			Commands = existing({ "Commands", "MinigameCommands" }),
		})
		-- Commands with `Group = "Fun"` are open to everyone; the rest stay with the admins.
		server.Permissions:SetGroup("Fun", RoShell.Permissions.Everyone())
		return server:Start()
	end,

	--- From a LocalScript.
	Client = function(): RoShell.Client
		return RoShell.Client.new():Start()
	end,
}
