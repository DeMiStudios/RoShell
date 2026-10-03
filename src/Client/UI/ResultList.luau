--!strict
--[[
	A virtualized, keyboard/mouse/touch selectable list with fuzzy-match highlighting and a single sliding
	selection highlight. Used by the suggestion popup, the command palette, history search and choice prompts.
]]

--// Imports
const Motion = require("./Motion")
const Signal = require("../../Shared/Signal")
const Theme = require("./Theme")
const Types = require("../../Shared/Types")
const Ui = require("./Ui")

--// Types
export type Item = {
	Label: string,
	--- Byte spans of `Label` to emphasize (fuzzy matches).
	Ranges: { Ui.Span }?,
	Detail: string?,
	Icon: string?,
	Tint: Color3?,
	Swatch: Color3?,
	Deprecated: boolean?,
}

export type ResultList = {
	read Frame: Frame,
	--- Replaces the items. `animate` staggers the first rows in.
	read SetItems: (items: { Item }, selected: number?, animate: boolean?) -> (),
	read SetSelected: (index: number?) -> (),
	read GetSelected: () -> number?,
	read Move: (delta: number) -> (),
	read Count: () -> number,
	--- Height needed to show `min(count, maxRows)` rows.
	read DesiredHeight: () -> number,
	read SetMaxRows: (rows: number) -> (),
	read SetTheme: (palette: Theme.Palette) -> (),
	read SetMetrics: (metrics: Ui.Metrics) -> (),
	--- Row clicked/tapped.
	read Activated: Types.Signal<number>,
	--- Row hovered (selection follows the mouse).
	read Hovered: Types.Signal<number>,
	read Destroy: () -> (),
}

type Row = {
	Button: TextButton,
	Badge: Frame,
	Glyph: TextLabel,
	Label: TextLabel,
	Detail: TextLabel,
	Index: number,
}

--// Constants
const STAGGER = 0.012
const STAGGER_ROWS = 6

--// ResultList
const ResultListModule = {}

function ResultListModule.new(parent: Instance, initialPalette: Theme.Palette, initialMetrics: Ui.Metrics): ResultList
	local palette = initialPalette
	local metrics = initialMetrics
	local items: { Item } = {}
	local selected: number? = nil
	local maxRows = 8
	const rows: { Row } = {}
	const activated: Types.Signal<number> = Signal.new()
	const hovered: Types.Signal<number> = Signal.new()

	const frame = Ui.Frame("List", parent)
	frame.ClipsDescendants = true

	const scroll = Instance.new("ScrollingFrame")
	scroll.Name = "Scroll"
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.Size = UDim2.fromScale(1, 1)
	scroll.ScrollBarThickness = 3
	scroll.ScrollingDirection = Enum.ScrollingDirection.Y
	scroll.ElasticBehavior = Enum.ElasticBehavior.Never
	scroll.CanvasSize = UDim2.new()
	scroll.Parent = frame

	const highlight = Ui.Frame("Highlight", scroll)
	highlight.BackgroundTransparency = 0
	highlight.Visible = false
	Ui.Corner(highlight, Ui.Radius.M - 2)
	const highlightBar = Ui.Frame("Bar", highlight)
	highlightBar.BackgroundTransparency = 0
	highlightBar.Size = UDim2.new(0, 3, 0.6, 0)
	highlightBar.Position = UDim2.fromScale(0, 0.2)
	Ui.Corner(highlightBar, 2)

	const highlightSpring = Motion.Spring(0, 16, 0.85, function(y: number)
		highlight.Position = UDim2.fromOffset(4, y)
	end)

	const function rowHeight(): number
		return metrics.SuggestionRow
	end

	const function makeRow(): Row
		const button = Ui.Button("Row", scroll)
		button.ZIndex = 2
		const badge = Ui.Frame("Badge", button)
		badge.BackgroundTransparency = 0.82
		Ui.Corner(badge, Ui.Radius.S + 1)
		const glyph = Ui.Label("Glyph", badge, Ui.Fonts.Bold, metrics.TextSm)
		glyph.Size = UDim2.fromScale(1, 1)
		glyph.TextXAlignment = Enum.TextXAlignment.Center
		const label = Ui.Label("Label", button, Ui.Fonts.Mono, metrics.Mono)
		label.RichText = true
		label.TextTruncate = Enum.TextTruncate.AtEnd
		const detail = Ui.Label("Detail", button, Ui.Fonts.Sans, metrics.TextSm)
		detail.TextXAlignment = Enum.TextXAlignment.Right
		detail.TextTruncate = Enum.TextTruncate.AtEnd
		detail.AnchorPoint = Vector2.new(1, 0)
		const row: Row = { Button = button, Badge = badge, Glyph = glyph, Label = label, Detail = detail, Index = 0 }
		button.MouseEnter:Connect(function()
			if row.Index > 0 then
				hovered:Fire(row.Index)
			end
		end)
		button.Activated:Connect(function()
			if row.Index > 0 then
				activated:Fire(row.Index)
			end
		end)
		return row
	end

	const function bind(row: Row, index: number, item: Item)
		const height = rowHeight()
		row.Index = index
		const button = row.Button
		button.Visible = true
		button.Position = UDim2.fromOffset(0, (index - 1) * height)
		button.Size = UDim2.new(1, 0, 0, height)

		const badgeSize = height - 10
		row.Badge.Position = UDim2.fromOffset(10, 5)
		row.Badge.Size = UDim2.fromOffset(badgeSize, badgeSize)
		const tint = item.Swatch or item.Tint or palette.TextSecondary
		row.Badge.BackgroundColor3 = tint
		row.Badge.BackgroundTransparency = if item.Swatch then 0 else 0.82
		row.Glyph.Text = if item.Swatch then "" else item.Icon or "◆"
		row.Glyph.TextColor3 = tint
		row.Glyph.TextSize = metrics.TextSm

		const isSelected = index == selected
		const accent = Ui.Hex(palette.Accent)
		local rich = Ui.HighlightRanges(item.Label, item.Ranges, `<font color="{accent}"><b>`, "</b></font>")
		if item.Deprecated then
			rich = `<s>{rich}</s>`
		end
		row.Label.Text = rich
		row.Label.TextSize = metrics.Mono
		row.Label.TextColor3 = if item.Deprecated then palette.TextMuted else palette.Text
		const labelLeft = 10 + badgeSize + 10
		const detailText = item.Detail or ""
		const detailWidth = if detailText == "" then 0
			else math.min(Ui.Measure(detailText, metrics.TextSm, Ui.Fonts.Sans).X + 4, frame.AbsoluteSize.X * 0.42)
		row.Label.Position = UDim2.fromOffset(labelLeft, 0)
		row.Label.Size = UDim2.new(1, -(labelLeft + detailWidth + 22), 1, 0)
		row.Detail.Text = detailText
		row.Detail.TextSize = metrics.TextSm
		row.Detail.TextColor3 = if isSelected then palette.TextSecondary else palette.TextMuted
		row.Detail.Position = UDim2.new(1, -12, 0, 0)
		row.Detail.Size = UDim2.new(0, detailWidth, 1, 0)
	end

	const function render()
		const height = rowHeight()
		const first = math.max(1, math.floor(scroll.CanvasPosition.Y / height) + 1)
		const last = math.min(#items, first + math.ceil(frame.AbsoluteSize.Y / height) + 1)
		local used = 0
		for index = first, last do
			used += 1
			local row = rows[used]
			if row == nil then
				row = makeRow()
				rows[used] = row
			end
			bind(row, index, items[index])
		end
		for index = used + 1, #rows do
			rows[index].Button.Visible = false
			rows[index].Index = 0
		end
	end

	const function ensureVisible(index: number)
		const height = rowHeight()
		const top = (index - 1) * height
		const viewHeight = frame.AbsoluteSize.Y
		const current = scroll.CanvasPosition.Y
		if top < current then
			scroll.CanvasPosition = Vector2.new(0, top)
		elseif top + height > current + viewHeight then
			scroll.CanvasPosition = Vector2.new(0, top + height - viewHeight)
		end
	end

	const function placeHighlight(snap: boolean)
		const index = selected
		if index == nil or items[index] == nil then
			highlight.Visible = false
			return
		end
		highlight.Visible = true
		highlight.Size = UDim2.new(1, -8, 0, rowHeight())
		const y = (index - 1) * rowHeight()
		if snap or not highlight.Visible then
			highlightSpring.Snap(y)
		else
			highlightSpring.SetTarget(y)
		end
	end

	const function applyTheme()
		highlight.BackgroundColor3 = palette.Selected
		highlightBar.BackgroundColor3 = palette.Accent
		scroll.ScrollBarImageColor3 = palette.TextMuted
	end

	scroll:GetPropertyChangedSignal("CanvasPosition"):Connect(render)
	frame:GetPropertyChangedSignal("AbsoluteSize"):Connect(render)

	const list: ResultList = {
		Frame = frame,
		SetItems = function(nextItems: { Item }, nextSelected: number?, animate: boolean?)
			const wasEmpty = #items == 0
			items = nextItems
			selected = if nextSelected and nextItems[nextSelected] then nextSelected else nil
			scroll.CanvasSize = UDim2.fromOffset(0, #items * rowHeight())
			scroll.CanvasPosition = Vector2.zero
			render()
			placeHighlight(wasEmpty)
			if selected then
				ensureVisible(selected)
			end
			if animate and not Motion.Reduced() then
				for index = 1, math.min(STAGGER_ROWS, #rows) do
					const row = rows[index]
					if row.Index > 0 then
						row.Label.TextTransparency = 1
						row.Badge.Position = UDim2.fromOffset(10, 9)
						Motion.Tween(row.Label, 0.16, { TextTransparency = 0 }, nil, nil, (index - 1) * STAGGER)
						Motion.Tween(
							row.Badge,
							0.16,
							{ Position = UDim2.fromOffset(10, 5) },
							nil,
							nil,
							(index - 1) * STAGGER
						)
					end
				end
			end
		end,
		SetSelected = function(index: number?)
			selected = if index and items[index] then index else nil
			if selected then
				ensureVisible(selected)
			end
			render()
			placeHighlight(false)
		end,
		GetSelected = function(): number?
			return selected
		end,
		Move = function(delta: number)
			if #items == 0 then
				return
			end
			const current = selected or (if delta > 0 then 0 else #items + 1)
			const index = (current + delta - 1) % #items + 1
			selected = index
			ensureVisible(index)
			render()
			placeHighlight(false)
		end,
		Count = function(): number
			return #items
		end,
		DesiredHeight = function(): number
			return math.min(#items, maxRows) * rowHeight()
		end,
		SetMaxRows = function(rowsCount: number)
			maxRows = rowsCount
		end,
		SetTheme = function(next: Theme.Palette)
			palette = next
			applyTheme()
			render()
		end,
		SetMetrics = function(next: Ui.Metrics)
			metrics = next
			scroll.CanvasSize = UDim2.fromOffset(0, #items * rowHeight())
			render()
			placeHighlight(true)
		end,
		Activated = activated,
		Hovered = hovered,
		Destroy = function()
			highlightSpring.Destroy()
			activated:DisconnectAll()
			hovered:DisconnectAll()
			frame:Destroy()
		end,
	}
	applyTheme()
	return list
end

return table.freeze(ResultListModule)
