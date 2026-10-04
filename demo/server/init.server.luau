--!strict
--[[
	Demo server: the built-in commands plus the demo's, with the demo's open to everyone in this place so it can be
	played with (Admin, Debug and Schedule stay restricted outside Studio; real games name their `Admins`).
	Clients load the demo's commands from the folder named here; their script is one line.
]]

const ReplicatedStorage = game:GetService("ReplicatedStorage")

const RoShell = require(ReplicatedStorage.RoShell)

const server = RoShell.Server.new({
	Commands = ReplicatedStorage.RoShellDemo.Commands,
})
server.Permissions:SetGroup("Demo", RoShell.Permissions.Everyone())
server:Start()
