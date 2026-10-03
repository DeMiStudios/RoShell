--!strict
--[[
	Modal prompts raised by commands (`ctx:Confirm`, `ctx:Choose`, `ctx:Input`): a card over the dimmed console
	with keyboard and pointer support and an optional auto-cancel countdown. `Ask` yields until answered;
	concurrent prompts queue.
]]

--// Imports
const Motion = require("./Motion")
const ResultList = require("./ResultList")
const Signal = require("../../Shared/Signal")
const Surface = require("./Surface")
const Theme = require("./Theme")
const Types = require("../../Shared/Types")
const Ui = require("./Ui")

--// Types
export type Dialog = {
	--- Shows the prompt and yields until it is answered (nil when cancelled or timed out).
	read Ask: (request: Types.PromptRequest) -> Types.PromptAnswer,
	read IsOpen: () -> boolean,
	--- Keyboard routing from the console.
	read Confirm: () -> (),
	read Cancel: () -> (),
	read Move: (delta: number) -> (),
	read Kind: () -> Types.PromptKind?,
	read SetTheme: (palette: Theme.Palette) -> (),
	read SetMetrics: (metrics: Ui.Metrics) -> (),
	read Destroy: () -> (),
}

type Active = {
	Request: Types.PromptRequest,
	Answered: Types.Signal<Types.PromptAnswer>,
	Done: boolean,
}

--// Constants
const WIDTH = 440
const DEFAULT_TIMEOUT = 60
const MAX_CHOICE_ROWS = 6

--// Dialog
const DialogModule = {}

function DialogModule.new(parent: GuiObject, initialPalette: Theme.Palette, initialMetrics: Ui.Metrics): Dialog
	local palette = initialPalette
	local metrics = initialMetrics
	local active: Active? = nil
	local busy = false
	const released: Types.Signal<()> = Signal.new()

	const backdrop = Ui.Button("DialogBackdrop", parent)
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.BackgroundTransparency = 1
	backdrop.ZIndex = 30
	backdrop.Visible = false

	const surface = Surface.new("Dialog", backdrop, Ui.Radius.L, palette, true)
	surface.SetElevation(2)
	const holder = surface.Holder
	holder.AnchorPoint = Vector2.new(0.5, 0.5)
	holder.Position = UDim2.fromScale(0.5, 0.5)
	const card = surface.Card
	const scale = Instance.new("UIScale")
	scale.Parent = holder

	const title = Ui.Label("Title", card, Ui.Fonts.Bold, metrics.TextLg)
	title.TextTruncate = Enum.TextTruncate.AtEnd
	const message = Ui.Label("Message", card, Ui.Fonts.Sans, metrics.TextMd)
	message.TextWrapped = true
	message.TextYAlignment = Enum.TextYAlignment.Top
	const list = ResultList.new(card, palette, metrics)
	list.SetMaxRows(MAX_CHOICE_ROWS)
	const field = Instance.new("TextBox")
	field.Name = "Field"
	field.BorderSizePixel = 0
	field.ClearTextOnFocus = false
	field.Font = Ui.Fonts.Mono
	field.TextXAlignment = Enum.TextXAlignment.Left
	field.Text = ""
	field.Parent = card
	Ui.Corner(field, Ui.Radius.M)
	Ui.Padding(field, 0, 10)
	const fieldStroke = Ui.Stroke(field, palette.Border)
	const countdown = Ui.Label("Countdown", card, Ui.Fonts.Sans, metrics.TextXs)
	const cancelButton = Ui.Button("Cancel", card)
	cancelButton.Font = Ui.Fonts.Medium
	cancelButton.BackgroundTransparency = 0
	Ui.Corner(cancelButton, Ui.Radius.M)
	const cancelStroke = Ui.Stroke(cancelButton, palette.Border)
	const confirmButton = Ui.Button("Confirm", card)
	confirmButton.Font = Ui.Fonts.Bold
	confirmButton.BackgroundTransparency = 0
	Ui.Corner(confirmButton, Ui.Radius.M)

	const function buttonHeight(): number
		return math.floor(metrics.TextMd * 2.3) + (if metrics.Touch then 10 else 0)
	end

	const function layout()
		const current = active
		if current == nil then
			return
		end
		const request = current.Request
		const width = math.min(math.floor(WIDTH * math.min(1.2, metrics.Scale)), parent.AbsoluteSize.X - 32)
		const inner = width - 40
		local y = 18
		title.TextSize = metrics.TextLg
		title.Position = UDim2.fromOffset(20, y)
		title.Size = UDim2.fromOffset(inner, metrics.TextLg + 4)
		y += metrics.TextLg + 10
		message.TextSize = metrics.TextMd
		const messageHeight = Ui.Measure(request.Message, metrics.TextMd, Ui.Fonts.Sans, inner).Y
		message.Position = UDim2.fromOffset(20, y)
		message.Size = UDim2.fromOffset(inner, messageHeight)
		y += messageHeight + 14
		list.Frame.Visible = request.Kind == "choice"
		field.Visible = request.Kind == "text"
		if request.Kind == "choice" then
			const listHeight = list.DesiredHeight()
			list.Frame.Position = UDim2.fromOffset(10, y)
			list.Frame.Size = UDim2.fromOffset(width - 20, listHeight)
			y += listHeight + 12
		elseif request.Kind == "text" then
			field.TextSize = metrics.Mono
			field.Position = UDim2.fromOffset(20, y)
			field.Size = UDim2.fromOffset(inner, metrics.InputHeight - 4)
			y += metrics.InputHeight + 10
		end
		const height = buttonHeight()
		const confirmWidth = math.max(96, Ui.Measure(confirmButton.Text, metrics.TextMd, Ui.Fonts.Bold).X + 32)
		confirmButton.TextSize = metrics.TextMd
		confirmButton.Size = UDim2.fromOffset(confirmWidth, height)
		confirmButton.Position = UDim2.fromOffset(width - 20 - confirmWidth, y)
		cancelButton.TextSize = metrics.TextMd
		cancelButton.Size = UDim2.fromOffset(88, height)
		cancelButton.Position = UDim2.fromOffset(width - 20 - confirmWidth - 8 - 88, y)
		countdown.TextSize = metrics.TextXs
		countdown.Position = UDim2.fromOffset(20, y)
		countdown.Size = UDim2.fromOffset(inner - confirmWidth - 96, height)
		y += height + 18
		holder.Size = UDim2.fromOffset(width, y)
	end

	const function applyTheme()
		surface.SetTheme(palette)
		backdrop.BackgroundColor3 = palette.Shadow
		title.TextColor3 = palette.Text
		message.TextColor3 = palette.TextSecondary
		field.BackgroundColor3 = palette.Input
		field.TextColor3 = palette.Text
		field.PlaceholderColor3 = palette.TextMuted
		fieldStroke.Color = palette.BorderFocus
		countdown.TextColor3 = palette.TextMuted
		cancelButton.BackgroundColor3 = palette.Hover
		cancelButton.TextColor3 = palette.Text
		cancelStroke.Color = palette.Border
		const current = active
		const destructive = current ~= nil and current.Request.Destructive == true
		confirmButton.BackgroundColor3 = if destructive then palette.Error else palette.Accent
		confirmButton.TextColor3 = palette.TextInverse
		list.SetTheme(palette)
	end

	const function finish(answer: Types.PromptAnswer)
		const current = active
		if current == nil or current.Done then
			return
		end
		current.Done = true
		active = nil
		backdrop.Visible = false
		if field:IsFocused() then
			field:ReleaseFocus()
		end
		current.Answered:Fire(answer)
	end

	const function confirm()
		const current = active
		if current == nil then
			return
		end
		const request = current.Request
		if request.Kind == "confirm" then
			finish("yes")
		elseif request.Kind == "choice" then
			const index = list.GetSelected()
			const choices = request.Choices or {}
			if index and choices[index] then
				finish(choices[index])
			end
		else
			finish(field.Text)
		end
	end

	confirmButton.Activated:Connect(confirm)
	cancelButton.Activated:Connect(function()
		finish(if active and active.Request.Kind == "confirm" then "no" else nil)
	end)
	list.Hovered:Connect(function(index: number)
		list.SetSelected(index)
	end)
	list.Activated:Connect(function(index: number)
		list.SetSelected(index)
		confirm()
	end)
	field.FocusLost:Connect(function(enterPressed: boolean)
		if enterPressed and active and active.Request.Kind == "text" then
			confirm()
		end
	end)

	const function present(current: Active)
		const request = current.Request
		active = current
		title.Text = request.Title or (if request.Kind == "confirm" then "Are you sure?" else "Input needed")
		message.Text = request.Message
		confirmButton.Text = if request.Kind == "confirm" then (if request.Destructive then "Confirm" else "Yes")
			elseif request.Kind == "choice" then "Choose"
			else "Submit"
		cancelButton.Text = if request.Kind == "confirm" then "No" else "Cancel"
		if request.Kind == "choice" then
			const items: { ResultList.Item } = {}
			local selected = 1
			for index, choice in request.Choices or {} do
				table.insert(items, { Label = choice, Icon = tostring(index) })
				if choice == request.Default then
					selected = index
				end
			end
			list.SetItems(items, selected, false)
		elseif request.Kind == "text" then
			field.Text = request.Default or ""
			field.PlaceholderText = request.Placeholder or ""
		end
		applyTheme()
		backdrop.Visible = true
		backdrop.BackgroundTransparency = 1
		layout()
		Motion.Tween(backdrop, 0.15, { BackgroundTransparency = 0.45 })
		scale.Scale = if Motion.Reduced() then 1 else 0.94
		Motion.Tween(scale, 0.2, { Scale = 1 }, Enum.EasingStyle.Back)
		if request.Kind == "text" then
			task.defer(function()
				field:CaptureFocus()
				field.CursorPosition = #field.Text + 1
			end)
		end

		const timeout = request.Timeout or DEFAULT_TIMEOUT
		const deadline = os.clock() + timeout
		task.spawn(function()
			while not current.Done do
				const remaining = math.ceil(deadline - os.clock())
				if remaining <= 0 then
					finish(nil)
					break
				end
				countdown.Text = if remaining <= 30 then `Auto-cancels in {remaining}s` else ""
				task.wait(0.25)
			end
		end)
	end

	return table.freeze({
		Ask = function(request: Types.PromptRequest): Types.PromptAnswer
			while busy do
				released:Wait()
			end
			busy = true
			const current: Active = { Request = request, Answered = Signal.new(), Done = false }
			present(current)
			const answer = current.Answered:Wait()
			busy = false
			released:Fire()
			return answer
		end,
		IsOpen = function(): boolean
			return active ~= nil
		end,
		Confirm = confirm,
		Cancel = function()
			finish(if active and active.Request.Kind == "confirm" then "no" else nil)
		end,
		Move = function(delta: number)
			if active and active.Request.Kind == "choice" then
				list.Move(delta)
			end
		end,
		Kind = function(): Types.PromptKind?
			return if active then active.Request.Kind else nil
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
			finish(nil)
			list.Destroy()
			backdrop:Destroy()
		end,
	})
end

return table.freeze(DialogModule)
