--!strict
--[[
	The panel's two-pane view, used while typing and by the pickers: a list on the left (commands, palette entries)
	and on the right the details of what is highlighted — a signature with the argument being typed, its type and
	description, notes — followed by that argument's candidates. Narrow panels show one side at a time.
]]

--// Imports
const Icons = require("./Icons")
const Model = require("./Model")
const ResultList = require("./ResultList")
const Signal = require("../../Shared/Signal")
const Theme = require("./Theme")
const Types = require("../../Shared/Types")
const Ui = require("./Ui")

--// Types
export type Which = "left" | "right"

export type Assist = {
	read Frame: Frame,
	--- Shows a model. `animate` fades the lists' first rows in (when the panel opens).
	read Set: (model: Model.Assist, animate: boolean?) -> (),
	--- Height the content needs.
	read DesiredHeight: () -> number,
	--- Width to lay out for (the panel's; its absolute size lags a frame behind).
	read SetWidth: (width: number) -> (),
	--- Tallest the content may be (the panel's room); the candidate list shows whole rows within it.
	read SetLimit: (height: number) -> (),
	--- Replaces only the right column's details (the highlight moved).
	read SetDetails: (details: Model.Details?) -> (),
	--- Fires when `DesiredHeight` changes.
	read Resized: Types.Signal<number>,
	--- Moves the highlight of the list the keyboard drives.
	read Move: (delta: number) -> (),
	read Focus: () -> Which,
	read Selected: () -> number?,
	read SetSelected: (which: Which, index: number?) -> (),
	read SetTheme: (palette: Theme.Palette) -> (),
	read SetMetrics: (metrics: Ui.Metrics) -> (),
	read Activated: Types.Signal<Which, number>,
	read Destroy: () -> (),
}

type SectionView = { Heading: TextLabel, Body: TextLabel }

--// Constants
const TWO_COLUMNS = 540
const PAD = 8
const RIGHT_PAD = 16
const MAX_SECTIONS = 4
const MAX_SWATCHES = 8
const MAX_DESCRIPTION_LINES = 3

--// Assist
const AssistModule = {}

function AssistModule.new(parent: Instance, initialPalette: Theme.Palette, initialMetrics: Ui.Metrics): Assist
	local palette = initialPalette
	local metrics = initialMetrics
	local model: Model.Assist = { Focus = "left" }
	local desired = 0
	local width = 0
	local limit = math.huge
	const activated: Types.Signal<Which, number> = Signal.new()
	const resized: Types.Signal<number> = Signal.new()

	const frame = Ui.Frame("Assist", parent)
	frame.Size = UDim2.fromScale(1, 1)

	const leftColumn = Ui.Frame("Left", frame)
	const left = ResultList.new(leftColumn, palette, metrics, "rich")
	left.Frame.Position = UDim2.fromOffset(0, PAD)
	left.SetMaxRows(7)

	const divider = Ui.Frame("Divider", frame)
	divider.BackgroundTransparency = 0.35

	const rightColumn = Ui.Frame("Right", frame)
	rightColumn.ClipsDescendants = true
	const title = Ui.Label("Title", rightColumn, Ui.Fonts.Sans, metrics.TextXl)
	title.RichText = true
	title.TextTruncate = Enum.TextTruncate.AtEnd
	const description = Ui.Label("Description", rightColumn, Ui.Fonts.Sans, metrics.TextMd)
	description.TextWrapped = true
	description.TextYAlignment = Enum.TextYAlignment.Top
	description.TextTruncate = Enum.TextTruncate.AtEnd
	const noticeIcon = Ui.Label("NoticeIcon", rightColumn, Ui.Fonts.Bold, metrics.TextMd)
	noticeIcon.TextXAlignment = Enum.TextXAlignment.Center
	noticeIcon.TextYAlignment = Enum.TextYAlignment.Top
	const notice = Ui.Label("Notice", rightColumn, Ui.Fonts.Medium, metrics.TextSm)
	notice.TextWrapped = true
	notice.TextYAlignment = Enum.TextYAlignment.Top
	const separator = Ui.Frame("Separator", rightColumn)
	separator.BackgroundTransparency = 0.35
	const activeTitle = Ui.Label("Active", rightColumn, Ui.Fonts.Sans, metrics.TextLg)
	activeTitle.RichText = true
	activeTitle.TextTruncate = Enum.TextTruncate.AtEnd
	const activeDescription = Ui.Label("ActiveDescription", rightColumn, Ui.Fonts.Sans, metrics.TextMd)
	activeDescription.TextWrapped = true
	activeDescription.TextYAlignment = Enum.TextYAlignment.Top
	activeDescription.TextTruncate = Enum.TextTruncate.AtEnd
	const sections: { SectionView } = {}
	for index = 1, MAX_SECTIONS do
		const heading = Ui.Label("Heading" .. index, rightColumn, Ui.Fonts.Bold, metrics.TextXs)
		const body = Ui.Label("Body" .. index, rightColumn, Ui.Fonts.Sans, metrics.TextMd)
		body.RichText = true
		body.TextWrapped = true
		body.TextYAlignment = Enum.TextYAlignment.Top
		sections[index] = { Heading = heading, Body = body }
	end
	const hint = Ui.Label("Hint", rightColumn, Ui.Fonts.Sans, metrics.TextMd)
	hint.RichText = true
	hint.TextTruncate = Enum.TextTruncate.AtEnd
	const swatchRow = Ui.Frame("Swatches", rightColumn)
	const swatches: { Frame } = {}
	for index = 1, MAX_SWATCHES do
		const swatch = Ui.Frame("Swatch" .. index, swatchRow)
		swatch.BackgroundTransparency = 0
		Ui.Corner(swatch, 999)
		Ui.Stroke(swatch, Color3.new(0.5, 0.5, 0.5), 0.6)
		swatches[index] = swatch
	end
	const right = ResultList.new(rightColumn, palette, metrics, "compact")
	right.SetMaxRows(8)

	-- Layout ---------------------------------------------------------------------------------------------------
	const function noticeColor(level: Types.Level): Color3
		return if level == "warning" then palette.Warning elseif level == "error" then palette.Error else palette.Info
	end

	--- Lays out the right column at `width` and returns the height of its details (above the candidates).
	const function layoutDetails(columnWidth: number): number
		const details = model.Details
		const inner = columnWidth - RIGHT_PAD * 2
		local y = 14
		const visible = details ~= nil
		title.Visible = visible
		description.Visible = false
		notice.Visible = false
		noticeIcon.Visible = false
		separator.Visible = false
		activeTitle.Visible = false
		activeDescription.Visible = false
		hint.Visible = false
		swatchRow.Visible = false
		for _, view in sections do
			view.Heading.Visible = false
			view.Body.Visible = false
		end
		if details == nil then
			return 0
		end
		const lineHeight = metrics.TextXl + 6
		title.Text = details.Title
		title.TextSize = metrics.TextXl
		title.TextColor3 = palette.Text
		title.Position = UDim2.fromOffset(RIGHT_PAD, y)
		title.Size = UDim2.fromOffset(inner, lineHeight)
		y += lineHeight + 2
		const text = details.Description
		if text and text ~= "" then
			const maximum = math.ceil(metrics.TextMd * 1.25 * MAX_DESCRIPTION_LINES)
			const height = math.min(Ui.Measure(text, metrics.TextMd, Ui.Fonts.Sans, inner).Y, maximum)
			description.Visible = true
			description.Text = text
			description.TextSize = metrics.TextMd
			description.TextColor3 = palette.TextSecondary
			description.Position = UDim2.fromOffset(RIGHT_PAD, y)
			description.Size = UDim2.fromOffset(inner, height)
			y += height + 6
		end
		const current = details.Notice
		if current then
			const iconSize = metrics.TextSm + 4
			const height = Ui.Measure(current.Text, metrics.TextSm, Ui.Fonts.Medium, inner - iconSize - 6).Y
			noticeIcon.Visible = true
			Icons.Apply(noticeIcon, current.Level)
			noticeIcon.TextSize = metrics.TextSm + 2
			noticeIcon.TextColor3 = noticeColor(current.Level)
			noticeIcon.Position = UDim2.fromOffset(RIGHT_PAD, y)
			noticeIcon.Size = UDim2.fromOffset(iconSize, iconSize)
			notice.Visible = true
			notice.Text = current.Text
			notice.TextSize = metrics.TextSm
			notice.TextColor3 = noticeColor(current.Level)
			notice.Position = UDim2.fromOffset(RIGHT_PAD + iconSize + 6, y + 1)
			notice.Size = UDim2.fromOffset(inner - iconSize - 6, height)
			y += math.max(height, iconSize) + 6
		end
		const active = details.Active
		const hasHint = details.HintSlot == true
		const hasMore = active ~= nil or #details.Sections > 0 or details.Swatches ~= nil or hasHint
		if hasMore then
			y += 6
			separator.Visible = true
			separator.BackgroundColor3 = palette.Border
			separator.Position = UDim2.fromOffset(RIGHT_PAD, y)
			separator.Size = UDim2.fromOffset(inner, 1)
			y += 12
		end
		if active then
			const name = `<font color="{Ui.Hex(palette.Accent)}"><b>{Ui.Escape(active.Name)}</b></font>`
			const kind = if active.Type then `<font color="{Ui.Hex(palette.TextSecondary)}">: {Ui.Escape(active.Type)}</font>`
				else ""
			activeTitle.Visible = true
			activeTitle.Text = name .. kind
			activeTitle.TextSize = metrics.TextLg
			activeTitle.TextColor3 = palette.Text
			activeTitle.Position = UDim2.fromOffset(RIGHT_PAD, y)
			activeTitle.Size = UDim2.fromOffset(inner, metrics.TextLg + 4)
			y += metrics.TextLg + 6
			const about = active.Description
			if about and about ~= "" then
				const maximum = math.ceil(metrics.TextMd * 1.25 * MAX_DESCRIPTION_LINES)
				const height = math.min(Ui.Measure(about, metrics.TextMd, Ui.Fonts.Sans, inner).Y, maximum)
				activeDescription.Visible = true
				activeDescription.Text = about
				activeDescription.TextSize = metrics.TextMd
				activeDescription.TextColor3 = palette.TextSecondary
				activeDescription.Position = UDim2.fromOffset(RIGHT_PAD, y)
				activeDescription.Size = UDim2.fromOffset(inner, height)
				y += height + 6
			end
		end
		for index, section in details.Sections do
			const view = sections[index]
			if view == nil then
				break
			end
			y += 4
			const heading = section.Heading
			if heading then
				view.Heading.Visible = true
				view.Heading.Text = heading:upper()
				view.Heading.TextSize = metrics.TextXs
				view.Heading.TextColor3 = palette.TextMuted
				view.Heading.Position = UDim2.fromOffset(RIGHT_PAD, y)
				view.Heading.Size = UDim2.fromOffset(inner, metrics.TextXs + 4)
				y += metrics.TextXs + 6
			end
			const font = if section.Mono then Ui.Fonts.Mono else Ui.Fonts.Sans
			const size = if section.Mono then metrics.Mono else metrics.TextMd
			const height = Ui.Measure(Ui.StripRich(section.Rich), size, font, inner).Y
			view.Body.Visible = true
			view.Body.Text = section.Rich
			view.Body.Font = font
			view.Body.TextSize = size
			view.Body.TextColor3 = palette.TextSecondary
			view.Body.Position = UDim2.fromOffset(RIGHT_PAD, y)
			view.Body.Size = UDim2.fromOffset(inner, height)
			y += height + 6
		end
		if hasHint then
			-- One line, kept while any candidate has a description, so moving the highlight never moves the list.
			const height = metrics.TextMd + 6
			y += 2
			hint.Visible = true
			hint.Text = details.Hint or ""
			hint.TextSize = metrics.TextMd
			hint.TextColor3 = palette.TextSecondary
			hint.Position = UDim2.fromOffset(RIGHT_PAD, y)
			hint.Size = UDim2.fromOffset(inner, height)
			y += height + 4
		end
		const colors = details.Swatches
		if colors then
			const size = 18
			swatchRow.Visible = true
			swatchRow.Position = UDim2.fromOffset(RIGHT_PAD, y + 2)
			swatchRow.Size = UDim2.fromOffset(inner, size)
			for index, swatch in swatches do
				const color = colors[index]
				swatch.Visible = color ~= nil
				if color then
					swatch.BackgroundColor3 = color
					swatch.Size = UDim2.fromOffset(size, size)
					swatch.Position = UDim2.fromOffset((index - 1) * (size + 6), 0)
				end
			end
			y += size + 8
		end
		return y
	end

	const function layout()
		if width <= 0 then
			width = frame.AbsoluteSize.X
		end
		const hasLeft = model.Left ~= nil
		const hasRight = model.Details ~= nil or model.Right ~= nil
		const twoColumns = hasLeft and hasRight and width >= TWO_COLUMNS
		const showLeft = hasLeft and (twoColumns or not hasRight or model.Focus == "left")
		const showRight = hasRight and (twoColumns or not hasLeft or model.Focus == "right")
		leftColumn.Visible = showLeft
		rightColumn.Visible = showRight
		divider.Visible = twoColumns
		local leftWidth = 0
		if showLeft then
			leftWidth = if twoColumns then math.clamp(math.floor(width * 0.4), 220, 300) else width
			leftColumn.Position = UDim2.fromOffset(0, 0)
			leftColumn.Size = UDim2.new(0, leftWidth, 1, 0)
			left.Frame.Size = UDim2.new(1, 0, 1, -PAD * 2)
		end
		local leftHeight = 0
		if showLeft then
			leftHeight = left.DesiredHeight() + PAD * 2
		end
		local rightHeight = 0
		if showRight then
			const x = if twoColumns then leftWidth + 1 else 0
			const rightWidth = width - x
			rightColumn.Position = UDim2.fromOffset(x, 0)
			rightColumn.Size = UDim2.new(0, rightWidth, 1, 0)
			const detailsHeight = layoutDetails(rightWidth)
			if model.Right then
				const top = if detailsHeight > 0 then detailsHeight + 2 else PAD
				right.Frame.Visible = true
				right.Frame.Position = UDim2.fromOffset(0, top)
				-- Whole rows only: as many as fit under the details within the limit (at least two).
				const rowHeight = right.RowHeight()
				const fitting = math.max(2, math.floor((limit - top - PAD) / rowHeight))
				const listHeight = math.min(right.DesiredHeight(), fitting * rowHeight)
				right.Frame.Size = UDim2.new(1, 0, 0, listHeight)
				rightHeight = top + listHeight + PAD
			else
				right.Frame.Visible = false
				rightHeight = detailsHeight + 8
			end
		end
		if twoColumns then
			divider.BackgroundColor3 = palette.Border
			divider.Position = UDim2.fromOffset(leftWidth, 12)
			divider.Size = UDim2.new(0, 1, 1, -24)
		end
		-- While an argument is typed the left column is context: it gets no more room than the right side needs
		-- (at least two rows), so the panel stays small.
		if twoColumns and model.Focus == "right" then
			leftHeight = math.min(leftHeight, math.max(rightHeight, left.RowHeight() * 2 + PAD * 2))
		end
		if showLeft then
			const rows = math.max(1, math.floor((math.min(leftHeight, limit) - PAD * 2) / left.RowHeight()))
			left.Frame.Size = UDim2.new(1, 0, 0, math.min(left.DesiredHeight(), rows * left.RowHeight()))
		end
		const previous = desired
		desired = math.min(math.max(leftHeight, rightHeight), limit)
		if desired ~= previous then
			resized:Fire(desired)
		end
	end

	left.Activated:Connect(function(index: number)
		activated:Fire("left", index)
	end)
	right.Activated:Connect(function(index: number)
		activated:Fire("right", index)
	end)

	const function focusedList(): ResultList.ResultList
		return if model.Focus == "left" then left else right
	end

	const assist: Assist = {
		Frame = frame,
		Set = function(next: Model.Assist, animate: boolean?)
			model = next
			const leftModel = next.Left
			left.SetItems(
				if leftModel then leftModel.Items else {},
				if leftModel then leftModel.Selected else nil,
				animate
			)
			const rightModel = next.Right
			right.SetItems(
				if rightModel then rightModel.Items else {},
				if rightModel then rightModel.Selected else nil,
				animate
			)
			layout()
		end,
		DesiredHeight = function(): number
			return desired
		end,
		SetWidth = function(value: number)
			if value ~= width then
				width = value
				layout()
			end
		end,
		SetLimit = function(value: number)
			if value ~= limit then
				limit = value
				layout()
			end
		end,
		SetDetails = function(details: Model.Details?)
			model = { Left = model.Left, Details = details, Right = model.Right, Focus = model.Focus }
			layout()
		end,
		Resized = resized,
		Move = function(delta: number)
			focusedList().Move(delta)
		end,
		Focus = function(): Which
			return model.Focus
		end,
		Selected = function(): number?
			return focusedList().GetSelected()
		end,
		SetSelected = function(which: Which, index: number?)
			if which == "left" then
				left.SetSelected(index)
			else
				right.SetSelected(index)
			end
		end,
		SetTheme = function(next: Theme.Palette)
			palette = next
			left.SetTheme(next)
			right.SetTheme(next)
			layout()
		end,
		SetMetrics = function(next: Ui.Metrics)
			metrics = next
			left.SetMetrics(next)
			right.SetMetrics(next)
			layout()
		end,
		Activated = activated,
		Destroy = function()
			left.Destroy()
			right.Destroy()
			activated:DisconnectAll()
			resized:DisconnectAll()
			frame:Destroy()
		end,
	}
	return assist
end

return table.freeze(AssistModule)
