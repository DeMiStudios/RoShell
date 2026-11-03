--!strict
--[[
	Demo server: the built-in commands plus the demo's, with the demo's open to everyone in this place so it can be
	played with (Admin, Debug and Schedule stay restricted outside Studio; real games name their `Admins`).

	The shared demo commands sit in ReplicatedStorage and clients load them too. The ones in this Script's
	`Commands` folder never leave the server: players get a description of them instead.
--]]

--// Services
const ReplicatedStorage = game:GetService("ReplicatedStorage")

--// Imports
const RoShell = require(ReplicatedStorage.RoShell)

--// Initialize RoShell
const shell = RoShell.new({
	Commands = { ReplicatedStorage.RoShellDemo.Commands, script.Commands },
})
shell.Permissions:SetGroup("Demo", RoShell.Permissions.Everyone())
shell:Start()
