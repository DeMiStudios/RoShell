--!strict
--[[
	Typed environment keys for services the built-in commands use (`ctx:GetEnv(Keys.Scheduler)`).
]]

--// Imports
const Command = require("./Command")
const Scheduler = require("../Server/Scheduler")
const Types = require("./Types")

--// Types
--- Client-side services exposed to built-in client commands (implemented by the client UI).
export type ConsoleApi = {
	read Clear: () -> (),
	read Show: () -> (),
	read Hide: () -> (),
	read Toggle: () -> (),
	read OpenPalette: () -> (),
	read SetTheme: (name: string) -> boolean,
	read GetThemes: () -> { string },
	read GetTheme: () -> string,
	read ExportLog: () -> string,
	read GetHistory: () -> { string },
	read ClearHistory: () -> (),
	read Bind: (keybind: string, command: string) -> (boolean, string?),
	read Unbind: (keybind: string) -> boolean,
	read GetBinds: () -> { { Key: string, Command: string } },
	read SaveAlias: (name: string, body: string) -> (),
	--- Persists the executor's variables (after `set`/`unset`).
	read SaveVariables: () -> (),
	read RemoveAlias: (name: string) -> (),
	read SetSetting: (key: string, value: string) -> (boolean, string?),
	read GetSettings: () -> { { Key: string, Value: string, Description: string } },
	--- The type of a setting's values (drives `config` completion and validation).
	read SettingType: (key: string) -> Types.Type<unknown>?,
	read Notify: (text: string, level: Types.Level?) -> (),
}

--// Keys
const Keys = {
	--- Server: the scheduler behind `in`, `every`, `repeat`, `schedules` and `cancel`.
	Scheduler = Command.EnvKey<<Scheduler.Scheduler>>("RoShell.Scheduler"),
	--- Server: the audit sink behind `audit`.
	Audit = Command.EnvKey<<Types.AuditSink>>("RoShell.Audit"),
	--- Server: the folder of scripts (ModuleScripts returning text, or StringValues) for `run-script`.
	Scripts = Command.EnvKey<<Instance>>("RoShell.Scripts"),
	--- Client: console/UI operations used by client commands (clear, theme, bind, history...).
	Console = Command.EnvKey<<ConsoleApi>>("RoShell.Console"),
}

return table.freeze(Keys)
