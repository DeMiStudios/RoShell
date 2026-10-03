--!strict
--[[
	Console key bindings. Every action can be remapped through `ClientOptions.Keymap`:

		RoShell.Client.new({ Keymap = { Palette = { { Key = Enum.KeyCode.P, Ctrl = true, Shift = true } } } })

	Notes on Roblox text input: a focused `TextBox` still reports key presses through `UserInputService` (with
	`gameProcessedEvent = true`), Enter/Escape also release focus (the console refocuses), and Tab would insert a
	tab character (the input bar strips it), so every binding here works while typing.
]]

--// Types
export type Action = "Accept" | "AcceptBackward" | "AcceptGhost" | "Up" | "Down" | "ForceSuggest" | "HistorySearch" | "ClearLog" | "DeleteWord" | "WordLeft" | "WordRight" | "Undo" | "Redo" | "Cancel" | "Palette" | "Help"

export type Chord = {
	Key: Enum.KeyCode,
	--- Ctrl (or Cmd on macOS).
	Ctrl: boolean?,
	Shift: boolean?,
	Alt: boolean?,
}

export type Keymap = { [Action]: { Chord } }

export type Modifiers = { Ctrl: boolean, Shift: boolean, Alt: boolean }

--// Constants
const ACTIONS: { Action } = {
	"Accept",
	"AcceptBackward",
	"AcceptGhost",
	"Up",
	"Down",
	"ForceSuggest",
	"HistorySearch",
	"ClearLog",
	"DeleteWord",
	"WordLeft",
	"WordRight",
	"Undo",
	"Redo",
	"Cancel",
	"Palette",
	"Help",
}

--- Built on first use: `Enum` does not exist outside Roblox, and this module is loaded by headless tools.
const function defaults(): Keymap
	return {
		Accept = { { Key = Enum.KeyCode.Tab }, { Key = Enum.KeyCode.ButtonR1 } },
		AcceptBackward = { { Key = Enum.KeyCode.Tab, Shift = true }, { Key = Enum.KeyCode.ButtonL1 } },
		AcceptGhost = { { Key = Enum.KeyCode.Right }, { Key = Enum.KeyCode.End } },
		Up = { { Key = Enum.KeyCode.Up }, { Key = Enum.KeyCode.DPadUp } },
		Down = { { Key = Enum.KeyCode.Down }, { Key = Enum.KeyCode.DPadDown } },
		ForceSuggest = { { Key = Enum.KeyCode.Space, Ctrl = true } },
		HistorySearch = { { Key = Enum.KeyCode.R, Ctrl = true } },
		ClearLog = { { Key = Enum.KeyCode.L, Ctrl = true } },
		DeleteWord = { { Key = Enum.KeyCode.W, Ctrl = true }, { Key = Enum.KeyCode.Backspace, Alt = true } },
		WordLeft = { { Key = Enum.KeyCode.Left, Ctrl = true } },
		WordRight = { { Key = Enum.KeyCode.Right, Ctrl = true } },
		Undo = { { Key = Enum.KeyCode.Z, Ctrl = true } },
		Redo = { { Key = Enum.KeyCode.Z, Ctrl = true, Shift = true }, { Key = Enum.KeyCode.Y, Ctrl = true } },
		Cancel = { { Key = Enum.KeyCode.C, Ctrl = true } },
		Palette = { { Key = Enum.KeyCode.K, Ctrl = true } },
		Help = { { Key = Enum.KeyCode.F1 } },
	}
end

--// Keymap
const KeymapModule = {}

KeymapModule.Actions = ACTIONS
KeymapModule.Defaults = defaults

--- The default keymap with `overrides` replacing whole actions.
function KeymapModule.Merge(overrides: Keymap?): Keymap
	const merged = defaults()
	if overrides then
		for _, action in ACTIONS do
			const chords = overrides[action]
			if chords then
				merged[action] = chords
			end
		end
	end
	return merged
end

--- Reads the modifier keys currently held.
function KeymapModule.Modifiers(): Modifiers
	const UserInputService = game:GetService("UserInputService")
	const function down(a: Enum.KeyCode, b: Enum.KeyCode): boolean
		return UserInputService:IsKeyDown(a) or UserInputService:IsKeyDown(b)
	end
	return {
		Ctrl = down(Enum.KeyCode.LeftControl, Enum.KeyCode.RightControl)
			or down(Enum.KeyCode.LeftMeta, Enum.KeyCode.RightMeta),
		Shift = down(Enum.KeyCode.LeftShift, Enum.KeyCode.RightShift),
		Alt = down(Enum.KeyCode.LeftAlt, Enum.KeyCode.RightAlt),
	}
end

--- The action bound to `key` with exactly these modifiers, if any.
function KeymapModule.Match(keymap: Keymap, key: Enum.KeyCode, modifiers: Modifiers): Action?
	for _, action in ACTIONS do
		const chords = keymap[action]
		if chords then
			for _, chord in chords do
				if chord.Key == key
					and (chord.Ctrl == true) == modifiers.Ctrl
					and (chord.Shift == true) == modifiers.Shift
					and (chord.Alt == true) == modifiers.Alt then
					return action
				end
			end
		end
	end
	return nil
end

--- Human readable chord ("Ctrl+K").
function KeymapModule.Describe(chord: Chord): string
	return (if chord.Ctrl then "Ctrl+" else "")
		.. (if chord.Shift then "Shift+" else "")
		.. (if chord.Alt then "Alt+" else "")
		.. chord.Key.Name
end

return table.freeze(KeymapModule)
