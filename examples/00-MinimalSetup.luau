--!strict
--[[
	The whole setup: one module, one line on each side.

	Server (a Script in ServerScriptService):

		const RoShell = require(game.ReplicatedStorage.RoShell)
		RoShell.new({ Admins = { 156 } }):Start()

	Client (a LocalScript in StarterPlayerScripts):

		const RoShell = require(game.ReplicatedStorage:WaitForChild("RoShell"))
		RoShell.new():Start()

	Every player gets the built-in commands open to everyone (help, history, aliases, themes, settings...) and the
	listed admins get everything (kick, teleport, announce...). In Studio every command is allowed, for testing.

	Your own commands: put their modules in a folder and name it on the server. The folder can be anywhere:

	- ServerStorage (or anywhere else on the server) keeps the code private. Each player receives a description of
	  the commands they may run, so the console still completes, highlights and checks them; running one sends the
	  line to the server.
	- ReplicatedStorage shares the code, so clients load the same modules themselves. Commands with a `ClientRun`
	  part need this (their client code has to reach the client).

		RoShell.new({ Admins = { 156 }, Commands = game.ServerStorage.Commands }):Start()

	Organizing commands: a folder can hold subfolders as deep as you like, since every ModuleScript under it is
	loaded (a module returns one command or a list of them; modules that return anything else, such as shared
	helpers, are ignored). Several separate folders work too:

		ServerStorage
		├─ Commands
		│  ├─ Moderation          kick.luau, ban.luau, mute.luau
		│  ├─ Economy             give.luau, take.luau
		│  │  └─ Shops            shop.luau
		│  └─ Fun                 dance.luau
		└─ MinigameCommands       round.luau, spectate.luau

		RoShell.new({
			Admins = { 156 },
			Commands = { game.ServerStorage.Commands, game.ServerStorage.MinigameCommands },
		}):Start()

	Folders do not set permissions: give a command a `Group` (for example the name of its folder) and grant groups
	with `shell.Permissions:SetGroup("Fun", RoShell.Permissions.Everyone())`.

	Nothing else is required. Players' history, aliases, binds, variables and console settings live in memory for
	the life of the server unless you pass `Storage = RoShell.Storage.DataStore("RoShell")` to keep them between
	sessions. Roles, group rules, hooks, middleware and audit sinks are in 05-ServerSetup.luau.
--]]

--// Services
const ReplicatedStorage = game:GetService("ReplicatedStorage")
const ServerStorage = game:GetService("ServerStorage")

--// Imports
const RoShell = require(ReplicatedStorage.RoShell)

--// Functions
-- The folders of commands this place has (an example has to run in any place, so missing ones are skipped; in a
-- game, write `{ ServerStorage.Commands, ServerStorage.MinigameCommands }`).
const function existing(names: { string }): { Instance }
	const found: { Instance } = {}
	for _, name in names do
		const folder = ServerStorage:FindFirstChild(name)
		if folder then
			table.insert(found, folder)
		end
	end
	return found
end

--// Minimal Setup
return {
	-- From a server Script.
	Server = function(): RoShell.RoShell
		const shell = RoShell.new({
			-- User ids and/or rules: `{ 156, RoShell.Permissions.Group(1234567, 250) }`.
			Admins = { 156 },
			-- Each folder (and everything nested in it) is loaded; players get a description of what they may run.
			Commands = existing({ "Commands", "MinigameCommands" }),
		})
		-- Commands with `Group = "Fun"` are open to everyone; the rest stay with the admins.
		shell.Permissions:SetGroup("Fun", RoShell.Permissions.Everyone())
		return shell:Start()
	end,

	-- From a LocalScript.
	Client = function(): RoShell.RoShell
		return RoShell.new():Start()
	end,
}
