--!strict
--[[
	Design tokens. Every color the console draws comes from a theme; components never hard-code colors.

	Themes are defined as hex strings (so they can be validated headlessly: every text token must reach a 4.5:1
	contrast ratio against the surfaces it is drawn on) and resolved to `Color3` palettes at runtime.

		RoShell.Theme.Create({ Name = "Ocean", Base = "Midnight", Overrides = { Accent = "#3DD6D0" } })
]]

--// Types
export type SyntaxTokens<C> = {
	read Command: C,
	read Argument: C,
	read Number: C,
	read String: C,
	read Operator: C,
	read Flag: C,
	read Variable: C,
	read Comment: C,
	read Error: C,
}

--- Badge colors of argument types (`Type.Color = "type.player"` resolves to `Types.Player`).
export type TypeTokens<C> = {
	read Player: C,
	read Team: C,
	read Number: C,
	read String: C,
	read Boolean: C,
	read Instance: C,
	read Color: C,
	read Enum: C,
	read Command: C,
	read Variable: C,
	read Default: C,
}

export type Tokens<C> = {
	read Name: string,
	read Dark: boolean,
	--- `bg.window`, `bg.elevated`, `bg.input`, `bg.hover`, `bg.selected`
	read Window: C,
	read Elevated: C,
	read Input: C,
	read Hover: C,
	read Selected: C,
	--- `border.subtle`, `border.focus`
	read Border: C,
	read BorderFocus: C,
	--- `text.primary`, `text.secondary`, `text.muted`, `text.inverse`
	read Text: C,
	read TextSecondary: C,
	read TextMuted: C,
	read TextInverse: C,
	--- `accent.primary`, `accent.hover`
	read Accent: C,
	read AccentHover: C,
	read Success: C,
	read Warning: C,
	read Error: C,
	read Info: C,
	read Shadow: C,
	read Syntax: SyntaxTokens<C>,
	read Types: TypeTokens<C>,
}

export type Definition = Tokens<string>
export type Palette = Tokens<Color3>

export type SyntaxOverrides = {
	Command: string?,
	Argument: string?,
	Number: string?,
	String: string?,
	Operator: string?,
	Flag: string?,
	Variable: string?,
	Comment: string?,
	Error: string?,
}

export type TypeOverrides = {
	Player: string?,
	Team: string?,
	Number: string?,
	String: string?,
	Boolean: string?,
	Instance: string?,
	Color: string?,
	Enum: string?,
	Command: string?,
	Variable: string?,
	Default: string?,
}

export type Overrides = {
	Window: string?,
	Elevated: string?,
	Input: string?,
	Hover: string?,
	Selected: string?,
	Border: string?,
	BorderFocus: string?,
	Text: string?,
	TextSecondary: string?,
	TextMuted: string?,
	TextInverse: string?,
	Accent: string?,
	AccentHover: string?,
	Success: string?,
	Warning: string?,
	Error: string?,
	Info: string?,
	Shadow: string?,
	Syntax: SyntaxOverrides?,
	Types: TypeOverrides?,
}

export type CreateOptions = {
	Name: string,
	--- Preset (or previously created theme) the overrides apply to. Defaults to "Midnight".
	Base: string?,
	Dark: boolean?,
	Overrides: Overrides?,
}

export type ContrastIssue = {
	Theme: string,
	Token: string,
	Surface: string,
	Ratio: number,
}

--// Constants
const MIN_CONTRAST = 4.5

const PRESETS: { Definition } = {
	{
		Name = "Midnight",
		Dark = true,
		Window = "#12151E",
		Elevated = "#191D29",
		Input = "#0E1118",
		Hover = "#1F2433",
		Selected = "#283048",
		Border = "#272D3D",
		BorderFocus = "#7C9CFF",
		Text = "#E6E9F2",
		TextSecondary = "#AAB2C8",
		TextMuted = "#7F89A3",
		TextInverse = "#0B0D12",
		Accent = "#7C9CFF",
		AccentHover = "#9DB4FF",
		Success = "#4ADE80",
		Warning = "#FBBF24",
		Error = "#FF7A7A",
		Info = "#60A5FA",
		Shadow = "#000000",
		Syntax = {
			Command = "#82AAFF",
			Argument = "#E6E9F2",
			Number = "#F78C6C",
			String = "#C3E88D",
			Operator = "#89DDFF",
			Flag = "#FFCB6B",
			Variable = "#C792EA",
			Comment = "#7F89A3",
			Error = "#FF6B81",
		},
		Types = {
			Player = "#7DD3FC",
			Team = "#86EFAC",
			Number = "#F78C6C",
			String = "#C3E88D",
			Boolean = "#FFCB6B",
			Instance = "#5EEAD4",
			Color = "#F9A8D4",
			Enum = "#FDE68A",
			Command = "#82AAFF",
			Variable = "#C792EA",
			Default = "#AAB2C8",
		},
	},
	{
		Name = "Graphite",
		Dark = true,
		Window = "#18181B",
		Elevated = "#1F1F23",
		Input = "#131315",
		Hover = "#27272A",
		Selected = "#32323A",
		Border = "#2E2E34",
		BorderFocus = "#38BDF8",
		Text = "#F4F4F5",
		TextSecondary = "#B8B8C0",
		TextMuted = "#8E8E98",
		TextInverse = "#0A0A0B",
		Accent = "#38BDF8",
		AccentHover = "#7DD3FC",
		Success = "#4ADE80",
		Warning = "#FACC15",
		Error = "#F87171",
		Info = "#60A5FA",
		Shadow = "#000000",
		Syntax = {
			Command = "#38BDF8",
			Argument = "#F4F4F5",
			Number = "#FB923C",
			String = "#A3E635",
			Operator = "#E879F9",
			Flag = "#FACC15",
			Variable = "#C084FC",
			Comment = "#8E8E98",
			Error = "#F87171",
		},
		Types = {
			Player = "#67E8F9",
			Team = "#86EFAC",
			Number = "#FB923C",
			String = "#A3E635",
			Boolean = "#FACC15",
			Instance = "#5EEAD4",
			Color = "#F9A8D4",
			Enum = "#FDE68A",
			Command = "#38BDF8",
			Variable = "#C084FC",
			Default = "#B8B8C0",
		},
	},
	{
		Name = "Light",
		Dark = false,
		Window = "#FFFFFF",
		Elevated = "#F6F7F9",
		Input = "#F3F5F8",
		Hover = "#ECEFF4",
		Selected = "#DFE6F7",
		Border = "#DCE0E8",
		BorderFocus = "#3B5BDB",
		Text = "#1A1D24",
		TextSecondary = "#465063",
		TextMuted = "#5F6878",
		TextInverse = "#FFFFFF",
		Accent = "#3B5BDB",
		AccentHover = "#2F4AC0",
		Success = "#137333",
		Warning = "#8A5300",
		Error = "#C62828",
		Info = "#1D4ED8",
		Shadow = "#1A2233",
		Syntax = {
			Command = "#3B5BDB",
			Argument = "#1A1D24",
			Number = "#A14A00",
			String = "#137333",
			Operator = "#0B6E80",
			Flag = "#8A5300",
			Variable = "#7E22CE",
			Comment = "#5F6878",
			Error = "#C62828",
		},
		Types = {
			Player = "#0369A1",
			Team = "#137333",
			Number = "#A14A00",
			String = "#137333",
			Boolean = "#8A5300",
			Instance = "#0B6E80",
			Color = "#BE185D",
			Enum = "#7C5800",
			Command = "#3B5BDB",
			Variable = "#7E22CE",
			Default = "#465063",
		},
	},
	{
		Name = "HighContrast",
		Dark = true,
		Window = "#000000",
		Elevated = "#0B0B0B",
		Input = "#000000",
		Hover = "#1C1C1C",
		Selected = "#00336B",
		Border = "#FFFFFF",
		BorderFocus = "#FFD400",
		Text = "#FFFFFF",
		TextSecondary = "#EDEDED",
		TextMuted = "#CFCFCF",
		TextInverse = "#000000",
		Accent = "#FFD400",
		AccentHover = "#FFE45C",
		Success = "#3DFF6E",
		Warning = "#FFD400",
		Error = "#FF6B6B",
		Info = "#6CD3FF",
		Shadow = "#000000",
		Syntax = {
			Command = "#6CD3FF",
			Argument = "#FFFFFF",
			Number = "#FFB86B",
			String = "#3DFF6E",
			Operator = "#FF8CF0",
			Flag = "#FFD400",
			Variable = "#D9A6FF",
			Comment = "#CFCFCF",
			Error = "#FF6B6B",
		},
		Types = {
			Player = "#6CD3FF",
			Team = "#3DFF6E",
			Number = "#FFB86B",
			String = "#3DFF6E",
			Boolean = "#FFD400",
			Instance = "#7CFFE4",
			Color = "#FF8CF0",
			Enum = "#FFE45C",
			Command = "#6CD3FF",
			Variable = "#D9A6FF",
			Default = "#EDEDED",
		},
	},
	{
		Name = "Solarized",
		Dark = true,
		Window = "#002B36",
		Elevated = "#04313D",
		Input = "#00232C",
		Hover = "#0A3B48",
		Selected = "#114B5A",
		Border = "#0E4250",
		BorderFocus = "#4AA3E3",
		Text = "#EEE8D5",
		TextSecondary = "#B5C0C0",
		TextMuted = "#93A1A1",
		TextInverse = "#002B36",
		Accent = "#4AA3E3",
		AccentHover = "#74BBEC",
		Success = "#A7BD1A",
		Warning = "#D9A61A",
		Error = "#F2665E",
		Info = "#3CC2B5",
		Shadow = "#00141A",
		Syntax = {
			Command = "#4AA3E3",
			Argument = "#EEE8D5",
			Number = "#F47C4D",
			String = "#A7BD1A",
			Operator = "#3CC2B5",
			Flag = "#D9A61A",
			Variable = "#9C9FEA",
			Comment = "#93A1A1",
			Error = "#F2665E",
		},
		Types = {
			Player = "#4AA3E3",
			Team = "#A7BD1A",
			Number = "#F47C4D",
			String = "#A7BD1A",
			Boolean = "#D9A61A",
			Instance = "#3CC2B5",
			Color = "#EC6FA9",
			Enum = "#D9A61A",
			Command = "#4AA3E3",
			Variable = "#9C9FEA",
			Default = "#B5C0C0",
		},
	},
	{
		Name = "Mocha",
		Dark = true,
		Window = "#1E1E2E",
		Elevated = "#24243A",
		Input = "#181825",
		Hover = "#2A2B3D",
		Selected = "#393B54",
		Border = "#313244",
		BorderFocus = "#CBA6F7",
		Text = "#CDD6F4",
		TextSecondary = "#BAC2DE",
		TextMuted = "#9399B2",
		TextInverse = "#11111B",
		Accent = "#CBA6F7",
		AccentHover = "#DDC4FA",
		Success = "#A6E3A1",
		Warning = "#F9E2AF",
		Error = "#F38BA8",
		Info = "#89B4FA",
		Shadow = "#11111B",
		Syntax = {
			Command = "#89B4FA",
			Argument = "#CDD6F4",
			Number = "#FAB387",
			String = "#A6E3A1",
			Operator = "#94E2D5",
			Flag = "#F9E2AF",
			Variable = "#CBA6F7",
			Comment = "#9399B2",
			Error = "#F38BA8",
		},
		Types = {
			Player = "#89DCEB",
			Team = "#A6E3A1",
			Number = "#FAB387",
			String = "#A6E3A1",
			Boolean = "#F9E2AF",
			Instance = "#94E2D5",
			Color = "#F5C2E7",
			Enum = "#F9E2AF",
			Command = "#89B4FA",
			Variable = "#CBA6F7",
			Default = "#BAC2DE",
		},
	},
}

--// Globals
const definitions: { [string]: Definition } = {}
const order: { string } = {}
const palettes: { [string]: Palette } = {}

--// Helpers

const function register(definition: Definition)
	if definitions[definition.Name] == nil then
		table.insert(order, definition.Name)
	end
	definitions[definition.Name] = definition
	palettes[definition.Name] = nil
end

for _, preset in PRESETS do
	register(preset)
end

const function channel(hex: string, index: number): number
	const value = tonumber(hex:sub(2 + (index - 1) * 2, 1 + index * 2), 16)
	return (value or 0) / 255
end

const function linear(value: number): number
	return if value <= 0.03928 then value / 12.92 else ((value + 0.055) / 1.055) ^ 2.4
end

const function luminance(hex: string): number
	return 0.2126 * linear(channel(hex, 1)) + 0.7152 * linear(channel(hex, 2)) + 0.0722 * linear(channel(hex, 3))
end

const function isHex(value: string): boolean
	return value:match("^#%x%x%x%x%x%x$") ~= nil
end

const function color(hex: string): Color3
	return Color3.fromHex(hex)
end

--// Theme
const Theme = {}

Theme.MinContrast = MIN_CONTRAST

--- WCAG contrast ratio between two `#RRGGBB` colors (1-21).
function Theme.Contrast(foreground: string, background: string): number
	const a = luminance(foreground)
	const b = luminance(background)
	return (math.max(a, b) + 0.05) / (math.min(a, b) + 0.05)
end

--- Blends two hex colors (`amount` 0 = a, 1 = b).
function Theme.Mix(a: string, b: string, amount: number): string
	const parts: { string } = {}
	for index = 1, 3 do
		const value = channel(a, index) + (channel(b, index) - channel(a, index)) * amount
		parts[index] = string.format("%02X", math.floor(value * 255 + 0.5))
	end
	return "#" .. table.concat(parts)
end

--- Names of every registered theme, presets first.
function Theme.Names(): { string }
	return table.clone(order)
end

function Theme.Has(name: string): boolean
	return definitions[name] ~= nil
end

--- Finds a theme name case-insensitively.
function Theme.Find(name: string): string?
	const lowered = name:lower()
	for _, candidate in order do
		if candidate:lower() == lowered then
			return candidate
		end
	end
	return nil
end

function Theme.Definition(name: string): Definition
	return definitions[name] or PRESETS[1]
end

--- Registers a theme derived from a base theme. Invalid hex values are rejected with an error.
function Theme.Create(options: CreateOptions): Definition
	const base = Theme.Definition(options.Base or "Midnight")
	const overrides: Overrides = options.Overrides or {}
	const syntax: SyntaxOverrides = overrides.Syntax or {}
	const types: TypeOverrides = overrides.Types or {}
	const function pick(value: string?, fallback: string, token: string): string
		if value == nil then
			return fallback
		end
		assert(isHex(value), `Theme '{options.Name}': {token} must be a #RRGGBB color, got '{value}'`)
		return value:upper()
	end
	const definition: Definition = {
		Name = options.Name,
		Dark = if options.Dark ~= nil then options.Dark else base.Dark,
		Window = pick(overrides.Window, base.Window, "Window"),
		Elevated = pick(overrides.Elevated, base.Elevated, "Elevated"),
		Input = pick(overrides.Input, base.Input, "Input"),
		Hover = pick(overrides.Hover, base.Hover, "Hover"),
		Selected = pick(overrides.Selected, base.Selected, "Selected"),
		Border = pick(overrides.Border, base.Border, "Border"),
		BorderFocus = pick(overrides.BorderFocus, base.BorderFocus, "BorderFocus"),
		Text = pick(overrides.Text, base.Text, "Text"),
		TextSecondary = pick(overrides.TextSecondary, base.TextSecondary, "TextSecondary"),
		TextMuted = pick(overrides.TextMuted, base.TextMuted, "TextMuted"),
		TextInverse = pick(overrides.TextInverse, base.TextInverse, "TextInverse"),
		Accent = pick(overrides.Accent, base.Accent, "Accent"),
		AccentHover = pick(overrides.AccentHover, base.AccentHover, "AccentHover"),
		Success = pick(overrides.Success, base.Success, "Success"),
		Warning = pick(overrides.Warning, base.Warning, "Warning"),
		Error = pick(overrides.Error, base.Error, "Error"),
		Info = pick(overrides.Info, base.Info, "Info"),
		Shadow = pick(overrides.Shadow, base.Shadow, "Shadow"),
		Syntax = {
			Command = pick(syntax.Command, base.Syntax.Command, "Syntax.Command"),
			Argument = pick(syntax.Argument, base.Syntax.Argument, "Syntax.Argument"),
			Number = pick(syntax.Number, base.Syntax.Number, "Syntax.Number"),
			String = pick(syntax.String, base.Syntax.String, "Syntax.String"),
			Operator = pick(syntax.Operator, base.Syntax.Operator, "Syntax.Operator"),
			Flag = pick(syntax.Flag, base.Syntax.Flag, "Syntax.Flag"),
			Variable = pick(syntax.Variable, base.Syntax.Variable, "Syntax.Variable"),
			Comment = pick(syntax.Comment, base.Syntax.Comment, "Syntax.Comment"),
			Error = pick(syntax.Error, base.Syntax.Error, "Syntax.Error"),
		},
		Types = {
			Player = pick(types.Player, base.Types.Player, "Types.Player"),
			Team = pick(types.Team, base.Types.Team, "Types.Team"),
			Number = pick(types.Number, base.Types.Number, "Types.Number"),
			String = pick(types.String, base.Types.String, "Types.String"),
			Boolean = pick(types.Boolean, base.Types.Boolean, "Types.Boolean"),
			Instance = pick(types.Instance, base.Types.Instance, "Types.Instance"),
			Color = pick(types.Color, base.Types.Color, "Types.Color"),
			Enum = pick(types.Enum, base.Types.Enum, "Types.Enum"),
			Command = pick(types.Command, base.Types.Command, "Types.Command"),
			Variable = pick(types.Variable, base.Types.Variable, "Types.Variable"),
			Default = pick(types.Default, base.Types.Default, "Types.Default"),
		},
	}
	register(definition)
	return definition
end

--- The color of a type token (`"type.player"`, `"player"`) in either a definition or a palette, falling back
--- to `Types.Default`.
function Theme.TypeToken<C>(types: TypeTokens<C>, token: string?): C
	const name = if token then (token:match("^type%.(.+)$") or token):lower() else "default"
	if name == "player" or name == "players" then
		return types.Player
	elseif name == "team" or name == "teams" then
		return types.Team
	elseif name == "number" or name == "integer" or name == "time" then
		return types.Number
	elseif name == "string" then
		return types.String
	elseif name == "boolean" then
		return types.Boolean
	elseif name == "instance" or name == "class" then
		return types.Instance
	elseif name == "color" then
		return types.Color
	elseif name == "enum" then
		return types.Enum
	elseif name == "command" then
		return types.Command
	elseif name == "variable" then
		return types.Variable
	end
	return types.Default
end

--- Returns the resolved `Color3` palette of a theme (cached).
function Theme.Get(name: string): Palette
	const definition = Theme.Definition(name)
	const cached = palettes[definition.Name]
	if cached then
		return cached
	end
	const syntax = definition.Syntax
	const types = definition.Types
	const palette: Palette = table.freeze({
		Name = definition.Name,
		Dark = definition.Dark,
		Window = color(definition.Window),
		Elevated = color(definition.Elevated),
		Input = color(definition.Input),
		Hover = color(definition.Hover),
		Selected = color(definition.Selected),
		Border = color(definition.Border),
		BorderFocus = color(definition.BorderFocus),
		Text = color(definition.Text),
		TextSecondary = color(definition.TextSecondary),
		TextMuted = color(definition.TextMuted),
		TextInverse = color(definition.TextInverse),
		Accent = color(definition.Accent),
		AccentHover = color(definition.AccentHover),
		Success = color(definition.Success),
		Warning = color(definition.Warning),
		Error = color(definition.Error),
		Info = color(definition.Info),
		Shadow = color(definition.Shadow),
		Syntax = table.freeze({
			Command = color(syntax.Command),
			Argument = color(syntax.Argument),
			Number = color(syntax.Number),
			String = color(syntax.String),
			Operator = color(syntax.Operator),
			Flag = color(syntax.Flag),
			Variable = color(syntax.Variable),
			Comment = color(syntax.Comment),
			Error = color(syntax.Error),
		}),
		Types = table.freeze({
			Player = color(types.Player),
			Team = color(types.Team),
			Number = color(types.Number),
			String = color(types.String),
			Boolean = color(types.Boolean),
			Instance = color(types.Instance),
			Color = color(types.Color),
			Enum = color(types.Enum),
			Command = color(types.Command),
			Variable = color(types.Variable),
			Default = color(types.Default),
		}),
	})
	palettes[definition.Name] = palette
	return palette
end

--- Checks every text token of a theme against the surfaces it is drawn on. Returns the failures.
function Theme.Audit(definition: Definition): { ContrastIssue }
	const issues: { ContrastIssue } = {}
	const surfaces = {
		{ Name = "Window", Hex = definition.Window },
		{ Name = "Input", Hex = definition.Input },
		{ Name = "Elevated", Hex = definition.Elevated },
	}
	const syntax = definition.Syntax
	const types = definition.Types
	const tokens = {
		{ Name = "Text", Hex = definition.Text },
		{ Name = "TextSecondary", Hex = definition.TextSecondary },
		{ Name = "TextMuted", Hex = definition.TextMuted },
		{ Name = "Accent", Hex = definition.Accent },
		{ Name = "Success", Hex = definition.Success },
		{ Name = "Warning", Hex = definition.Warning },
		{ Name = "Error", Hex = definition.Error },
		{ Name = "Info", Hex = definition.Info },
		{ Name = "Syntax.Command", Hex = syntax.Command },
		{ Name = "Syntax.Argument", Hex = syntax.Argument },
		{ Name = "Syntax.Number", Hex = syntax.Number },
		{ Name = "Syntax.String", Hex = syntax.String },
		{ Name = "Syntax.Operator", Hex = syntax.Operator },
		{ Name = "Syntax.Flag", Hex = syntax.Flag },
		{ Name = "Syntax.Variable", Hex = syntax.Variable },
		{ Name = "Syntax.Comment", Hex = syntax.Comment },
		{ Name = "Syntax.Error", Hex = syntax.Error },
		{ Name = "Types.Player", Hex = types.Player },
		{ Name = "Types.Team", Hex = types.Team },
		{ Name = "Types.Number", Hex = types.Number },
		{ Name = "Types.String", Hex = types.String },
		{ Name = "Types.Boolean", Hex = types.Boolean },
		{ Name = "Types.Instance", Hex = types.Instance },
		{ Name = "Types.Color", Hex = types.Color },
		{ Name = "Types.Enum", Hex = types.Enum },
		{ Name = "Types.Command", Hex = types.Command },
		{ Name = "Types.Variable", Hex = types.Variable },
		{ Name = "Types.Default", Hex = types.Default },
	}
	for _, surface in surfaces do
		for _, token in tokens do
			const ratio = Theme.Contrast(token.Hex, surface.Hex)
			if ratio < MIN_CONTRAST then
				table.insert(issues, {
					Theme = definition.Name,
					Token = token.Name,
					Surface = surface.Name,
					Ratio = ratio,
				})
			end
		end
	end
	-- Text drawn on accent-filled controls (buttons, the selected chip).
	const inverse = Theme.Contrast(definition.TextInverse, definition.Accent)
	if inverse < MIN_CONTRAST then
		table.insert(issues, { Theme = definition.Name, Token = "TextInverse", Surface = "Accent", Ratio = inverse })
	end
	return issues
end

return table.freeze(Theme)
