--!strict
--[[
	A glass card: rounded, translucent, with a 1 px border and a faint top sheen on dark themes. No drop shadow —
	the border separates it from the game. The holder is what callers position and size; the card fills it and can
	be a `CanvasGroup` so everything inside fades as one.
]]

--// Imports
const Theme = require("./Theme")
const Ui = require("./Ui")

--// Types
export type Options = {
	--- Make the card a `CanvasGroup` (fades with `SetFade`).
	Canvas: boolean?,
	--- Use the elevated surface color instead of the window color.
	Elevated: boolean?,
}

export type Surface = {
	--- Position/size this frame.
	read Holder: Frame,
	--- Put content in this frame (a `CanvasGroup` when created with `Canvas`).
	read Card: GuiObject,
	read Group: CanvasGroup?,
	read Stroke: UIStroke,
	read SetTheme: (palette: Theme.Palette) -> (),
	--- Background opacity (0.5-1).
	read SetOpacity: (opacity: number) -> (),
	--- Visibility of the whole card (0 hidden, 1 shown); needs `Canvas`.
	read SetFade: (alpha: number) -> (),
	--- Border in the focus color.
	read SetFocused: (focused: boolean) -> (),
}

--// Surface
const SurfaceModule = {}

function SurfaceModule.new(name: string, parent: Instance, radius: number, palette: Theme.Palette, options: Options?): Surface
	const settings: Options = options or {}
	local current = palette
	local opacity = 0.95
	local focused = false

	const holder = Ui.Frame(name, parent)
	const group = if settings.Canvas then Instance.new("CanvasGroup") else nil
	const card: GuiObject = group or Instance.new("Frame")
	card.Name = "Card"
	card.BorderSizePixel = 0
	card.Size = UDim2.fromScale(1, 1)
	card.Parent = holder
	Ui.Corner(card, radius)
	const stroke = Ui.Stroke(card, palette.Border)

	const sheen = Ui.Frame("Sheen", card)
	sheen.BackgroundTransparency = 0
	sheen.BackgroundColor3 = Color3.new(1, 1, 1)
	sheen.Size = UDim2.fromScale(1, 1)
	sheen.ZIndex = 0
	Ui.Corner(sheen, radius)
	const gradient = Instance.new("UIGradient")
	gradient.Rotation = 90
	gradient.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.94),
		NumberSequenceKeypoint.new(0.45, 1),
		NumberSequenceKeypoint.new(1, 1),
	})
	gradient.Parent = sheen

	const function paint()
		card.BackgroundColor3 = if settings.Elevated then current.Elevated else current.Window
		card.BackgroundTransparency = 1 - opacity
		stroke.Color = if focused then current.BorderFocus else current.Border
		stroke.Transparency = if focused then 0.35 elseif current.Dark then 0.1 else 0
		sheen.Visible = current.Dark
	end

	const surface: Surface = {
		Holder = holder,
		Card = card,
		Group = group,
		Stroke = stroke,
		SetTheme = function(next: Theme.Palette)
			current = next
			paint()
		end,
		SetOpacity = function(value: number)
			opacity = math.clamp(value, 0.5, 1)
			paint()
		end,
		SetFade = function(alpha: number)
			if group then
				group.GroupTransparency = 1 - math.clamp(alpha, 0, 1)
			end
		end,
		SetFocused = function(value: boolean)
			if value ~= focused then
				focused = value
				paint()
			end
		end,
	}
	paint()
	return table.freeze(surface)
end

return table.freeze(SurfaceModule)
