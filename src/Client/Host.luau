--!strict
--[[
	The contract between the client core and the console UI: what the UI may ask of the client (`ConsoleHost`) and
	what the client may ask of the UI (`Console`).
]]

--// Imports
const Keymap = require("./UI/Keymap")
const Settings = require("./Settings")
const Types = require("../Shared/Types")

--// Types
export type ActivationOptions = {
	Keys: { Enum.KeyCode },
	MashToEnable: boolean,
	HideOnLostFocus: boolean,
	UnlocksMouse: boolean,
	TouchButton: boolean,
}

export type ConsoleHost = {
	read Shell: Types.Shell,
	read Settings: Settings.Settings,
	read Activation: ActivationOptions,
	read Keymap: Keymap.Keymap,
	read PlaceName: () -> string,
	read IsConnected: () -> boolean,
	--- Runs a line typed by the user (echo, history, output to the log).
	read Execute: (text: string) -> (),
	--- Cancels the running command (Ctrl+C).
	read Cancel: () -> boolean,
	read IsRunning: () -> boolean,
	read History: () -> { string },
	read CanSee: (command: Types.Command) -> boolean,
	--- Extra completion score (frecency) for a suggestion.
	read Boost: (kind: string, text: string) -> number,
	--- Records that a suggestion was accepted (feeds frecency).
	read Accepted: (kind: string, text: string) -> (),
}

export type Console = {
	read Show: () -> (),
	read Hide: () -> (),
	read Toggle: () -> (),
	read IsVisible: () -> boolean,
	read SetEnabled: (enabled: boolean) -> (),
	--- Adds an output block to the log.
	read AddBlock: (block: Types.Block) -> (),
	--- Echoes an executed input line.
	read AddEcho: (text: string) -> (),
	read Notify: (text: string, level: Types.Level?) -> (),
	--- Shows a prompt (confirm/choice/text) and yields until it is answered.
	read Prompt: (prompt: Types.PromptRequest) -> Types.PromptAnswer,
	read SetRunning: (running: boolean) -> (),
	read Clear: () -> (),
	read OpenPalette: () -> (),
	--- Theme picker with live previews.
	read OpenThemes: () -> (),
	read ExportLog: () -> string,
	read SetTheme: (name: string) -> boolean,
	read GetTheme: () -> string,
	read GetThemes: () -> { string },
	--- Re-applies activation options (keys, mash, touch button) after they change.
	read RefreshActivation: () -> (),
	--- Re-reads the place name (shown in the bar's placeholder).
	read RefreshTitle: () -> (),
	read Toggled: Types.Signal<boolean>,
	read Destroy: () -> (),
}

return table.freeze({})
