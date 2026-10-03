--!strict
--[[
	Small instance helpers and the typography/spacing metrics shared by every component. Icons live in Icons.luau.
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
	read TextXl: number,
	--- Monospace size used by the log (and the input with the mono font).
	read Mono: number,
	--- Width of one monospace cell and the height of one line.
	read MonoWidth: number,
	read LineHeight: number,
	--- The command bar.
	read BarHeight: number,
	read BarWidth: number,
	--- Text size of the command bar's input with the sans font.
	read BarText: number,
	--- Prompt dialogs' text field.
	read InputHeight: number,
	--- Two-line list rows (commands, palette entries) and one-line rows (values).
	read RowRich: number,
	read RowCompact: number,
	--- Rounded square behind a rich row's icon, and icon glyph size.
	read IconBox: number,
	read IconSize: number,
	--- Space between the bar and the panel, and inside the panel.
	read PanelGap: number,
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

--// Globals
const metricsCache: { [string]: Metrics } = {}

--// Ui
const Ui = {}

Ui.Fonts = table.freeze({ Sans = FONT_SANS, Medium = FONT_SANS_MEDIUM, Bold = FONT_SANS_BOLD, Mono = FONT_MONO })

--- Spacing scale (2/4/8/12/16/24) and radius scale.
Ui.Space = table.freeze({ XXS = 2, XS = 4, S = 8, M = 12, L = 16, XL = 24 })
Ui.Radius = table.freeze({ S = 4, M = 8, L = 12, XL = 16, Panel = 16, Row = 10, Key = 6 })

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

--- Width of a single line of text in pixels, trailing spaces included (measured with a sentinel).
function Ui.TextWidth(text: string, size: number, font: Enum.Font): number
	if text == "" then
		return 0
	end
	return Ui.Measure(text .. "|", size, font).X - Ui.Measure("|", size, font).X
end

--- Width of a monospace string in pixels. ASCII uses the cell width; anything else is measured.
function Ui.MonoTextWidth(text: string, metrics: Metrics): number
	if text == "" then
		return 0
	end
	if not text:find("[\128-\255]") then
		return #text * metrics.MonoWidth
	end
	return Ui.TextWidth(text, metrics.Mono, FONT_MONO)
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
	-- Fingers need bigger targets than a mouse.
	const touchBoost = if touch then 1.22 else 1
	const metrics: Metrics = table.freeze({
		Scale = scale,
		Compact = compact,
		Touch = touch,
		TextXs = size(11),
		TextSm = size(13),
		TextMd = size(15),
		TextLg = size(17),
		TextXl = size(19),
		Mono = mono,
		MonoWidth = sample.X / 64,
		LineHeight = sample.Y,
		BarHeight = math.floor(size(if compact then 44 else 50) * (if touch then 1.12 else 1)),
		BarWidth = math.floor(760 * math.min(1.3, scale)),
		BarText = size(if compact then 17 else 18),
		InputHeight = math.floor(size(if compact then 36 else 40) * touchBoost),
		RowRich = math.floor(size(if compact then 48 else 56) * touchBoost),
		RowCompact = math.floor(size(if compact then 32 else 38) * touchBoost),
		IconBox = size(if compact then 30 else 34),
		IconSize = size(if compact then 18 else 20),
		PanelGap = 8,
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

--- Removes RichText tags and decodes the escapes (for measuring rich text).
function Ui.StripRich(rich: string): string
	return (rich:gsub("<[^>]*>", ""):gsub("&lt;", "<"):gsub("&gt;", ">"):gsub("&quot;", '"'):gsub("&apos;", "'"):gsub(
		"&amp;",
		"&"
	))
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

--- Whether a screen point (AbsolutePosition space) lies inside a GUI object.
function Ui.Contains(object: GuiObject, point: Vector2): boolean
	const position = object.AbsolutePosition
	const size = object.AbsoluteSize
	return point.X >= position.X
		and point.X <= position.X + size.X
		and point.Y >= position.Y
		and point.Y <= position.Y + size.Y
end

return table.freeze(Ui)
