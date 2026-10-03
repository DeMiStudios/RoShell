--!strict
--[[
	Demo server: built-in commands plus the demo's commands, open to everyone in this place so the demo can be
	played with (real games keep the default-deny permissions and map groups to roles instead).
]]

const ReplicatedStorage = game:GetService("ReplicatedStorage")

const RoShell = require(ReplicatedStorage.RoShell)

const server = RoShell.Server.new({
	Storage = RoShell.Storage.Memory(),
})

server.Registry:RegisterDefaultCommands()
server.Registry:RegisterCommandsIn(ReplicatedStorage.RoShellDemo.Commands)

-- Everyone may use the demo commands; Admin/Debug/Schedule stay restricted outside Studio.
server.Permissions:SetGroup("Demo", RoShell.Permissions.Everyone())

server:Start()
