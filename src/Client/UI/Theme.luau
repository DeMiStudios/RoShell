--!strict
--[[
	Design tokens. Every color the console draws comes from a theme; components never hard-code colors.

	Themes are defined as hex strings (so they can be validated headlessly: every text token must reach a 4.5:1
	contrast ratio against the surfaces it is drawn on) and resolved to `Color3` palettes at runtime.

		RoShell.Theme.Create({ Name = "Reef", Base = "Midnight", Overrides = { Accent = "#3DD6D0" } })
]]

--// Imports
const Types = require("../../Shared/Types")

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
	--- One line for the theme picker.
	read Description: string?,
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

--- Overrides and creation options are declared in Types.luau so plugins and the shared registry can carry them.
export type SyntaxOverrides = Types.ThemeSyntaxOverrides
export type TypeOverrides = Types.ThemeTypeOverrides
export type Overrides = Types.ThemeOverrides
export type CreateOptions = Types.ThemeOptions

export type ContrastIssue = {
	Theme: string,
	Token: string,
	Surface: string,
	Ratio: number,
}

--// Constants
const MIN_CONTRAST = 4.5
--- How much accent tints a selected row (the panel draws the accent at this opacity over the window color).
const SELECTION_TINT = 0.22
--- Other names players may type for a theme (`theme dark`).
const ALIASES: { [string]: string } = { dark = "Midnight", default = "Midnight", night = "Midnight", pink = "Sakura" }

const PRESETS: { Definition } = {
	{
		Name = "Midnight",
		Description = "Deep navy glass with a periwinkle accent",
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
		Description = "Neutral charcoal with a sky-blue accent",
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
		Description = "Bright paper with an indigo accent",
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
		Name = "Sakura",
		Description = "Cherry-blossom pink on soft petal white",
		Dark = false,
		Window = "#FFF7FA",
		Elevated = "#FFF0F5",
		Input = "#FFF2F7",
		Hover = "#FCE6EE",
		Selected = "#F8D5E3",
		Border = "#F2D3DF",
		BorderFocus = "#C2306C",
		Text = "#3A1F2B",
		TextSecondary = "#6B4152",
		TextMuted = "#7E5566",
		TextInverse = "#FFFFFF",
		Accent = "#C2306C",
		AccentHover = "#A8235A",
		Success = "#1E7A45",
		Warning = "#8C5A00",
		Error = "#BE2A3E",
		Info = "#2F5FBF",
		Shadow = "#5A2A3C",
		Syntax = {
			Command = "#C2306C",
			Argument = "#3A1F2B",
			Number = "#A44A12",
			String = "#2F7A3A",
			Operator = "#7A3FB0",
			Flag = "#8C5A00",
			Variable = "#8E3FAF",
			Comment = "#7E5566",
			Error = "#BE2A3E",
		},
		Types = {
			Player = "#A3306F",
			Team = "#2F7A3A",
			Number = "#A44A12",
			String = "#2F7A3A",
			Boolean = "#8C5A00",
			Instance = "#1F6E7A",
			Color = "#C2306C",
			Enum = "#7A5800",
			Command = "#C2306C",
			Variable = "#8E3FAF",
			Default = "#6B4152",
		},
	},
	{
		Name = "Blossom",
		Description = "Sakura at night: plum dusk with petal pink",
		Dark = true,
		Window = "#1C1219",
		Elevated = "#241720",
		Input = "#170E14",
		Hover = "#2D1C28",
		Selected = "#3D2436",
		Border = "#3A2433",
		BorderFocus = "#FF8FB8",
		Text = "#FBEAF1",
		TextSecondary = "#D9B5C5",
		TextMuted = "#B48C9E",
		TextInverse = "#2A0F1C",
		Accent = "#FF8FB8",
		AccentHover = "#FFB3CF",
		Success = "#7FE0A0",
		Warning = "#FFD27A",
		Error = "#FF7B8A",
		Info = "#8FC3FF",
		Shadow = "#000000",
		Syntax = {
			Command = "#FF8FB8",
			Argument = "#FBEAF1",
			Number = "#FFB38A",
			String = "#B8E994",
			Operator = "#9EE4F0",
			Flag = "#FFD27A",
			Variable = "#D4A5FF",
			Comment = "#B48C9E",
			Error = "#FF7B8A",
		},
		Types = {
			Player = "#FFB3CF",
			Team = "#B8E994",
			Number = "#FFB38A",
			String = "#B8E994",
			Boolean = "#FFD27A",
			Instance = "#9EE4F0",
			Color = "#FF8FB8",
			Enum = "#FFE3A3",
			Command = "#FF8FB8",
			Variable = "#D4A5FF",
			Default = "#D9B5C5",
		},
	},
	{
		Name = "Ocean",
		Description = "Deep sea blue with a lagoon cyan accent",
		Dark = true,
		Window = "#0B1823",
		Elevated = "#10202E",
		Input = "#08131C",
		Hover = "#15293A",
		Selected = "#1C3850",
		Border = "#1D3245",
		BorderFocus = "#3FD2E6",
		Text = "#E3F2F7",
		TextSecondary = "#A6C3CF",
		TextMuted = "#7FA0AE",
		TextInverse = "#04161D",
		Accent = "#3FD2E6",
		AccentHover = "#7BE3F0",
		Success = "#5EE6A8",
		Warning = "#FFD166",
		Error = "#FF7A85",
		Info = "#6FB6FF",
		Shadow = "#000000",
		Syntax = {
			Command = "#3FD2E6",
			Argument = "#E3F2F7",
			Number = "#FFB077",
			String = "#9BE58E",
			Operator = "#8AB4FF",
			Flag = "#FFD166",
			Variable = "#C7A0FF",
			Comment = "#7FA0AE",
			Error = "#FF7A85",
		},
		Types = {
			Player = "#7BE3F0",
			Team = "#9BE58E",
			Number = "#FFB077",
			String = "#9BE58E",
			Boolean = "#FFD166",
			Instance = "#5EE6C8",
			Color = "#FF9EC7",
			Enum = "#FFE08A",
			Command = "#3FD2E6",
			Variable = "#C7A0FF",
			Default = "#A6C3CF",
		},
	},
	{
		Name = "Forest",
		Description = "Pine shade with a fresh moss accent",
		Dark = true,
		Window = "#111A15",
		Elevated = "#16221B",
		Input = "#0D1511",
		Hover = "#1C2B22",
		Selected = "#24392C",
		Border = "#24352B",
		BorderFocus = "#63D78F",
		Text = "#E6F1E9",
		TextSecondary = "#AFC6B6",
		TextMuted = "#88A592",
		TextInverse = "#0A1A10",
		Accent = "#63D78F",
		AccentHover = "#8FE6AE",
		Success = "#63D78F",
		Warning = "#F2C94C",
		Error = "#FF7B72",
		Info = "#79C0FF",
		Shadow = "#000000",
		Syntax = {
			Command = "#63D78F",
			Argument = "#E6F1E9",
			Number = "#F0A868",
			String = "#C5E478",
			Operator = "#7FD1D8",
			Flag = "#F2C94C",
			Variable = "#C4A1FF",
			Comment = "#88A592",
			Error = "#FF7B72",
		},
		Types = {
			Player = "#8FE6AE",
			Team = "#C5E478",
			Number = "#F0A868",
			String = "#C5E478",
			Boolean = "#F2C94C",
			Instance = "#7FD1D8",
			Color = "#F5A3C7",
			Enum = "#F2D98C",
			Command = "#63D78F",
			Variable = "#C4A1FF",
			Default = "#AFC6B6",
		},
	},
	{
		Name = "Ember",
		Description = "Warm charcoal with a glowing ember orange",
		Dark = true,
		Window = "#1B1411",
		Elevated = "#231915",
		Input = "#160F0C",
		Hover = "#2C201A",
		Selected = "#3B2A21",
		Border = "#382920",
		BorderFocus = "#FF9A5A",
		Text = "#F7ECE5",
		TextSecondary = "#D6BFB1",
		TextMuted = "#AE9585",
		TextInverse = "#2A1206",
		Accent = "#FF9A5A",
		AccentHover = "#FFB98A",
		Success = "#8FD694",
		Warning = "#FFD166",
		Error = "#FF6F61",
		Info = "#7DB8FF",
		Shadow = "#000000",
		Syntax = {
			Command = "#FF9A5A",
			Argument = "#F7ECE5",
			Number = "#FFC27A",
			String = "#B5D98A",
			Operator = "#7FD4D0",
			Flag = "#FFD166",
			Variable = "#D9A8FF",
			Comment = "#AE9585",
			Error = "#FF6F61",
		},
		Types = {
			Player = "#FFB98A",
			Team = "#B5D98A",
			Number = "#FFC27A",
			String = "#B5D98A",
			Boolean = "#FFD166",
			Instance = "#7FD4D0",
			Color = "#FF9EB5",
			Enum = "#FFE08A",
			Command = "#FF9A5A",
			Variable = "#D9A8FF",
			Default = "#D6BFB1",
		},
	},
	{
		Name = "Dusk",
		Description = "Twilight violet with a lilac glow",
		Dark = true,
		Window = "#16131F",
		Elevated = "#1D1929",
		Input = "#120F19",
		Hover = "#251F35",
		Selected = "#322A48",
		Border = "#2E2742",
		BorderFocus = "#B794FF",
		Text = "#EEEAF8",
		TextSecondary = "#BDB4D6",
		TextMuted = "#978EB3",
		TextInverse = "#170D2E",
		Accent = "#B794FF",
		AccentHover = "#CDB4FF",
		Success = "#7EE0A8",
		Warning = "#FFD27A",
		Error = "#FF7E9D",
		Info = "#8FB8FF",
		Shadow = "#000000",
		Syntax = {
			Command = "#B794FF",
			Argument = "#EEEAF8",
			Number = "#FFAE85",
			String = "#B6E58C",
			Operator = "#8FDCEB",
			Flag = "#FFD27A",
			Variable = "#FF9ECF",
			Comment = "#978EB3",
			Error = "#FF7E9D",
		},
		Types = {
			Player = "#CDB4FF",
			Team = "#B6E58C",
			Number = "#FFAE85",
			String = "#B6E58C",
			Boolean = "#FFD27A",
			Instance = "#8FDCEB",
			Color = "#FF9ECF",
			Enum = "#FFE3A3",
			Command = "#B794FF",
			Variable = "#FF9ECF",
			Default = "#BDB4D6",
		},
	},
	{
		Name = "Arctic",
		Description = "Frosted slate with a glacier blue",
		Dark = true,
		Window = "#232833",
		Elevated = "#2A303C",
		Input = "#1F242E",
		Hover = "#313846",
		Selected = "#3B4456",
		Border = "#3A4252",
		BorderFocus = "#88C0D0",
		Text = "#ECEFF4",
		TextSecondary = "#CBD2DE",
		TextMuted = "#A7B1C2",
		TextInverse = "#1B2029",
		Accent = "#88C0D0",
		AccentHover = "#A6D2DE",
		Success = "#A3D99B",
		Warning = "#EBCB8B",
		Error = "#F0919B",
		Info = "#91B4E8",
		Shadow = "#000000",
		Syntax = {
			Command = "#88C0D0",
			Argument = "#ECEFF4",
			Number = "#E3A88A",
			String = "#A3D99B",
			Operator = "#8FD3C5",
			Flag = "#EBCB8B",
			Variable = "#C9A3D9",
			Comment = "#A7B1C2",
			Error = "#F0919B",
		},
		Types = {
			Player = "#A6D2DE",
			Team = "#A3D99B",
			Number = "#E3A88A",
			String = "#A3D99B",
			Boolean = "#EBCB8B",
			Instance = "#8FD3C5",
			Color = "#E8A2C0",
			Enum = "#EBD8A8",
			Command = "#88C0D0",
			Variable = "#C9A3D9",
			Default = "#CBD2DE",
		},
	},
	{
		Name = "Lavender",
		Description = "Soft lilac paper with a violet accent",
		Dark = false,
		Window = "#FBF9FF",
		Elevated = "#F4F1FD",
		Input = "#F5F2FE",
		Hover = "#ECE7FB",
		Selected = "#DFD7FA",
		Border = "#DDD6F3",
		BorderFocus = "#6547D3",
		Text = "#231C3B",
		TextSecondary = "#4D4470",
		TextMuted = "#5F5680",
		TextInverse = "#FFFFFF",
		Accent = "#6547D3",
		AccentHover = "#5537C3",
		Success = "#1C7A48",
		Warning = "#8A5800",
		Error = "#BF2E45",
		Info = "#2F5DBF",
		Shadow = "#2A2150",
		Syntax = {
			Command = "#6547D3",
			Argument = "#231C3B",
			Number = "#A24A14",
			String = "#2C7A3C",
			Operator = "#0E6F84",
			Flag = "#8A5800",
			Variable = "#9A3BB0",
			Comment = "#5F5680",
			Error = "#BF2E45",
		},
		Types = {
			Player = "#3A5BC2",
			Team = "#2C7A3C",
			Number = "#A24A14",
			String = "#2C7A3C",
			Boolean = "#8A5800",
			Instance = "#0E6F84",
			Color = "#B42F80",
			Enum = "#7A5800",
			Command = "#6547D3",
			Variable = "#9A3BB0",
			Default = "#4D4470",
		},
	},
	{
		Name = "Mint",
		Description = "Cool mint with an evergreen accent",
		Dark = false,
		Window = "#F6FCF9",
		Elevated = "#EDF8F2",
		Input = "#EFF9F4",
		Hover = "#E2F3EA",
		Selected = "#CDEBDB",
		Border = "#CFE8DA",
		BorderFocus = "#0E7A4F",
		Text = "#13291F",
		TextSecondary = "#355447",
		TextMuted = "#4A6A5C",
		TextInverse = "#FFFFFF",
		Accent = "#0E7A4F",
		AccentHover = "#0A6641",
		Success = "#1C7A3C",
		Warning = "#8A5800",
		Error = "#BE2F3A",
		Info = "#1F5FB8",
		Shadow = "#123526",
		Syntax = {
			Command = "#0E7A4F",
			Argument = "#13291F",
			Number = "#A04A14",
			String = "#3D7316",
			Operator = "#0E6A84",
			Flag = "#8A5800",
			Variable = "#8A3FB0",
			Comment = "#4A6A5C",
			Error = "#BE2F3A",
		},
		Types = {
			Player = "#0B6A8A",
			Team = "#3D7316",
			Number = "#A04A14",
			String = "#3D7316",
			Boolean = "#8A5800",
			Instance = "#0E6A84",
			Color = "#B42F6E",
			Enum = "#7A5800",
			Command = "#0E7A4F",
			Variable = "#8A3FB0",
			Default = "#355447",
		},
	},
	{
		Name = "Sand",
		Description = "Sunlit parchment with a terracotta accent",
		Dark = false,
		Window = "#FCF8F1",
		Elevated = "#F6EFE3",
		Input = "#F7F1E6",
		Hover = "#EFE5D4",
		Selected = "#E6D6BC",
		Border = "#E4D6C0",
		BorderFocus = "#9E4F14",
		Text = "#2E241B",
		TextSecondary = "#5A4A3B",
		TextMuted = "#6A5847",
		TextInverse = "#FFFFFF",
		Accent = "#9E4F14",
		AccentHover = "#86420F",
		Success = "#2B6E2F",
		Warning = "#865000",
		Error = "#B52D2D",
		Info = "#2C5BA8",
		Shadow = "#3A2A1C",
		Syntax = {
			Command = "#9E4F14",
			Argument = "#2E241B",
			Number = "#A33E1A",
			String = "#3F6A12",
			Operator = "#126A7A",
			Flag = "#865000",
			Variable = "#86389E",
			Comment = "#6A5847",
			Error = "#B52D2D",
		},
		Types = {
			Player = "#1F5F99",
			Team = "#3F6A12",
			Number = "#A33E1A",
			String = "#3F6A12",
			Boolean = "#865000",
			Instance = "#126A7A",
			Color = "#AA2F66",
			Enum = "#755000",
			Command = "#9E4F14",
			Variable = "#86389E",
			Default = "#5A4A3B",
		},
	},
	{
		Name = "HighContrast",
		Description = "Maximum legibility: black, white and yellow",
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
		Description = "The classic teal-dark solarized palette",
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
		Description = "Cozy mocha with pastel mauve highlights",
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

--- Lowercase letters and digits only, so `high contrast`, `High-Contrast` and `highcontrast` match.
const function simplify(name: string): string
	return (name:lower():gsub("[^%w]", ""))
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

--- Finds a theme by name, ignoring case, spaces and punctuation (`theme high contrast`), or by alias (`dark`).
function Theme.Find(name: string): string?
	const wanted = simplify(name)
	if wanted == "" then
		return nil
	end
	for _, candidate in order do
		if simplify(candidate) == wanted then
			return candidate
		end
	end
	const alias = ALIASES[wanted]
	return if alias and definitions[alias] then alias else nil
end

--- The opacity at which the accent tints a selected row.
Theme.SelectionTint = SELECTION_TINT

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
		Description = options.Description or `Based on {base.Name}`,
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
		Description = definition.Description,
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
	-- Rows highlighted with the accent tint carry primary and secondary text.
	const selection = Theme.Mix(definition.Window, definition.Accent, SELECTION_TINT)
	for _, token in {
		{ Name = "Text", Hex = definition.Text },
		{ Name = "TextSecondary", Hex = definition.TextSecondary },
	} do
		const ratio = Theme.Contrast(token.Hex, selection)
		if ratio < MIN_CONTRAST then
			table.insert(issues, { Theme = definition.Name, Token = token.Name, Surface = "Selection", Ratio = ratio })
		end
	end
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
