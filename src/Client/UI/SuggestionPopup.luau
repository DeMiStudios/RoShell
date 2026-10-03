--!strict
--[[
	The completion popup: a header naming what is being completed, the suggestion list, and a footer with the
	highlighted suggestion's description (or key hints). The console positions it above the input at the start of
	the replaced text. On touch devices the console uses a chip row instead (`SuggestionChips`).
]]

--// Imports
const Motion = require("./Motion")
const ResultList = require("./ResultList")
const Surface = require("./Surface")
const Theme = require("./Theme")
const Ui = require("./Ui")

--// Types
export type SuggestionPopup = {
	read Holder: Frame,
	read List: ResultList.ResultList,
	read Show: (header: string, items: { ResultList.Item }, selected: number?, footer: string?) -> (),
	read SetFooter: (text: string?) -> (),
	read Hide: () -> (),
	read IsOpen: () -> boolean,
	--- Places the popup with its bottom-left corner at `anchor` (screen space), clamped inside `bounds`.
	read Place: (anchor: Vector2, bounds: Rect, below: boolean) -> (),
	read SetTheme: (palette: Theme.Palette) -> (),
	read SetMetrics: (metrics: Ui.Metrics) -> (),
	read Destroy: () -> (),
}

--// Constants
const WIDTH = 420
const HINT = "Tab accept · ↑↓ select · Esc close"

--// SuggestionPopup
const SuggestionPopupModule = {}

function SuggestionPopupModule.new(parent: Instance, initialPalette: Theme.Palette, initialMetrics: Ui.Metrics): SuggestionPopup
	local palette = initialPalette
	local metrics = initialMetrics
	local open = false
	local footerText: string? = nil

	const surface = Surface.new("Suggestions", parent, Ui.Radius.L - 2, palette, true)
	const holder = surface.Holder
	holder.Visible = false
	holder.ZIndex = 20
	const card = surface.Card
	card.ClipsDescendants = true
	const scale = Instance.new("UIScale")
	scale.Parent = holder

	const header = Ui.Label("Header", card, Ui.Fonts.Medium, metrics.TextXs)
	const list = ResultList.new(card, palette, metrics)
	const divider = Ui.Frame("Divider", card)
	divider.BackgroundTransparency = 0
	const footer = Ui.Label("Footer", card, Ui.Fonts.Sans, metrics.TextXs)
	footer.TextTruncate = Enum.TextTruncate.AtEnd
	footer.TextWrapped = false

	const function headerHeight(): number
		return metrics.TextXs + 12
	end

	const function footerHeight(): number
		return metrics.TextXs + 14
	end

	const function layout()
		const listHeight = list.DesiredHeight()
		const height = headerHeight() + listHeight + footerHeight() + 6
		holder.Size = UDim2.fromOffset(math.floor(WIDTH * math.min(1.25, metrics.Scale)), height)
		header.Position = UDim2.fromOffset(14, 2)
		header.Size = UDim2.new(1, -28, 0, headerHeight())
		header.TextSize = metrics.TextXs
		list.Frame.Position = UDim2.fromOffset(0, headerHeight())
		list.Frame.Size = UDim2.new(1, 0, 0, listHeight)
		divider.Position = UDim2.fromOffset(0, headerHeight() + listHeight + 3)
		divider.Size = UDim2.new(1, 0, 0, 1)
		footer.Position = UDim2.fromOffset(14, headerHeight() + listHeight + 4)
		footer.Size = UDim2.new(1, -28, 0, footerHeight())
		footer.TextSize = metrics.TextXs
	end

	const function applyTheme()
		surface.SetTheme(palette)
		header.TextColor3 = palette.TextMuted
		divider.BackgroundColor3 = palette.Border
		footer.TextColor3 = palette.TextSecondary
		list.SetTheme(palette)
	end

	const popup: SuggestionPopup = {
		Holder = holder,
		List = list,
		Show = function(title: string, items: { ResultList.Item }, selected: number?, footerValue: string?)
			const opening = not open
			header.Text = title:upper()
			footerText = footerValue
			footer.Text = footerValue or HINT
			list.SetItems(items, selected, opening)
			layout()
			if opening then
				open = true
				holder.Visible = true
				scale.Scale = if Motion.Reduced() then 1 else 0.97
				Motion.Tween(scale, 0.14, { Scale = 1 })
			end
		end,
		SetFooter = function(text: string?)
			if text ~= footerText then
				footerText = text
				footer.Text = text or HINT
			end
		end,
		Hide = function()
			if not open then
				return
			end
			open = false
			holder.Visible = false
			list.SetItems({}, nil, false)
		end,
		IsOpen = function(): boolean
			return open
		end,
		Place = function(anchor: Vector2, bounds: Rect, below: boolean)
			const size = holder.AbsoluteSize
			const parentPosition = if parent:IsA("GuiObject") then parent.AbsolutePosition else Vector2.zero
			local x = math.clamp(anchor.X - 14, bounds.Min.X, math.max(bounds.Min.X, bounds.Max.X - size.X))
			local y = if below then anchor.Y + 6 else anchor.Y - size.Y - 6
			y = math.clamp(y, bounds.Min.Y, math.max(bounds.Min.Y, bounds.Max.Y - size.Y))
			holder.Position = UDim2.fromOffset(x - parentPosition.X, y - parentPosition.Y)
		end,
		SetTheme = function(next: Theme.Palette)
			palette = next
			applyTheme()
		end,
		SetMetrics = function(next: Ui.Metrics)
			metrics = next
			list.SetMetrics(next)
			layout()
		end,
		Destroy = function()
			list.Destroy()
			holder:Destroy()
		end,
	}
	applyTheme()
	layout()
	return popup
end

return table.freeze(SuggestionPopupModule)
