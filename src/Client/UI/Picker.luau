--!strict
--[[
	A centered fuzzy picker over a dimmed backdrop. Powers the command palette (Ctrl+K) and reverse history
	search (Ctrl+R). Each entry decides what choosing it does.
]]

--// Imports
const Fuzzy = require("../../Shared/Fuzzy")
const Motion = require("./Motion")
const ResultList = require("./ResultList")
const Surface = require("./Surface")
const Theme = require("./Theme")
const Ui = require("./Ui")

--// Types
export type Entry = {
	Item: ResultList.Item,
	--- Text the query is matched against (label plus keywords).
	Search: string,
	--- Shown in the footer while the entry is selected.
	Description: string?,
	--- `alternate` is true for Shift+Enter (e.g. run instead of insert).
	Choose: (alternate: boolean) -> (),
}

export type OpenOptions = {
	Title: string,
	Placeholder: string,
	Entries: { Entry },
	--- Footer hint when nothing is selected.
	Hint: string?,
	--- Initial query.
	Query: string?,
}

export type Picker = {
	read Holder: Frame,
	read TextBox: TextBox,
	read Open: (options: OpenOptions) -> (),
	read Close: () -> (),
	read IsOpen: () -> boolean,
	read Move: (delta: number) -> (),
	read Choose: (alternate: boolean) -> (),
	read SetTheme: (palette: Theme.Palette) -> (),
	read SetMetrics: (metrics: Ui.Metrics) -> (),
	read Destroy: () -> (),
}

--// Constants
const WIDTH = 620
const MAX_ROWS = 9
const LIMIT = 200

--// Helpers

const function searchText(entry: Entry): string
	return entry.Search
end

--// Picker
const PickerModule = {}

function PickerModule.new(parent: Instance, initialPalette: Theme.Palette, initialMetrics: Ui.Metrics): Picker
	local palette = initialPalette
	local metrics = initialMetrics
	local open = false
	local entries: { Entry } = {}
	local visible: { Entry } = {}
	local hint = ""

	const backdrop = Ui.Button("PickerBackdrop", parent)
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.BackgroundTransparency = 1
	backdrop.Visible = false
	backdrop.ZIndex = 40
	backdrop.Modal = true

	const surface = Surface.new("Picker", backdrop, Ui.Radius.XL - 2, palette, true)
	surface.SetElevation(1.8)
	const holder = surface.Holder
	holder.AnchorPoint = Vector2.new(0.5, 0)
	holder.Position = UDim2.fromScale(0.5, 0.16)
	const card = surface.Card
	card.ClipsDescendants = true
	const scale = Instance.new("UIScale")
	scale.Parent = holder

	const title = Ui.Label("Title", card, Ui.Fonts.Medium, metrics.TextXs)
	const searchIcon = Ui.Label("SearchIcon", card, Ui.Fonts.Bold, metrics.TextLg)
	searchIcon.Text = "›"
	searchIcon.TextXAlignment = Enum.TextXAlignment.Center
	const box = Instance.new("TextBox")
	box.Name = "Search"
	box.BackgroundTransparency = 1
	box.BorderSizePixel = 0
	box.ClearTextOnFocus = false
	box.Font = Ui.Fonts.Sans
	box.TextXAlignment = Enum.TextXAlignment.Left
	box.Text = ""
	box.Parent = card
	const escHint = Ui.Label("Esc", card, Ui.Fonts.Medium, metrics.TextXs)
	escHint.Text = "esc"
	escHint.TextXAlignment = Enum.TextXAlignment.Center
	escHint.BackgroundTransparency = 0
	Ui.Corner(escHint, 5)
	const divider = Ui.Frame("Divider", card)
	divider.BackgroundTransparency = 0
	const list = ResultList.new(card, palette, metrics)
	list.SetMaxRows(MAX_ROWS)
	const empty = Ui.Label("Empty", card, Ui.Fonts.Sans, metrics.TextSm)
	empty.Text = "No matches"
	empty.TextXAlignment = Enum.TextXAlignment.Center
	const footerDivider = Ui.Frame("FooterDivider", card)
	footerDivider.BackgroundTransparency = 0
	const footer = Ui.Label("Footer", card, Ui.Fonts.Sans, metrics.TextXs)
	footer.TextTruncate = Enum.TextTruncate.AtEnd

	const function searchHeight(): number
		return metrics.TextLg + 26
	end

	const function layout()
		const titleHeight = metrics.TextXs + 14
		const listHeight = math.max(list.DesiredHeight(), metrics.SuggestionRow * 2)
		const footerHeight = metrics.TextXs + 16
		const width = math.floor(WIDTH * math.min(1.2, metrics.Scale))
		holder.Size = UDim2.fromOffset(width, titleHeight + searchHeight() + listHeight + footerHeight + 10)
		title.Position = UDim2.fromOffset(18, 4)
		title.Size = UDim2.new(1, -36, 0, titleHeight)
		title.TextSize = metrics.TextXs
		searchIcon.Position = UDim2.fromOffset(12, titleHeight)
		searchIcon.Size = UDim2.fromOffset(28, searchHeight())
		searchIcon.TextSize = metrics.TextLg
		box.Position = UDim2.fromOffset(44, titleHeight)
		box.Size = UDim2.new(1, -100, 0, searchHeight())
		box.TextSize = metrics.TextLg
		escHint.TextSize = metrics.TextXs
		escHint.Size = UDim2.fromOffset(34, metrics.TextXs + 8)
		escHint.Position = UDim2.new(1, -48, 0, titleHeight + (searchHeight() - (metrics.TextXs + 8)) // 2)
		divider.Position = UDim2.fromOffset(0, titleHeight + searchHeight())
		divider.Size = UDim2.new(1, 0, 0, 1)
		list.Frame.Position = UDim2.fromOffset(0, titleHeight + searchHeight() + 5)
		list.Frame.Size = UDim2.new(1, 0, 0, listHeight)
		empty.Position = list.Frame.Position
		empty.Size = list.Frame.Size
		empty.TextSize = metrics.TextSm
		footerDivider.Position = UDim2.fromOffset(0, titleHeight + searchHeight() + listHeight + 8)
		footerDivider.Size = UDim2.new(1, 0, 0, 1)
		footer.Position = UDim2.fromOffset(18, titleHeight + searchHeight() + listHeight + 9)
		footer.Size = UDim2.new(1, -36, 0, footerHeight)
		footer.TextSize = metrics.TextXs
	end

	const function updateFooter()
		const index = list.GetSelected()
		const entry = if index then visible[index] else nil
		footer.Text = if entry and entry.Description then entry.Description else hint
	end

	const function refresh()
		const query = box.Text
		const items: { ResultList.Item } = {}
		visible = {}
		if query == "" then
			for index, entry in entries do
				if index > LIMIT then
					break
				end
				table.insert(visible, entry)
				const item = table.clone(entry.Item)
				item.Ranges = nil
				table.insert(items, item)
			end
		else
			for _, scored in Fuzzy.Filter(query, entries, searchText, LIMIT) do
				const entry = scored.Item
				table.insert(visible, entry)
				const item = table.clone(entry.Item)
				const labelLength = #item.Label
				const ranges: { Ui.Span } = {}
				for _, range in scored.Ranges do
					if range.End - 1 <= labelLength then
						table.insert(ranges, range)
					end
				end
				item.Ranges = ranges
				table.insert(items, item)
			end
		end
		list.SetItems(items, if #items > 0 then 1 else nil, false)
		empty.Visible = #items == 0
		layout()
		updateFooter()
	end

	const function applyTheme()
		surface.SetTheme(palette)
		backdrop.BackgroundColor3 = palette.Shadow
		title.TextColor3 = palette.TextMuted
		searchIcon.TextColor3 = palette.Accent
		box.TextColor3 = palette.Text
		box.PlaceholderColor3 = palette.TextMuted
		escHint.TextColor3 = palette.TextMuted
		escHint.BackgroundColor3 = palette.Hover
		divider.BackgroundColor3 = palette.Border
		footerDivider.BackgroundColor3 = palette.Border
		footer.TextColor3 = palette.TextSecondary
		empty.TextColor3 = palette.TextMuted
		list.SetTheme(palette)
	end

	local picker: Picker

	const function choose(alternate: boolean)
		const index = list.GetSelected()
		const entry = if index then visible[index] else nil
		if entry then
			picker.Close()
			entry.Choose(alternate)
		end
	end

	box:GetPropertyChangedSignal("Text"):Connect(function()
		if open then
			refresh()
		end
	end)
	box.FocusLost:Connect(function(enterPressed: boolean)
		if open and enterPressed then
			const UserInputService = game:GetService("UserInputService")
			choose(
				UserInputService:IsKeyDown(Enum.KeyCode.LeftShift)
					or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)
			)
		end
	end)
	list.Hovered:Connect(function(index: number)
		list.SetSelected(index)
		updateFooter()
	end)
	list.Activated:Connect(function(index: number)
		list.SetSelected(index)
		choose(false)
	end)
	backdrop.Activated:Connect(function()
		const mouse = game:GetService("UserInputService"):GetMouseLocation()
		const inset = game:GetService("GuiService"):GetGuiInset()
		const point = mouse - inset
		const position = holder.AbsolutePosition
		const size = holder.AbsoluteSize
		if point.X < position.X
			or point.Y < position.Y
			or point.X > position.X + size.X
			or point.Y > position.Y + size.Y then
			picker.Close()
		end
	end)

	picker = {
		Holder = holder,
		TextBox = box,
		Open = function(options: OpenOptions)
			entries = options.Entries
			hint = options.Hint or "Enter choose · Shift+Enter run · Esc close"
			title.Text = options.Title:upper()
			box.PlaceholderText = options.Placeholder
			open = true
			box.Text = options.Query or ""
			refresh()
			backdrop.Visible = true
			backdrop.BackgroundTransparency = 1
			Motion.Tween(backdrop, 0.16, { BackgroundTransparency = if palette.Dark then 0.55 else 0.7 })
			scale.Scale = if Motion.Reduced() then 1 else 0.96
			Motion.Tween(scale, 0.18, { Scale = 1 })
			task.defer(function()
				if open then
					box:CaptureFocus()
				end
			end)
		end,
		Close = function()
			if not open then
				return
			end
			open = false
			backdrop.Visible = false
			if box:IsFocused() then
				box:ReleaseFocus()
			end
		end,
		IsOpen = function(): boolean
			return open
		end,
		Move = function(delta: number)
			list.Move(delta)
			updateFooter()
		end,
		Choose = choose,
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
			backdrop:Destroy()
		end,
	}
	applyTheme()
	layout()
	return picker
end

return table.freeze(PickerModule)
