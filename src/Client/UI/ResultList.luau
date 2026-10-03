--!strict
--[[
	A virtualized, keyboard/mouse/touch selectable list with fuzzy-match highlighting and one accent-tinted highlight
	that springs between rows. Two row styles: `rich` (icon, title and a description line — commands, palette
	entries) and `compact` (icon, label and a detail on the right — argument values).
]]

--// Imports
const Icons = require("./Icons")
const Model = require("./Model")
const Motion = require("./Motion")
const Signal = require("../../Shared/Signal")
const Theme = require("./Theme")
const Types = require("../../Shared/Types")
const Ui = require("./Ui")

--// Types
export type Style = "rich" | "compact"

export type ResultList = {
	read Frame: Frame,
	--- Replaces the items. `animate` fades the first rows in.
	read SetItems: (items: { Model.Item }, selected: number?, animate: boolean?) -> (),
	read SetSelected: (index: number?) -> (),
	read GetSelected: () -> number?,
	read Move: (delta: number) -> (),
	read Count: () -> number,
	--- Height needed to show `min(count, maxRows)` rows.
	read DesiredHeight: () -> number,
	read RowHeight: () -> number,
	read SetMaxRows: (rows: number) -> (),
	read SetTheme: (palette: Theme.Palette) -> (),
	read SetMetrics: (metrics: Ui.Metrics) -> (),
	--- Row clicked/tapped.
	read Activated: Types.Signal<number>,
	--- Row hovered (the console moves the selection to it).
	read Hovered: Types.Signal<number>,
	read Destroy: () -> (),
}

type Row = {
	Button: TextButton,
	Icon: TextLabel,
	Chip: Frame,
	Dots: { Frame },
	Title: TextLabel,
	Subtitle: TextLabel,
	Detail: TextLabel,
	Index: number,
}

--// Constants
const STAGGER = 0.014
const STAGGER_ROWS = 6
const SIDE = 6

--// ResultList
const ResultListModule = {}

function ResultListModule.new(parent: Instance, initialPalette: Theme.Palette, initialMetrics: Ui.Metrics, style: Style): ResultList
	local palette = initialPalette
	local metrics = initialMetrics
	local items: { Model.Item } = {}
	local selected: number? = nil
	local maxRows = 7
	const rows: { Row } = {}
	const activated: Types.Signal<number> = Signal.new()
	const hovered: Types.Signal<number> = Signal.new()
	const rich = style == "rich"

	const frame = Ui.Frame("List", parent)
	frame.ClipsDescendants = true

	const scroll = Instance.new("ScrollingFrame")
	scroll.Name = "Scroll"
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.Size = UDim2.fromScale(1, 1)
	scroll.ScrollBarThickness = 3
	scroll.ScrollBarImageTransparency = 0.5
	scroll.ScrollingDirection = Enum.ScrollingDirection.Y
	scroll.ElasticBehavior = Enum.ElasticBehavior.Never
	scroll.CanvasSize = UDim2.new()
	scroll.Parent = frame

	const highlight = Ui.Frame("Highlight", scroll)
	highlight.BackgroundTransparency = 1 - Theme.SelectionTint
	highlight.Visible = false
	Ui.Corner(highlight, Ui.Radius.Row)

	const highlightSpring = Motion.Spring(0, 15, 0.9, function(y: number)
		highlight.Position = UDim2.fromOffset(SIDE, y)
	end)

	const function rowHeight(): number
		return if rich then metrics.RowRich else metrics.RowCompact
	end

	const function tintColor(token: string?): Color3
		if token == nil then
			return palette.TextSecondary
		elseif token == "command" then
			return palette.Syntax.Command
		elseif token == "flag" then
			return palette.Syntax.Flag
		elseif token == "operator" then
			return palette.Syntax.Operator
		elseif token == "variable" then
			return palette.Syntax.Variable
		elseif token == "accent" then
			return palette.Accent
		elseif token == "muted" then
			return palette.TextMuted
		elseif token == "success" then
			return palette.Success
		elseif token == "warning" then
			return palette.Warning
		elseif token == "error" then
			return palette.Error
		elseif token == "info" then
			return palette.Info
		end
		return Theme.TypeToken(palette.Types, token)
	end

	const function makeRow(): Row
		const button = Ui.Button("Row", scroll)
		button.ZIndex = 2
		const icon = Ui.Label("Icon", button, Ui.Fonts.Bold, metrics.IconSize)
		icon.TextXAlignment = Enum.TextXAlignment.Center
		icon.AnchorPoint = Vector2.new(0, 0.5)
		-- Theme previews: a tile in the theme's window color with dots in its accent and text colors.
		const chip = Ui.Frame("Chip", button)
		chip.BackgroundTransparency = 0
		chip.AnchorPoint = Vector2.new(0, 0.5)
		chip.Visible = false
		Ui.Corner(chip, if rich then 9 else 999)
		Ui.Stroke(chip, Color3.new(0.5, 0.5, 0.5), 0.6)
		const dots: { Frame } = {}
		for index = 1, 3 do
			const dot = Ui.Frame("Dot" .. index, chip)
			dot.BackgroundTransparency = 0
			dot.AnchorPoint = Vector2.new(0.5, 0.5)
			Ui.Corner(dot, 999)
			dots[index] = dot
		end
		const title = Ui.Label("Title", button, if rich then Ui.Fonts.Bold else Ui.Fonts.Medium, metrics.TextMd)
		title.RichText = true
		title.TextTruncate = Enum.TextTruncate.AtEnd
		const subtitle = Ui.Label("Subtitle", button, Ui.Fonts.Sans, metrics.TextSm)
		subtitle.TextTruncate = Enum.TextTruncate.AtEnd
		subtitle.Visible = rich
		const detail = Ui.Label("Detail", button, Ui.Fonts.Sans, metrics.TextSm)
		detail.TextXAlignment = Enum.TextXAlignment.Right
		detail.TextTruncate = Enum.TextTruncate.AtEnd
		detail.AnchorPoint = Vector2.new(1, 0)
		const row: Row = {
			Button = button,
			Icon = icon,
			Chip = chip,
			Dots = dots,
			Title = title,
			Subtitle = subtitle,
			Detail = detail,
			Index = 0,
		}
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

	const function bind(row: Row, index: number, item: Model.Item)
		const height = rowHeight()
		row.Index = index
		const button = row.Button
		button.Visible = true
		button.Position = UDim2.fromOffset(SIDE, (index - 1) * height)
		button.Size = UDim2.new(1, -SIDE * 2, 0, height)
		const isSelected = index == selected

		-- Icon (or theme tile).
		const iconBox = if rich then metrics.IconBox else metrics.IconSize + 6
		const iconLeft = 8
		const swatches = item.Swatches
		row.Chip.Visible = swatches ~= nil
		row.Icon.Visible = swatches == nil
		if swatches then
			const size = if rich then iconBox else math.floor(iconBox * 0.7)
			row.Chip.Size = UDim2.fromOffset(size, size)
			row.Chip.Position = UDim2.new(0, iconLeft + (iconBox - size) // 2, 0.5, 0)
			row.Chip.BackgroundColor3 = swatches[1]
			for dotIndex, dot in row.Dots do
				const color = swatches[dotIndex + 1]
				dot.Visible = rich and color ~= nil
				if color then
					const dotSize = math.max(5, math.floor(size * 0.2))
					dot.BackgroundColor3 = color
					dot.Size = UDim2.fromOffset(dotSize, dotSize)
					dot.Position = UDim2.fromScale(0.25 + (dotIndex - 1) * 0.25, 0.5)
				end
			end
		else
			Icons.Apply(row.Icon, item.Icon)
			row.Icon.TextSize = metrics.IconSize
			row.Icon.Size = UDim2.fromOffset(iconBox, iconBox)
			row.Icon.Position = UDim2.new(0, iconLeft, 0.5, 0)
			row.Icon.TextColor3 = if rich then (if isSelected then palette.Text else palette.TextSecondary)
				else tintColor(item.Tint)
		end

		-- Title and match highlights.
		const accent = Ui.Hex(palette.Accent)
		local text = Ui.HighlightRanges(item.Label, item.Ranges, `<font color="{accent}">`, "</font>")
		if item.Deprecated then
			text = `<s>{text}</s>`
		end
		row.Title.Text = text
		row.Title.TextColor3 = if item.Deprecated then palette.TextMuted else palette.Text
		const textLeft = iconLeft + iconBox + (if rich then 12 else 8)
		const detailText = item.Detail or ""
		const detailWidth = if detailText == "" then 0
			else math.min(
				Ui.Measure(detailText, metrics.TextSm, Ui.Fonts.Sans).X + 4,
				math.floor(frame.AbsoluteSize.X * 0.4)
			)
		row.Detail.Text = detailText
		row.Detail.TextSize = metrics.TextSm
		row.Detail.TextColor3 = if isSelected then palette.TextSecondary else palette.TextMuted
		row.Detail.Position = UDim2.new(1, -10, 0, 0)
		row.Detail.Size = UDim2.new(0, detailWidth, 1, 0)
		const textWidth = UDim2.new(1, -(textLeft + detailWidth + 16), 0, 0)
		if rich then
			const titleSize = metrics.TextMd + 1
			const subtitleSize = metrics.TextSm
			const block = titleSize + 3 + subtitleSize
			const top = math.floor((height - block) / 2)
			row.Title.TextSize = titleSize
			row.Title.Position = UDim2.fromOffset(textLeft, top)
			row.Title.Size = textWidth + UDim2.fromOffset(0, titleSize + 2)
			row.Subtitle.Text = item.Subtitle or ""
			row.Subtitle.TextSize = subtitleSize
			row.Subtitle.TextColor3 = if isSelected then palette.TextSecondary else palette.TextMuted
			row.Subtitle.Position = UDim2.fromOffset(textLeft, top + titleSize + 3)
			row.Subtitle.Size = textWidth + UDim2.fromOffset(0, subtitleSize + 2)
			row.Detail.Size = UDim2.fromOffset(detailWidth, titleSize + 2)
			row.Detail.Position = UDim2.new(1, -10, 0, top)
		else
			row.Title.TextSize = metrics.TextMd
			row.Title.Position = UDim2.fromOffset(textLeft, 0)
			row.Title.Size = textWidth + UDim2.fromScale(0, 1)
		end
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
		if viewHeight < height then
			-- Not laid out yet: the size signal brings the row into view later.
			return
		end
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
		const wasVisible = highlight.Visible
		highlight.Visible = true
		highlight.Size = UDim2.new(1, -SIDE * 2, 0, rowHeight())
		const y = (index - 1) * rowHeight()
		if snap or not wasVisible then
			highlightSpring.Snap(y)
		else
			highlightSpring.SetTarget(y)
		end
	end

	const function applyTheme()
		highlight.BackgroundColor3 = palette.Accent
		scroll.ScrollBarImageColor3 = palette.TextMuted
	end

	scroll:GetPropertyChangedSignal("CanvasPosition"):Connect(render)
	frame:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		render()
		if selected then
			ensureVisible(selected)
		end
	end)

	const list: ResultList = {
		Frame = frame,
		SetItems = function(nextItems: { Model.Item }, nextSelected: number?, animate: boolean?)
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
						const delay = (index - 1) * STAGGER
						row.Title.TextTransparency = 1
						row.Subtitle.TextTransparency = 1
						row.Icon.TextTransparency = 1
						Motion.Tween(row.Title, 0.18, { TextTransparency = 0 }, nil, nil, delay)
						Motion.Tween(row.Subtitle, 0.18, { TextTransparency = 0 }, nil, nil, delay)
						Motion.Tween(row.Icon, 0.18, { TextTransparency = 0 }, nil, nil, delay)
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
		RowHeight = rowHeight,
		SetMaxRows = function(count: number)
			maxRows = count
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
