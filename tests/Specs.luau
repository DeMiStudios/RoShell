--!strict
--[[
	The list of every spec module. Shared by the headless runner (tests/cli.luau) and the Studio runner
	(tests/Studio.luau). Specs marked `RobloxOnly` need the engine and are skipped headless.
]]

const Runner = require("./Runner")

const specs: { Runner.Spec } = {
	{ Name = "Fuzzy", Run = require("./unit/FuzzySpec") },
	{ Name = "Parser", Run = require("./unit/ParserSpec") },
	{ Name = "TypeBuilder", Run = require("./unit/TypeBuilderSpec") },
	{ Name = "Dispatcher", Run = require("./unit/DispatcherSpec") },
}

return specs
