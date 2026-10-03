--!strict
--[[
	Prompts raised by commands (`ctx:Confirm`, `ctx:Choose`, `ctx:Input`), shown in the command bar's panel with
	keyboard and pointer support and an optional auto-cancel countdown. `Ask` yields until answered; concurrent
	prompts queue.
]]

--// Imports
const Model = require("./Model")
const ResultList = require("./ResultList")
const Signal = require("../../Shared/Signal")
const Theme = require("./Theme")
const Types = require("../../Shared/Types")
const Ui = require("./Ui")

--// Types
export type Dialog = {
	read Frame: Frame,
	--- Shows the prompt and yields until it is answered (nil when cancelled or timed out).
	read Ask: (request: Types.PromptRequest) -> Types.PromptAnswer,
	read IsOpen: () -> boolean,
	--- Height the open prompt needs.
	read DesiredHeight: () -> number,
	--- Width to lay out for (the panel's).
	read SetWidth: (width: number) -> (),
	--- Keyboard routing from the console.
	read Confirm: () -> (),
	read Cancel: () -> (),
	read Move: (delta: number) -> (),
	read Kind: () -> Types.PromptKind?,
	read SetTheme: (palette: Theme.Palette) -> (),
	read SetMetrics: (metrics: Ui.Metrics) -> (),
	--- A prompt became visible / was answered.
	read Presented: Types.Signal<()>,
	read Finished: Types.Signal<()>,
	read Destroy: () -> (),
}

type Active = {
	Request: Types.PromptRequest,
	Answered: Types.Signal<Types.PromptAnswer>,
	Done: boolean,
}

--// Constants
const DEFAULT_TIMEOUT = 60
const MAX_CHOICE_ROWS = 6
const PAD = 18

--// Dialog
const DialogModule = {}

function DialogModule.new(parent: GuiObject, initialPalette: Theme.Palette, initialMetrics: Ui.Metrics): Dialog
	local palette = initialPalette
	local metrics = initialMetrics
	local active: Active? = nil
	local busy = false
	local desired = 0
	local width = 0
	const released: Types.Signal<()> = Signal.new()
	const presented: Types.Signal<()> = Signal.new()
	const finished: Types.Signal<()> = Signal.new()

	const frame = Ui.Frame("Dialog", parent)
	frame.Size = UDim2.fromScale(1, 1)
	frame.Visible = false

	const title = Ui.Label("Title", frame, Ui.Fonts.Bold, metrics.TextLg)
	title.TextTruncate = Enum.TextTruncate.AtEnd
	const message = Ui.Label("Message", frame, Ui.Fonts.Sans, metrics.TextMd)
	message.TextWrapped = true
	message.TextYAlignment = Enum.TextYAlignment.Top
	const list = ResultList.new(frame, palette, metrics, "compact")
	list.SetMaxRows(MAX_CHOICE_ROWS)
	const field = Instance.new("TextBox")
	field.Name = "Field"
	field.BorderSizePixel = 0
	field.ClearTextOnFocus = false
	field.Font = Ui.Fonts.Medium
	field.TextXAlignment = Enum.TextXAlignment.Left
	field.Text = ""
	field.Parent = frame
	Ui.Corner(field, Ui.Radius.M + 2)
	Ui.Padding(field, 0, 12)
	const fieldStroke = Ui.Stroke(field, palette.Border)
	const countdown = Ui.Label("Countdown", frame, Ui.Fonts.Sans, metrics.TextXs)
	const cancelButton = Ui.Button("Cancel", frame)
	cancelButton.Font = Ui.Fonts.Medium
	cancelButton.BackgroundTransparency = 0
	Ui.Corner(cancelButton, 999)
	const cancelStroke = Ui.Stroke(cancelButton, palette.Border)
	const confirmButton = Ui.Button("Confirm", frame)
	confirmButton.Font = Ui.Fonts.Bold
	confirmButton.BackgroundTransparency = 0
	Ui.Corner(confirmButton, 999)

	const function buttonHeight(): number
		return math.floor(metrics.TextMd * 2.3) + (if metrics.Touch then 10 else 0)
	end

	const function layout()
		const current = active
		if current == nil then
			desired = 0
			return
		end
		const request = current.Request
		if width <= 0 then
			width = parent.AbsoluteSize.X
		end
		const inner = width - PAD * 2
		local y = PAD
		title.TextSize = metrics.TextLg
		title.Position = UDim2.fromOffset(PAD, y)
		title.Size = UDim2.fromOffset(inner, metrics.TextLg + 4)
		y += metrics.TextLg + 8
		message.TextSize = metrics.TextMd
		const messageHeight = Ui.Measure(request.Message, metrics.TextMd, Ui.Fonts.Sans, inner).Y
		message.Position = UDim2.fromOffset(PAD, y)
		message.Size = UDim2.fromOffset(inner, messageHeight)
		y += messageHeight + 12
		list.Frame.Visible = request.Kind == "choice"
		field.Visible = request.Kind == "text"
		if request.Kind == "choice" then
			const listHeight = list.DesiredHeight()
			list.Frame.Position = UDim2.fromOffset(PAD - 6, y)
			list.Frame.Size = UDim2.fromOffset(inner + 12, listHeight)
			y += listHeight + 10
		elseif request.Kind == "text" then
			field.TextSize = metrics.TextMd
			field.Position = UDim2.fromOffset(PAD, y)
			field.Size = UDim2.fromOffset(inner, metrics.InputHeight)
			y += metrics.InputHeight + 12
		end
		const height = buttonHeight()
		const confirmWidth = math.max(96, Ui.Measure(confirmButton.Text, metrics.TextMd, Ui.Fonts.Bold).X + 36)
		const cancelWidth = math.max(88, Ui.Measure(cancelButton.Text, metrics.TextMd, Ui.Fonts.Medium).X + 32)
		confirmButton.TextSize = metrics.TextMd
		confirmButton.Size = UDim2.fromOffset(confirmWidth, height)
		confirmButton.Position = UDim2.fromOffset(width - PAD - confirmWidth, y)
		cancelButton.TextSize = metrics.TextMd
		cancelButton.Size = UDim2.fromOffset(cancelWidth, height)
		cancelButton.Position = UDim2.fromOffset(width - PAD - confirmWidth - 8 - cancelWidth, y)
		countdown.TextSize = metrics.TextXs
		countdown.Position = UDim2.fromOffset(PAD, y)
		countdown.Size = UDim2.fromOffset(math.max(0, inner - confirmWidth - cancelWidth - 16), height)
		y += height + PAD
		desired = y
	end

	const function applyTheme()
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
		frame.Visible = false
		if field:IsFocused() then
			field:ReleaseFocus()
		end
		desired = 0
		finished:Fire()
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
			const items: { Model.Item } = {}
			local selected = 1
			for index, choice in request.Choices or {} do
				table.insert(items, { Label = choice, Icon = tostring(index), Tint = "accent" })
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
		frame.Visible = true
		layout()
		presented:Fire()
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
		Frame = frame,
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
		DesiredHeight = function(): number
			return desired
		end,
		SetWidth = function(value: number)
			if value ~= width then
				width = value
				layout()
			end
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
		Presented = presented,
		Finished = finished,
		Destroy = function()
			finish(nil)
			list.Destroy()
			frame:Destroy()
		end,
	})
end

return table.freeze(DialogModule)
