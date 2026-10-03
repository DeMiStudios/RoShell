--!strict
--[[
	The output log. Virtualized: entries are measured once per width, laid out with cumulative offsets, and only
	the rows inside the viewport (plus overscan) are bound to pooled instances. Sticks to the bottom while new
	output arrives unless the player scrolled up.
]]

--// Imports
const Format = require("./Format")
const Motion = require("./Motion")
const Signal = require("../../Shared/Signal")
const Theme = require("./Theme")
const Types = require("../../Shared/Types")
const Ui = require("./Ui")

--// Types
export type LogView = {
	read Frame: ScrollingFrame,
	read Add: (entry: Format.Entry) -> (),
	--- Replaces the progress entry with the same id. Returns false when there is none.
	read UpdateProgress: (entry: Format.Entry) -> boolean,
	read Clear: () -> (),
	read Export: () -> string,
	read Count: () -> number,
	read SetTheme: (palette: Theme.Palette) -> (),
	read SetMetrics: (metrics: Ui.Metrics) -> (),
	read SetLimit: (limit: number) -> (),
	read SetTimestamps: (enabled: boolean) -> (),
	read ScrollToBottom: (animated: boolean) -> (),
	--- Fires when a row is clicked (the console offers to copy it).
	read Activated: Types.Signal<Format.Entry>,
	read Destroy: () -> (),
}

type Item = {
	Entry: Format.Entry,
	Time: number,
	Height: number,
	Y: number,
	Margin: number,
	Fresh: boolean,
	MeasuredWidth: number,
}

type Row = {
	Button: TextButton,
	Accent: Frame,
	Icon: TextLabel,
	Text: TextLabel,
	Time: TextLabel,
	Swatch: Frame,
	Track: Frame,
	Fill: Frame,
	Item: Item?,
	Hovered: boolean,
	Fade: Tween?,
}

--// Constants
const OVERSCAN = 240
const STICK_THRESHOLD = 8
const TIME_WIDTH = 64
const PROGRESS_HEIGHT = 4

--// LogView
const LogViewModule = {}

function LogViewModule.new(parent: Instance, initialPalette: Theme.Palette, initialMetrics: Ui.Metrics): LogView
	local palette = initialPalette
	local metrics = initialMetrics
	local limit = 1000
	local timestamps = false
	local items: { Item } = {}
	local totalHeight = 0
	local layoutWidth = -1
	local renderQueued = false
	local layoutDirty = true
	local stick = true
	const rows: { Row } = {}
	const activated: Types.Signal<Format.Entry> = Signal.new()
	const connections: { RBXScriptConnection } = {}

	const frame = Instance.new("ScrollingFrame")
	frame.Name = "Log"
	frame.BackgroundTransparency = 1
	frame.BorderSizePixel = 0
	frame.ScrollingDirection = Enum.ScrollingDirection.Y
	frame.ScrollBarThickness = 4
	frame.ScrollBarImageTransparency = 0.4
	frame.VerticalScrollBarInset = Enum.ScrollBarInset.None
	frame.ElasticBehavior = Enum.ElasticBehavior.Never
	frame.CanvasSize = UDim2.new()
	frame.ClipsDescendants = true
	frame.Parent = parent

	const function levelColor(level: Types.Level): Color3
		if level == "success" then
			return palette.Success
		elseif level == "error" then
			return palette.Error
		elseif level == "warning" then
			return palette.Warning
		elseif level == "info" then
			return palette.Info
		elseif level == "echo" then
			return palette.Accent
		end
		return palette.TextMuted
	end

	const function textColor(level: Types.Level): Color3
		if level == "error" then
			return palette.Error
		elseif level == "warning" then
			return palette.Warning
		elseif level == "muted" then
			return palette.TextMuted
		end
		return palette.Text
	end

	const function iconWidth(): number
		return math.ceil(metrics.MonoWidth * 2) + 4
	end

	const function textWidth(): number
		const extra = if timestamps then TIME_WIDTH else 0
		return math.max(40, frame.AbsoluteSize.X - metrics.Pad * 2 - iconWidth() - extra - 6)
	end

	const function measure(item: Item, width: number)
		const entry = item.Entry
		const size = Ui.Measure(entry.Plain, metrics.Mono, Ui.Fonts.Mono, if entry.Wrap then width else nil)
		local height = math.max(metrics.LineHeight, size.Y) + metrics.RowPadding * 2
		if entry.Kind == "progress" then
			height += PROGRESS_HEIGHT + metrics.RowPadding * 2
		end
		item.Height = math.ceil(height)
		item.MeasuredWidth = size.X
	end

	const function relayout()
		const width = textWidth()
		const remeasure = width ~= layoutWidth
		layoutWidth = width
		local y = metrics.Pad / 2
		for index, item in items do
			if remeasure or item.Height == 0 then
				measure(item, width)
			end
			item.Margin = if item.Entry.Kind == "echo" and index > 1 then metrics.Gap else 0
			y += item.Margin
			item.Y = y
			y += item.Height
		end
		totalHeight = y + metrics.Pad / 2
		frame.CanvasSize = UDim2.fromOffset(0, totalHeight)
		layoutDirty = false
	end

	const function maxScroll(): number
		return math.max(0, totalHeight - frame.AbsoluteSize.Y)
	end

	const function makeRow(): Row
		const button = Ui.Button("Row", frame)
		button.BackgroundColor3 = palette.Hover
		button.Visible = false
		const accent = Ui.Frame("Accent", button)
		accent.BackgroundTransparency = 0.15
		accent.Size = UDim2.new(0, 2, 1, -4)
		accent.Position = UDim2.fromOffset(2, 2)
		Ui.Corner(accent, 1)
		const icon = Ui.Label("Icon", button, Ui.Fonts.Mono, metrics.Mono)
		icon.TextXAlignment = Enum.TextXAlignment.Center
		icon.TextYAlignment = Enum.TextYAlignment.Top
		const text = Ui.Label("Text", button, Ui.Fonts.Mono, metrics.Mono)
		text.RichText = true
		text.TextYAlignment = Enum.TextYAlignment.Top
		text.ClipsDescendants = true
		const time = Ui.Label("Time", button, Ui.Fonts.Mono, metrics.TextXs)
		time.TextXAlignment = Enum.TextXAlignment.Right
		time.TextYAlignment = Enum.TextYAlignment.Top
		time.AnchorPoint = Vector2.new(1, 0)
		const swatch = Ui.Frame("Swatch", button)
		swatch.BackgroundTransparency = 0
		Ui.Corner(swatch, 4)
		const track = Ui.Frame("Track", button)
		track.BackgroundTransparency = 0
		Ui.Corner(track, 2)
		const fill = Ui.Frame("Fill", track)
		fill.BackgroundTransparency = 0
		fill.Size = UDim2.fromScale(0, 1)
		Ui.Corner(fill, 2)
		const row: Row = {
			Button = button,
			Accent = accent,
			Icon = icon,
			Text = text,
			Time = time,
			Swatch = swatch,
			Track = track,
			Fill = fill,
			Item = nil,
			Hovered = false,
			Fade = nil,
		}
		button.MouseEnter:Connect(function()
			row.Hovered = true
			button.BackgroundTransparency = 0.6
			time.Visible = true
		end)
		button.MouseLeave:Connect(function()
			row.Hovered = false
			button.BackgroundTransparency = 1
			time.Visible = timestamps
		end)
		button.Activated:Connect(function()
			const item = row.Item
			if item then
				activated:Fire(item.Entry)
			end
		end)
		return row
	end

	const function bind(row: Row, item: Item)
		const entry = item.Entry
		const button = row.Button
		const changed = row.Item ~= item
		row.Item = item
		button.Visible = true
		button.Position = UDim2.fromOffset(0, item.Y)
		button.Size = UDim2.new(1, 0, 0, item.Height)
		button.BackgroundColor3 = palette.Hover
		button.BackgroundTransparency = if row.Hovered then 0.6 else 1

		const level = entry.Level
		const left = metrics.Pad
		const iconSize = iconWidth()
		const showAccent = level == "error" or level == "warning" or level == "success"
		row.Accent.Visible = showAccent
		row.Accent.BackgroundColor3 = levelColor(level)

		row.Icon.Text = Ui.Icon(if entry.Kind == "echo" then "echo" else level)
		row.Icon.TextColor3 = levelColor(level)
		row.Icon.TextSize = metrics.Mono
		row.Icon.Position = UDim2.fromOffset(left, metrics.RowPadding)
		row.Icon.Size = UDim2.fromOffset(iconSize, metrics.LineHeight)

		local textLeft = left + iconSize
		row.Swatch.Visible = entry.Kind == "swatch"
		if entry.Kind == "swatch" then
			const swatchSize = metrics.LineHeight - 2
			row.Swatch.BackgroundColor3 = entry.Color or palette.Text
			row.Swatch.Position = UDim2.fromOffset(textLeft, metrics.RowPadding + 1)
			row.Swatch.Size = UDim2.fromOffset(swatchSize, swatchSize)
			textLeft += swatchSize + metrics.Gap
		end

		const text = row.Text
		text.TextSize = metrics.Mono
		text.TextWrapped = entry.Wrap
		text.Text = entry.Rich
		text.TextColor3 = textColor(level)
		text.Position = UDim2.fromOffset(textLeft, metrics.RowPadding)
		const width = layoutWidth - (textLeft - left - iconSize)
		text.Size = UDim2.fromOffset(
			if entry.Wrap then width else math.max(width, item.MeasuredWidth + 4),
			item.Height - metrics.RowPadding * 2
		)

		row.Track.Visible = entry.Kind == "progress"
		if entry.Kind == "progress" then
			row.Track.BackgroundColor3 = palette.Border
			row.Fill.BackgroundColor3 = palette.Accent
			row.Track.Position = UDim2.new(0, textLeft, 1, -(PROGRESS_HEIGHT + metrics.RowPadding * 2))
			row.Track.Size = UDim2.fromOffset(math.min(width, 320), PROGRESS_HEIGHT)
			const fraction = entry.Fraction or 0.35
			if changed then
				row.Fill.Size = UDim2.fromScale(fraction, 1)
			else
				Motion.Tween(row.Fill, 0.25, { Size = UDim2.fromScale(fraction, 1) })
			end
		end

		row.Time.Text = os.date("%H:%M:%S", math.floor(item.Time))
		row.Time.TextSize = metrics.TextXs
		row.Time.TextColor3 = palette.TextMuted
		row.Time.Position = UDim2.new(1, -metrics.Pad - 6, 0, metrics.RowPadding + 1)
		row.Time.Size = UDim2.fromOffset(TIME_WIDTH, metrics.LineHeight)
		row.Time.Visible = timestamps or row.Hovered

		if changed then
			const fade = row.Fade
			if fade then
				fade:Cancel()
				row.Fade = nil
			end
			text.TextTransparency = 0
			row.Icon.TextTransparency = 0
		end
		if item.Fresh then
			item.Fresh = false
			if not Motion.Reduced() then
				text.TextTransparency = 1
				row.Icon.TextTransparency = 1
				row.Fade = Motion.Tween(text, 0.22, { TextTransparency = 0 })
				Motion.Tween(row.Icon, 0.22, { TextTransparency = 0 })
			end
		end
	end

	const function render()
		renderQueued = false
		if layoutDirty or textWidth() ~= layoutWidth then
			relayout()
		end
		const top = frame.CanvasPosition.Y - OVERSCAN
		const bottom = frame.CanvasPosition.Y + frame.AbsoluteSize.Y + OVERSCAN
		-- Binary search for the first visible item.
		local low, high = 1, #items
		while low < high do
			const middle = (low + high) // 2
			const item = items[middle]
			if item.Y + item.Height < top then
				low = middle + 1
			else
				high = middle
			end
		end
		local used = 0
		for index = low, #items do
			const item = items[index]
			if item.Y > bottom then
				break
			end
			used += 1
			local row = rows[used]
			if row == nil then
				row = makeRow()
				rows[used] = row
			end
			bind(row, item)
		end
		for index = used + 1, #rows do
			const row = rows[index]
			row.Button.Visible = false
			row.Item = nil
		end
	end

	const function queueRender()
		if renderQueued then
			return
		end
		renderQueued = true
		task.defer(function()
			const wasStuck = stick
			render()
			if wasStuck then
				frame.CanvasPosition = Vector2.new(0, maxScroll())
				render()
			end
		end)
	end

	const function scrollToBottom(animated: boolean)
		stick = true
		if layoutDirty then
			relayout()
		end
		const target = Vector2.new(0, maxScroll())
		if animated and not Motion.Reduced() then
			Motion.Tween(frame, 0.18, { CanvasPosition = target })
		else
			frame.CanvasPosition = target
		end
	end

	table.insert(
		connections,
		frame:GetPropertyChangedSignal("CanvasPosition"):Connect(function()
			stick = frame.CanvasPosition.Y >= maxScroll() - STICK_THRESHOLD
			if not renderQueued then
				render()
			end
		end)
	)
	table.insert(
		connections,
		frame:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
			layoutDirty = true
			queueRender()
		end)
	)

	const function trim()
		const excess = #items - limit
		if excess > 0 then
			table.move(items, excess + 1, #items, 1)
			for index = #items, #items - excess + 1, -1 do
				items[index] = nil
			end
		end
	end

	const view: LogView = {
		Frame = frame,
		Add = function(entry: Format.Entry)
			table.insert(items, {
				Entry = entry,
				Time = os.time(),
				Height = 0,
				Y = 0,
				Margin = 0,
				Fresh = true,
				MeasuredWidth = 0,
			})
			trim()
			layoutDirty = true
			queueRender()
		end,
		UpdateProgress = function(entry: Format.Entry): boolean
			for index = #items, math.max(1, #items - 200), -1 do
				const item = items[index]
				if item.Entry.Kind == "progress" and item.Entry.ProgressId == entry.ProgressId then
					item.Entry = entry
					item.Height = 0
					layoutDirty = true
					queueRender()
					return true
				end
			end
			return false
		end,
		Clear = function()
			items = {}
			layoutDirty = true
			stick = true
			frame.CanvasPosition = Vector2.zero
			queueRender()
		end,
		Export = function(): string
			const list: { { Entry: Format.Entry, Time: number } } = {}
			for _, item in items do
				table.insert(list, { Entry = item.Entry, Time = item.Time })
			end
			return Format.Export(list)
		end,
		Count = function(): number
			return #items
		end,
		SetTheme = function(next: Theme.Palette)
			palette = next
			frame.ScrollBarImageColor3 = palette.TextMuted
			queueRender()
		end,
		SetMetrics = function(next: Ui.Metrics)
			metrics = next
			layoutWidth = -1
			layoutDirty = true
			queueRender()
		end,
		SetLimit = function(next: number)
			limit = math.max(10, next)
			trim()
			layoutDirty = true
			queueRender()
		end,
		SetTimestamps = function(enabled: boolean)
			timestamps = enabled
			layoutWidth = -1
			layoutDirty = true
			queueRender()
		end,
		ScrollToBottom = scrollToBottom,
		Activated = activated,
		Destroy = function()
			for _, connection in connections do
				connection:Disconnect()
			end
			activated:DisconnectAll()
			frame:Destroy()
		end,
	}
	view.SetTheme(palette)
	return view
end

return table.freeze(LogViewModule)
