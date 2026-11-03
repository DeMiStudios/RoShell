--!strict
--[[
	Demo client: press F2 or ` to open the console (or tap the floating button on touch devices). The built-in
	commands, the demo's shared ones and the server's private ones are registered by `Start`.
--]]

--// Services
const ReplicatedStorage = game:GetService("ReplicatedStorage")

--// Imports
const RoShell = require(ReplicatedStorage:WaitForChild("RoShell"))

--// Initialize RoShell
RoShell.new({ PlaceName = "Demo place" }):Start()
