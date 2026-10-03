--!strict
--[[
	Demo client: press F2 or ` to open the console (or tap the floating button on touch devices).
]]

const ReplicatedStorage = game:GetService("ReplicatedStorage")

const RoShell = require(ReplicatedStorage:WaitForChild("RoShell"))
const demo = ReplicatedStorage:WaitForChild("RoShellDemo")

const client = RoShell.Client.new({
	PlaceName = "Demo place",
})

client.Registry:RegisterDefaultCommands()
client.Registry:RegisterCommandsIn(demo:WaitForChild("Commands"))
client:Start()
