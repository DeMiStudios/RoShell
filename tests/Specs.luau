--!strict
--[[
	The list of every spec module. Shared by the headless runner (tests/cli.luau) and the Studio runner
	(tests/Studio.luau). Specs marked `RobloxOnly` need the engine and are skipped headless.
--]]

const Runner = require(script.Parent.Runner)

const specs: { Runner.Spec } = {
	{ Name = "Fuzzy", Run = require(script.Parent.unit.FuzzySpec) },
	{ Name = "Parser", Run = require(script.Parent.unit.ParserSpec) },
	{ Name = "TypeBuilder", Run = require(script.Parent.unit.TypeBuilderSpec) },
	{ Name = "Dispatcher", Run = require(script.Parent.unit.DispatcherSpec) },
	{ Name = "Completion", Run = require(script.Parent.unit.CompletionSpec) },
	{ Name = "BuiltInCommands", Run = require(script.Parent.unit.BuiltInCommandsSpec) },
	{ Name = "Theme", Run = require(script.Parent.unit.ThemeSpec) },
	{ Name = "Highlight", Run = require(script.Parent.unit.HighlightSpec) },
	{ Name = "Format", Run = require(script.Parent.unit.FormatSpec) },
	{ Name = "InputText", Run = require(script.Parent.unit.InputTextSpec) },
	{ Name = "Settings", Run = require(script.Parent.unit.SettingsSpec) },
	{ Name = "Model", Run = require(script.Parent.unit.ModelSpec) },
	{ Name = "Net", Run = require(script.Parent.unit.NetSpec) },
	{ Name = "Manifest", Run = require(script.Parent.unit.ManifestSpec) },
	{ Name = "Permissions", Run = require(script.Parent.unit.PermissionsSpec) },
	{ Name = "PublicApi", Run = require(script.Parent.unit.PublicApiSpec) },
	{ Name = "Appendix", Run = require(script.Parent.unit.AppendixSpec) },
	{ Name = "Roblox", Run = require(script.Parent.unit.RobloxSpec), RobloxOnly = true },
}

return specs
