--!strict
--[[
	Demo client: press F2 or ` to open the console (or tap the floating button on touch devices). The built-in
	commands and the demo's (shared by the server) are registered by `Start`.
]]

const ReplicatedStorage = game:GetService("ReplicatedStorage")

const RoShell = require(ReplicatedStorage:WaitForChild("RoShell"))

RoShell.Client.new({ PlaceName = "Demo place" }):Start()
