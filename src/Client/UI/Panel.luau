--!strict
--[[
	The panel that pops out of the command bar: below a bar docked to the top, above one docked to the bottom, and on
	whichever side has more room for a floating bar. It is slightly narrower than the bar, springs to the height its
	content asks for (within the room available), and fades in sliding away from the bar.
]]

--// Imports
const Motion = require("./Motion")
const Surface = require("./Surface")
const Theme = require("./Theme")
const Ui = require("./Ui")

--// Types
export type Side = "below" | "above"

export type Rect = { X: number, Y: number, Width: number, Height: number }

export type Panel = {
	read Holder: Frame,
	--- Views put their content here (it fills the panel).
	read Content: Frame,
	read Show: () -> (),
	read Hide: () -> (),
	read IsOpen: () -> boolean,
	--- Height the content would like (clamped to the room available).
	read SetHeight: (height: number) -> (),
	--- Puts the panel next to the bar. `floor`/`ceiling` bound the room (keyboard, top bar).
	read Place: (bar: Rect, floating: boolean, preferAbove: boolean, floor: number, ceiling: number) -> (),
	--- Room available on the side the panel opens on.
	read MaxHeight: () -> number,
	read Width: () -> number,
	read Side: () -> Side,
	--- Screen bounds right now (AbsolutePosition space).
	read Bounds: () -> Rect,
	read SetOpacity: (opacity: number) -> (),
	read SetTheme: (palette: Theme.Palette) -> (),
	read SetMetrics: (metrics: Ui.Metrics) -> (),
	read Destroy: () -> (),
}

--// Constants
--- Tallest the panel gets (scaled with the text).
const MAX_HEIGHT = 460
--- The panel is inset from the bar's ends when the bar is wide enough.
const INSET = 20
const INSET_MIN_WIDTH = 600

--// Panel
const PanelModule = {}

function PanelModule.new(parent: GuiObject, initialPalette: Theme.Palette, initialMetrics: Ui.Metrics): Panel
	local palette = initialPalette
	local metrics = initialMetrics
	local open = false
	local generation = 0
	local desired = 0
	local side: Side = "below"
	local barRect: Rect = { X = 0, Y = 0, Width = 0, Height = 0 }
	local floating = false
	local preferAbove = false
	local floorY = 0
	local ceilingY = 0

	const surface = Surface.new("Panel", parent, Ui.Radius.Panel, palette, { Canvas = true })
	const holder = surface.Holder
	holder.Visible = false
	holder.ZIndex = 19
	const content = Ui.Frame("Content", surface.Card)
	content.Size = UDim2.fromScale(1, 1)
	content.ClipsDescendants = true

	const function inset(): number
		return if barRect.Width >= INSET_MIN_WIDTH then INSET else 0
	end

	const function room(which: Side): number
		const gap = metrics.PanelGap
		if which == "below" then
			return math.max(0, floorY - (barRect.Y + barRect.Height + gap))
		end
		return math.max(0, barRect.Y - gap - ceilingY)
	end

	const function chooseSide(): Side
		if not floating then
			return if preferAbove then "above" else "below"
		end
		-- Floating: below when the content fits there, else wherever there is more room.
		const below = room("below")
		const above = room("above")
		if below >= math.min(desired, MAX_HEIGHT * metrics.Scale) or below >= above then
			return "below"
		end
		return "above"
	end

	const function maxHeight(): number
		return math.floor(math.min(room(side), MAX_HEIGHT * math.min(1.3, metrics.Scale)))
	end

	const function applyGeometry(value: number)
		const panelWidth = barRect.Width - inset() * 2
		const x = barRect.X + inset()
		const gap = metrics.PanelGap
		const y = if side == "below" then barRect.Y + barRect.Height + gap else barRect.Y - gap - value
		holder.Size = UDim2.fromOffset(panelWidth, math.max(0, math.floor(value + 0.5)))
		holder.Position = UDim2.fromOffset(x, math.floor(y + 0.5))
	end

	const heightSpring = Motion.Spring(0, 7, 1, applyGeometry)
	const fadeSpring = Motion.Spring(0, 6, 1, function(alpha: number)
		surface.SetFade(alpha)
	end)

	const function target(): number
		return math.min(desired, maxHeight())
	end

	const function relayout(animate: boolean)
		side = chooseSide()
		if animate and open then
			heightSpring.SetTarget(target())
		else
			heightSpring.Snap(target())
		end
		applyGeometry(heightSpring.Get())
	end

	const panel: Panel = {
		Holder = holder,
		Content = content,
		Show = function()
			if open then
				return
			end
			open = true
			generation += 1
			side = chooseSide()
			heightSpring.Snap(target())
			holder.Visible = true
			fadeSpring.SetTarget(1)
			-- Slide out of the bar.
			const final = holder.Position
			const offset = if side == "below" then -6 else 6
			holder.Position = final + UDim2.fromOffset(0, offset)
			Motion.Tween(holder, 0.16, { Position = final })
		end,
		Hide = function()
			if not open then
				return
			end
			open = false
			generation += 1
			const closing = generation
			fadeSpring.SetTarget(0)
			task.delay(if Motion.Reduced() then 0 else 0.14, function()
				if generation == closing then
					holder.Visible = false
					fadeSpring.Snap(0)
				end
			end)
		end,
		IsOpen = function(): boolean
			return open
		end,
		SetHeight = function(value: number)
			if value == desired then
				return
			end
			desired = math.max(0, value)
			relayout(true)
		end,
		Place = function(rect: Rect, isFloating: boolean, above: boolean, floor: number, ceiling: number)
			barRect = rect
			floating = isFloating
			preferAbove = above
			floorY = floor
			ceilingY = ceiling
			relayout(false)
		end,
		MaxHeight = maxHeight,
		Width = function(): number
			return barRect.Width - inset() * 2
		end,
		Side = function(): Side
			return side
		end,
		Bounds = function(): Rect
			const position = holder.AbsolutePosition
			const size = holder.AbsoluteSize
			return { X = position.X, Y = position.Y, Width = size.X, Height = size.Y }
		end,
		SetOpacity = surface.SetOpacity,
		SetTheme = function(next: Theme.Palette)
			palette = next
			surface.SetTheme(palette)
		end,
		SetMetrics = function(next: Ui.Metrics)
			metrics = next
			relayout(false)
		end,
		Destroy = function()
			heightSpring.Destroy()
			fadeSpring.Destroy()
			holder:Destroy()
		end,
	}
	surface.SetTheme(palette)
	fadeSpring.Snap(0)
	return panel
end

return table.freeze(PanelModule)
