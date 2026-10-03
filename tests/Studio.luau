--!strict
--[[
	Studio test entry. From the command bar (or a plugin), in edit or play mode:

		require(game.ServerStorage.RoShellDev.tests.Studio)()

	Runs every spec, including the `RobloxOnly` ones that need the engine, and returns the summary.
]]

const Runner = require("./Runner")
const Specs = require("./Specs")

return function(options: Runner.RunOptions?): Runner.Summary
	return Runner.Run(Specs, options)
end
