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
	{ Name = "Completion", Run = require("./unit/CompletionSpec") },
	{ Name = "BuiltInCommands", Run = require("./unit/BuiltInCommandsSpec") },
	{ Name = "Theme", Run = require("./unit/ThemeSpec") },
	{ Name = "Highlight", Run = require("./unit/HighlightSpec") },
	{ Name = "Format", Run = require("./unit/FormatSpec") },
	{ Name = "InputText", Run = require("./unit/InputTextSpec") },
	{ Name = "Settings", Run = require("./unit/SettingsSpec") },
	{ Name = "Net", Run = require("./unit/NetSpec") },
	{ Name = "PublicApi", Run = require("./unit/PublicApiSpec") },
	{ Name = "Appendix", Run = require("./unit/AppendixSpec") },
	{ Name = "Roblox", Run = require("./unit/RobloxSpec"), RobloxOnly = true },
}

return specs
