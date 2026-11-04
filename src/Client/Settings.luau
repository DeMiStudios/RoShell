--!strict
--[[
	Typed console settings (`config <key> <value>`). Each setting has a type that parses the user's text, so
	values are validated and completed like command arguments. Values persist per user through the server.
--]]

--// Imports
const BuiltInTypes = require(script.Parent.Parent.Shared.BuiltInTypes)
const Platform = require(script.Parent.Parent.Shared.Platform)
const Signal = require(script.Parent.Parent.Shared.Signal)
const TypeBuilder = require(script.Parent.Parent.Shared.TypeBuilder)
const Types = require(script.Parent.Parent.Shared.Types)
const Util = require(script.Parent.Parent.Shared.Util)

--// Types
export type Definition = {
	Key: string,
	Description: string,
	Type: Types.Type<unknown>,
	Default: string | number | boolean,
	--- Internal settings (window layout) are persisted but not listed by `config`.
	Hidden: boolean?,
}

export type Settings = {
	--- Fires with the key that changed.
	read Changed: Types.Signal<string>,
	read GetBoolean: (self: Settings, key: string) -> boolean,
	read GetNumber: (self: Settings, key: string) -> number,
	read GetString: (self: Settings, key: string) -> string,
	--- Parses and stores a value given as text. Returns false and a message when invalid.
	read SetText: (self: Settings, key: string, text: string) -> (boolean, string?),
	read Set: (self: Settings, key: string, value: string | number | boolean) -> (),
	read List: (self: Settings) -> { { Key: string, Value: string, Description: string } },
	--- The values that differ from the defaults (so later changes to defaults still reach players).
	read Serialize: (self: Settings) -> { [string]: string | number | boolean },
	_values: { [string]: string | number | boolean },
	--- Definition defaults overlaid with the developer's overrides.
	_defaults: { [string]: string | number | boolean },
}

--// Constants
const T = BuiltInTypes.Types
const DEFINITIONS: { Definition } = {
	{ Key = "theme", Description = "Color theme (see `theme`)", Type = T.String, Default = "Midnight" },
	{
		Key = "density",
		Description = "Spacing of rows: comfortable or compact",
		Type = TypeBuilder.Choice({ Name = "density", Choices = { "comfortable", "compact" } }),
		Default = "comfortable",
	},
	{ Key = "reduceMotion", Description = "Turn off animations", Type = T.Boolean, Default = false },
	{
		Key = "textScale",
		Description = "Text size multiplier (0.75-1.75)",
		Type = TypeBuilder.Number({ Name = "scale", Min = 0.75, Max = 1.75 }),
		Default = 1,
	},
	{
		Key = "dock",
		Description = "Command bar placement: top, bottom or float",
		Type = TypeBuilder.Choice({ Name = "dock", Choices = { "top", "bottom", "float" } }),
		Default = "top",
	},
	{ Key = "blur", Description = "Blur the game behind the console", Type = T.Boolean, Default = false },
	{ Key = "timestamps", Description = "Show a timestamp on every log row", Type = T.Boolean, Default = false },
	{
		Key = "opacity",
		Description = "Opacity of the bar and panel (0.5-1)",
		Type = TypeBuilder.Number({ Name = "opacity", Min = 0.5, Max = 1 }),
		Default = 0.95,
	},
	{
		Key = "font",
		Description = "Font of the command bar: sans or mono",
		Type = TypeBuilder.Choice({ Name = "font", Choices = { "sans", "mono" } }),
		Default = "sans",
	},
	{ Key = "ghostText", Description = "Show the top suggestion inline as you type", Type = T.Boolean, Default = true },
	{ Key = "autoPair", Description = "Insert closing quotes and braces", Type = T.Boolean, Default = false },
	{
		Key = "quoting",
		Description = 'How completions write values with spaces: quotes ("Golden Apple") or backslash (Golden\\ Apple)',
		Type = TypeBuilder.Choice({ Name = "quoting", Choices = { "quotes", "backslash" } }),
		Default = "quotes",
	},
	{
		Key = "maxLog",
		Description = "Log rows kept (100-5000)",
		Type = TypeBuilder.Integer({ Name = "rows", Min = 100, Max = 5000 }),
		Default = 1000,
	},
	{
		Key = "layout",
		Description = "Position of the floating command bar",
		Type = T.String,
		Default = "",
		Hidden = true,
	},
}

--// Globals
-- Parsing a setting value needs a request; settings never use the shell, so a detached handle is enough.
const DETACHED_HANDLE: Types.ShellHandle = table.freeze({ Name = "settings", Id = 0 })
local headlessPlatform: Types.PlatformInfo? = nil

--// Functions
const function definitionOf(key: string): Definition?
	const lowered = key:lower()
	for _, definition in DEFINITIONS do
		if definition.Key:lower() == lowered then
			return definition
		end
	end
	return nil
end

const function platform(): Types.PlatformInfo
	if headlessPlatform == nil then
		headlessPlatform = Platform.Headless().Platform
	end
	return headlessPlatform :: Types.PlatformInfo
end

--// Settings Class
const Settings = {}
Settings.__index = Settings

function Settings.GetBoolean(self: Settings, key: string): boolean
	return self._values[key] == true
end

function Settings.GetNumber(self: Settings, key: string): number
	const value = self._values[key]
	return if typeof(value) == "number" then value else 0
end

function Settings.GetString(self: Settings, key: string): string
	const value = self._values[key]
	return if typeof(value) == "string" then value else tostring(value)
end

function Settings.Set(self: Settings, key: string, value: string | number | boolean)
	if self._values[key] == value then
		return
	end
	self._values[key] = value
	self.Changed:Fire(key)
end

function Settings.SetText(self: Settings, key: string, text: string): (boolean, string?)
	const definition = definitionOf(key)
	if definition == nil then
		return false, `Unknown setting '{key}'`
	end
	const result = definition.Type.Parse({
		Text = text,
		Quoted = false,
		Span = { Start = 1, End = #text + 1 },
		Shell = DETACHED_HANDLE,
		Platform = platform(),
		Final = true,
	})
	if not result.Ok then
		return false, result.Error
	end
	const value = result.Value
	if typeof(value) == "string" or typeof(value) == "number" or typeof(value) == "boolean" then
		self:Set(definition.Key, value)
		return true, nil
	end
	return false, "Unsupported value"
end

function Settings.List(self: Settings): { { Key: string, Value: string, Description: string } }
	const list: { { Key: string, Value: string, Description: string } } = {}
	for _, definition in DEFINITIONS do
		if definition.Hidden then
			continue
		end
		table.insert(list, {
			Key = definition.Key,
			Value = Util.FormatValue(self._values[definition.Key]),
			Description = definition.Description,
		})
	end
	return list
end

function Settings.Serialize(self: Settings): { [string]: string | number | boolean }
	const changed: { [string]: string | number | boolean } = {}
	for key, value in self._values do
		if value ~= self._defaults[key] then
			changed[key] = value
		end
	end
	return changed
end

Settings.Definitions = DEFINITIONS

--- The type of a (visible) setting's values.
function Settings.TypeOf(key: string): Types.Type<unknown>?
	const definition = definitionOf(key)
	if definition == nil or definition.Hidden then
		return nil
	end
	return definition.Type
end

--- Creates settings from saved values (anything invalid falls back to the default).
function Settings.new(saved: unknown, overrides: { [string]: string | number | boolean }?): Settings
	const defaults: { [string]: string | number | boolean } = {}
	for _, definition in DEFINITIONS do
		defaults[definition.Key] = definition.Default
	end
	for key, value in overrides or {} do
		const definition = definitionOf(key)
		if definition and typeof(definition.Default) == typeof(value) then
			defaults[definition.Key] = value
		end
	end
	const values = table.clone(defaults)
	if typeof(saved) == "table" then
		for key, value in saved do
			if typeof(key) == "string" and definitionOf(key) ~= nil then
				if typeof(value) == "string" or typeof(value) == "number" or typeof(value) == "boolean" then
					if typeof(values[key]) == typeof(value) then
						values[key] = value
					end
				end
			end
		end
	end
	return setmetatable({ Changed = Signal.new(), _values = values, _defaults = defaults }, Settings)
end

return table.freeze(Settings)
