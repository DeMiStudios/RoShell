--!strict
--[[
	Small instance helpers, typography/spacing metrics and the icon set shared by every component.
]]

--// Types
--- Sizes derived from the text scale, density and input device. Components read these instead of constants.
export type Metrics = {
	read Scale: number,
	read Compact: boolean,
	read Touch: boolean,
	read TextXs: number,
	read TextSm: number,
	read TextMd: number,
	read TextLg: number,
	--- Monospace size used by the input and the log.
	read Mono: number,
	--- Width of one monospace cell and the height of one line.
	read MonoWidth: number,
	read LineHeight: number,
	read TitleHeight: number,
	read InputHeight: number,
	read SignatureHeight: number,
	read SuggestionRow: number,
	read RowPadding: number,
	read Gap: number,
	read Pad: number,
}

--// Constants
const FONT_SANS = Enum.Font.BuilderSans
const FONT_SANS_MEDIUM = Enum.Font.BuilderSansMedium
const FONT_SANS_BOLD = Enum.Font.BuilderSansBold
const FONT_MONO = Enum.Font.RobotoMono
const HUGE = Vector2.new(100000, 100000)

--- Glyph icons by suggestion kind / type icon / level. Plain Unicode so nothing needs to load; every glyph here
--- was checked to render (and tint) in BuilderSans and RobotoMono — many common symbols such as ❯ ✕ ⌕ ↺ ⚑
--- are missing from Roblox's fonts, and others (⚙ ↪ ✔) fall back to fixed-color emoji.
const ICONS: { [string]: string } = {
	command = "⌘",
	alias = "→",
	subcommand = "›",
	argument = "◇",
	flag = "-",
	operator = "*",
	variable = "$",
	history = "↑",
	value = "◆",
	player = "●",
	team = "◉",
	number = "#",
	string = "“",
	boolean = "◐",
	instance = "◈",
	class = "◈",
	color = "●",
	enum = "≡",
	tag = "#",
	time = "◔",
	vector = "↗",
	key = "⌥",
	type = "τ",
	remote = "⇄",
	theme = "◑",
	setting = "≡",
	action = "→",
	success = "✓",
	error = "×",
	warning = "▲",
	info = "i",
	echo = "›",
	muted = "·",
	plain = "",
}

--// Globals
const metricsCache: { [string]: Metrics } = {}

--// Ui
const Ui = {}

Ui.Fonts = table.freeze({ Sans = FONT_SANS, Medium = FONT_SANS_MEDIUM, Bold = FONT_SANS_BOLD, Mono = FONT_MONO })

--- Spacing scale (2/4/8/12/16/24) and radius scale (4/8/12/16).
Ui.Space = table.freeze({ XXS = 2, XS = 4, S = 8, M = 12, L = 16, XL = 24 })
Ui.Radius = table.freeze({ S = 4, M = 8, L = 12, XL = 16, Window = 12, Input = 10 })

function Ui.Icon(kind: string?): string
	if kind == nil then
		return ICONS.value
	end
	return ICONS[kind] or ICONS[kind:lower()] or ICONS.value
end

--- `#rrggbb` for RichText.
function Ui.Hex(color: Color3): string
	return "#" .. color:ToHex()
end

--- Measures text with an engine font.
function Ui.Measure(text: string, size: number, font: Enum.Font, width: number?): Vector2
	return game:GetService("TextService"):GetTextSize(
		text,
		size,
		font,
		if width then Vector2.new(width, 100000) else HUGE
	)
end

--- Width of a monospace string in pixels. ASCII uses the cell width; anything else is measured.
function Ui.MonoTextWidth(text: string, metrics: Metrics): number
	if text == "" then
		return 0
	end
	if not text:find("[\128-\255]") then
		return #text * metrics.MonoWidth
	end
	-- Measured with a sentinel so trailing spaces count.
	const withSentinel = Ui.Measure(text .. "|", metrics.Mono, FONT_MONO).X
	return withSentinel - Ui.Measure("|", metrics.Mono, FONT_MONO).X
end

function Ui.Metrics(scale: number, compact: boolean, touch: boolean): Metrics
	const key = `{scale}:{compact}:{touch}`
	const cached = metricsCache[key]
	if cached then
		return cached
	end
	const function size(base: number): number
		return math.floor(base * scale + 0.5)
	end
	const mono = size(if compact then 13 else 14)
	const sample = Ui.Measure(string.rep("M", 64), mono, FONT_MONO)
	const touchBoost = if touch then 1.35 else 1
	const metrics: Metrics = table.freeze({
		Scale = scale,
		Compact = compact,
		Touch = touch,
		TextXs = size(11),
		TextSm = size(12),
		TextMd = size(14),
		TextLg = size(16),
		Mono = mono,
		MonoWidth = sample.X / 64,
		LineHeight = sample.Y,
		TitleHeight = math.floor(size(if compact then 30 else 34) * (if touch then 1.2 else 1)),
		InputHeight = math.floor(size(if compact then 36 else 42) * touchBoost),
		SignatureHeight = size(if compact then 22 else 26),
		SuggestionRow = math.floor(size(if compact then 26 else 30) * touchBoost),
		RowPadding = if compact then 2 else 4,
		Gap = if compact then 6 else 8,
		Pad = if compact then 8 else 12,
	})
	metricsCache[key] = metrics
	return metrics
end

function Ui.Corner(parent: Instance, radius: number): UICorner
	const corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = parent
	return corner
end

function Ui.Stroke(parent: Instance, color: Color3, transparency: number?, thickness: number?): UIStroke
	const stroke = Instance.new("UIStroke")
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Color = color
	stroke.Transparency = transparency or 0
	stroke.Thickness = thickness or 1
	stroke.Parent = parent
	return stroke
end

function Ui.Padding(parent: Instance, top: number, right: number?, bottom: number?, left: number?): UIPadding
	const padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, top)
	padding.PaddingRight = UDim.new(0, right or top)
	padding.PaddingBottom = UDim.new(0, bottom or top)
	padding.PaddingLeft = UDim.new(0, left or right or top)
	padding.Parent = parent
	return padding
end

function Ui.List(parent: Instance, direction: Enum.FillDirection, gap: number, alignment: Enum.VerticalAlignment?): UIListLayout
	const layout = Instance.new("UIListLayout")
	layout.FillDirection = direction
	layout.Padding = UDim.new(0, gap)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.VerticalAlignment = alignment or Enum.VerticalAlignment.Center
	layout.Parent = parent
	return layout
end

--- A transparent frame.
function Ui.Frame(name: string, parent: Instance?): Frame
	const frame = Instance.new("Frame")
	frame.Name = name
	frame.BackgroundTransparency = 1
	frame.BorderSizePixel = 0
	frame.Parent = parent
	return frame
end

--- A transparent single-line label.
function Ui.Label(name: string, parent: Instance?, font: Enum.Font, size: number): TextLabel
	const label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.BorderSizePixel = 0
	label.Font = font
	label.TextSize = size
	label.Text = ""
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Center
	label.Parent = parent
	return label
end

--- A borderless button with no default styling.
function Ui.Button(name: string, parent: Instance?): TextButton
	const button = Instance.new("TextButton")
	button.Name = name
	button.AutoButtonColor = false
	button.BackgroundTransparency = 1
	button.BorderSizePixel = 0
	button.Text = ""
	button.Parent = parent
	return button
end

--- Rich text with match ranges highlighted (`ranges` are byte spans within `text`).
function Ui.HighlightRanges(text: string, ranges: { Span }?, open: string, close: string): string
	const escape = Ui.Escape
	if ranges == nil or #ranges == 0 then
		return escape(text)
	end
	const parts: { string } = {}
	local cursor = 1
	for _, range in ranges do
		if range.Start > cursor then
			table.insert(parts, escape(text:sub(cursor, range.Start - 1)))
		end
		if range.End > range.Start and range.Start >= cursor then
			table.insert(parts, open .. escape(text:sub(range.Start, range.End - 1)) .. close)
			cursor = range.End
		end
	end
	if cursor <= #text then
		table.insert(parts, escape(text:sub(cursor)))
	end
	return table.concat(parts)
end

export type Span = { Start: number, End: number }

--- Escapes RichText markup characters.
function Ui.Escape(text: string): string
	return (text:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"):gsub('"', "&quot;"):gsub("'", "&apos;"))
end

--- Shared mouse-over handling for a button: `onHover(true/false)`.
function Ui.Hover(button: GuiObject, onHover: (hovered: boolean) -> ())
	button.MouseEnter:Connect(function()
		onHover(true)
	end)
	button.MouseLeave:Connect(function()
		onHover(false)
	end)
end

return table.freeze(Ui)
