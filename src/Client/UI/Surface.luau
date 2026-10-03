--!strict
--[[
	A rounded card with a 1 px border and a soft drop shadow made of layered transparent frames (Roblox has no
	native shadows). The holder is what callers position and size; the card fills it.
]]

--// Imports
const Theme = require("./Theme")
const Ui = require("./Ui")

--// Types
export type Surface = {
	--- Position/size this frame.
	read Holder: Frame,
	--- Put content in this frame (a `CanvasGroup` when created with `canvas`, so it can fade as one).
	read Card: GuiObject,
	read Group: CanvasGroup?,
	read Stroke: UIStroke,
	read SetTheme: (palette: Theme.Palette) -> (),
	read SetElevation: (elevation: number) -> (),
	--- Scales the shadow's opacity (0 hidden, 1 normal) for open/close transitions.
	read SetFade: (alpha: number) -> (),
}

--// Constants
const LAYERS = 4

--// Surface
const SurfaceModule = {}

function SurfaceModule.new(
	name: string,
	parent: Instance,
	radius: number,
	palette: Theme.Palette,
	elevated: boolean?,
	canvas: boolean?
): Surface
	const holder = Ui.Frame(name, parent)
	const shadows: { Frame } = {}
	local elevation = 1
	local current = palette
	local fade = 1
	for index = 1, LAYERS do
		const layer = Ui.Frame("Shadow" .. index, holder)
		layer.BackgroundTransparency = 1
		layer.ZIndex = 0
		Ui.Corner(layer, radius + index * 2)
		shadows[index] = layer
	end
	const group = if canvas then Instance.new("CanvasGroup") else nil
	const card: GuiObject = group or Instance.new("Frame")
	card.Name = "Card"
	card.BorderSizePixel = 0
	card.Size = UDim2.fromScale(1, 1)
	card.ZIndex = 1
	card.Parent = holder
	Ui.Corner(card, radius)
	const stroke = Ui.Stroke(card, palette.Border)

	const function layoutShadows(colors: Theme.Palette)
		const strength = if colors.Dark then 1 else 0.55
		for index, layer in shadows do
			const spread = index * 3 * elevation
			layer.Size = UDim2.new(1, spread * 2, 1, spread * 2)
			layer.Position = UDim2.fromOffset(-spread, -spread + math.floor(index * 1.5 * elevation))
			layer.BackgroundColor3 = colors.Shadow
			layer.BackgroundTransparency = 1 - (0.11 - index * 0.02) * strength * fade
		end
	end

	const surface: Surface = {
		Holder = holder,
		Card = card,
		Group = group,
		Stroke = stroke,
		SetTheme = function(next: Theme.Palette)
			current = next
			card.BackgroundColor3 = if elevated then next.Elevated else next.Window
			stroke.Color = next.Border
			layoutShadows(next)
		end,
		SetElevation = function(value: number)
			elevation = value
			layoutShadows(current)
		end,
		SetFade = function(alpha: number)
			fade = alpha
			layoutShadows(current)
		end,
	}
	surface.SetTheme(palette)
	return table.freeze(surface)
end

return table.freeze(SurfaceModule)
