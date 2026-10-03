--!strict
--[[
	A console API for headless tests of client commands (`config`, `theme`, `bind`, `alias`, ...), backed by a real
	Settings object and plain tables.
]]

const Keys = require("../../src/Shared/Keys")
const Settings = require("../../src/Client/Settings")
const Types = require("../../src/Shared/Types")

export type FakeConsole = {
	Api: Keys.ConsoleApi,
	Settings: Settings.Settings,
	Binds: { [string]: string },
	Aliases: { [string]: string },
	Notifications: { string },
}

const FakeConsole = {}

const function nothing()
end

function FakeConsole.new(): FakeConsole
	const settings = Settings.new(nil, nil)
	const binds: { [string]: string } = {}
	const aliases: { [string]: string } = {}
	const notifications: { string } = {}
	const themes = { "Midnight", "Graphite", "Light" }
	local theme = "Midnight"
	const api: Keys.ConsoleApi = {
		Clear = nothing,
		Show = nothing,
		Hide = nothing,
		Toggle = nothing,
		OpenPalette = nothing,
		SetTheme = function(name: string): boolean
			if table.find(themes, name) == nil then
				return false
			end
			theme = name
			return true
		end,
		GetThemes = function(): { string }
			return table.clone(themes)
		end,
		GetTheme = function(): string
			return theme
		end,
		ExportLog = function(): string
			return ""
		end,
		GetHistory = function(): { string }
			return {}
		end,
		ClearHistory = nothing,
		Bind = function(keybind: string, line: string): (boolean, string?)
			binds[keybind] = line
			return true, nil
		end,
		Unbind = function(keybind: string): boolean
			const existed = binds[keybind] ~= nil
			binds[keybind] = nil
			return existed
		end,
		GetBinds = function(): { { Key: string, Command: string } }
			const list: { { Key: string, Command: string } } = {}
			for key, line in binds do
				table.insert(list, { Key = key, Command = line })
			end
			return list
		end,
		SaveAlias = function(name: string, body: string)
			aliases[name] = body
		end,
		SaveVariables = nothing,
		RemoveAlias = function(name: string)
			aliases[name] = nil
		end,
		SetSetting = function(key: string, value: string): (boolean, string?)
			return settings:SetText(key, value)
		end,
		GetSettings = function(): { { Key: string, Value: string, Description: string } }
			return settings:List()
		end,
		SettingType = Settings.TypeOf,
		Notify = function(text: string, _level: Types.Level?)
			table.insert(notifications, text)
		end,
	}
	return { Api = api, Settings = settings, Binds = binds, Aliases = aliases, Notifications = notifications }
end

return table.freeze(FakeConsole)
