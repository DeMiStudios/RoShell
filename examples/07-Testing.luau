--!strict
--[[
	Unit-testing commands with `RoShell.Test`: no UI, no network, a virtual clock (waits finish instantly) and
	scripted prompt answers. Works in any test framework (TestEZ, Jest-Lua, ...) and in the standalone Luau runtime.
]]

const RoShell = require(game:GetService("ReplicatedStorage").RoShell)
const CustomTypes = require("./02-CustomTypes")

return function()
	-- One-off run.
	const result = RoShell.Test.Run({ Text = "configure hard cat --offset x=1,y=2", Commands = CustomTypes.Commands })
	assert(result.Ok, result.Output)
	assert(result.Output == "difficulty=hard speed=16 offset=1,2", result.Output)

	-- A reusable harness (server side by default; `Client = true` runs `ClientRun` handlers instead).
	const harness = RoShell.Test.new({ Commands = CustomTypes.Commands })
	const defaults = harness.Run("configure")
	assert(defaults.Output == "difficulty=normal speed=0 offset=none", defaults.Output)

	const invalid = harness.Run("configure impossible")
	assert(not invalid.Ok, "invalid difficulty must fail")
end
