--!strict
--[[
	`RoShell.Types`: the built-in argument types. Every one is registered on new shells (so `help <type>` and pipe
	type names work), and each is an ordinary `Type<T>` value you pass to `RoShell.Arg(...)`.
]]

--// Imports
const Colors = require("@self/Colors")
const Instances = require("@self/Instances")
const Meta = require("@self/Meta")
const Players = require("@self/Players")
const Primitives = require("@self/Primitives")
const Time = require("@self/Time")
const Types = require("./Types")
const Vectors = require("@self/Vectors")

--// Built-in types
const BuiltInTypes = {
	-- Primitives
	String = Primitives.String,
	Strings = Primitives.Strings,
	Number = Primitives.Number,
	Numbers = Primitives.Numbers,
	Integer = Primitives.Integer,
	Integers = Primitives.Integers,
	Boolean = Primitives.Boolean,
	Percent = Primitives.Percent,
	Range = Primitives.Range,
	Pattern = Primitives.Pattern,
	Url = Primitives.Url,
	Json = Primitives.Json,
	Asset = Primitives.Asset,

	-- Players and teams
	Player = Players.Player,
	Players = Players.Players,
	Team = Players.Team,
	Teams = Players.Teams,
	TeamPlayers = Players.TeamPlayers,
	UserId = Players.UserId,
	UserIds = Players.UserIds,

	-- Time
	Duration = Time.Duration,
	Durations = Time.Durations,
	Timestamp = Time.Timestamp,

	-- Colors and vectors
	Color3 = Colors.Color3,
	Color3s = Colors.Color3s,
	ColorHex = Colors.ColorHex,
	BrickColor = Colors.BrickColor,
	BrickColors = Colors.BrickColors,
	Vector3 = Vectors.Vector3,
	Vector3s = Vectors.Vector3s,
	Vector2 = Vectors.Vector2,
	Vector2s = Vectors.Vector2s,

	-- DataModel
	Instance = Instances.Instance,
	Instances = Instances.Instances,
	Class = Instances.Class,
	Tag = Instances.Tag,
	Remote = Instances.Remote,
	Attribute = Instances.Attribute,

	-- Shell and engine metadata
	Command = Meta.Command,
	Commands = Meta.Commands,
	TypeName = Meta.TypeName,
	StoredKey = Meta.StoredKey,
	Keybind = Meta.Keybind,
	Material = Meta.Material,
	KeyCode = Meta.KeyCode,

	--- Any Roblox enum by name (`RoShell.Types.Enum("HumanoidStateType")`, shown as `enum:HumanoidStateType`).
	Enum = Meta.EnumByName,
}

--- Every built-in type (for registration).
const ALL: { Types.Type<unknown> } = {
	BuiltInTypes.String,
	BuiltInTypes.Strings,
	BuiltInTypes.Number,
	BuiltInTypes.Numbers,
	BuiltInTypes.Integer,
	BuiltInTypes.Integers,
	BuiltInTypes.Boolean,
	BuiltInTypes.Percent,
	BuiltInTypes.Range,
	BuiltInTypes.Pattern,
	BuiltInTypes.Url,
	BuiltInTypes.Json,
	BuiltInTypes.Asset,
	BuiltInTypes.Player,
	BuiltInTypes.Players,
	BuiltInTypes.Team,
	BuiltInTypes.Teams,
	BuiltInTypes.TeamPlayers,
	BuiltInTypes.UserId,
	BuiltInTypes.UserIds,
	BuiltInTypes.Duration,
	BuiltInTypes.Durations,
	BuiltInTypes.Timestamp,
	BuiltInTypes.Color3,
	BuiltInTypes.Color3s,
	BuiltInTypes.ColorHex,
	BuiltInTypes.BrickColor,
	BuiltInTypes.BrickColors,
	BuiltInTypes.Vector3,
	BuiltInTypes.Vector3s,
	BuiltInTypes.Vector2,
	BuiltInTypes.Vector2s,
	BuiltInTypes.Instance,
	BuiltInTypes.Instances,
	BuiltInTypes.Class,
	BuiltInTypes.Tag,
	BuiltInTypes.Remote,
	BuiltInTypes.Attribute,
	BuiltInTypes.Command,
	BuiltInTypes.Commands,
	BuiltInTypes.TypeName,
	BuiltInTypes.StoredKey,
	BuiltInTypes.Keybind,
	BuiltInTypes.Material,
	BuiltInTypes.KeyCode,
}

const Module = {
	Types = table.freeze(BuiltInTypes),
	All = table.freeze(ALL),
	--- Selectors exported for reuse in custom player types.
	TeamSelector = Players.TeamSelector,
	TagSelector = Players.TagSelector,
	ParseDuration = Time.ParseDuration,
	ParseColor = Colors.ParseColor,
	ParseKeybind = Meta.ParseKeybind,
	SplitPath = Instances.SplitPath,
}

return table.freeze(Module)
