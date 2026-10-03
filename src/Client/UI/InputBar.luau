--!strict
--[[
	The command bar's contents: a prompt icon (also the drag handle), the input — a transparent `TextBox` over a
	RichText overlay that carries the syntax colors and the ghost completion — and on the right a key hint
	(`Tab to autocomplete`), the history button and, on touch screens, a run button.

	The caret and selection are drawn by hand (the native ones disappear with the transparent text) and the text
	scrolls horizontally to keep the caret in view. Text changes are detected by comparing against the last known
	text instead of suppression flags, because property signals are deferred.
]]

--// Imports
const Icons = require("./Icons")
const InputText = require("./InputText")
const Lexer = require("../../Shared/Lexer")
const Motion = require("./Motion")
const Signal = require("../../Shared/Signal")
const Theme = require("./Theme")
const Types = require("../../Shared/Types")
const Ui = require("./Ui")

--// Types
export type InputState = "idle" | "valid" | "invalid" | "running"

--- `search` turns the prompt into a magnifying glass (the bar is filtering a picker).
export type InputMode = "command" | "search"

export type InputFont = "sans" | "mono"

--- What the right side of the bar says: key caps followed by text (`Tab` `to autocomplete`), or a message.
export type Hint = { Keys: { string }?, Text: string?, Level: Types.Level? }

export type InputBar = {
	read Frame: Frame,
	read TextBox: TextBox,
	--- Dragging this moves the bar.
	read Handle: GuiButton,
	read GetText: () -> string,
	--- Reads the TextBox right now (its change signal is deferred) and returns the current text.
	read Sync: () -> string,
	--- Caret byte position (1-based; #text + 1 at the end).
	read GetCursor: () -> number,
	--- Selection as a byte span, or nil.
	read GetSelection: () -> (number?, number?),
	read SetText: (text: string, cursor: number?) -> (),
	read SetCursor: (cursor: number) -> (),
	--- Sets the highlighted RichText rendering of the current text (plus ghost text).
	read SetRich: (rich: string) -> (),
	read SetState: (state: InputState) -> (),
	read SetMode: (mode: InputMode) -> (),
	read SetFont: (font: InputFont) -> (),
	read SetHint: (hint: Hint?) -> (),
	read SetPlaceholder: (text: string) -> (),
	--- History button: `active` while the log is open, `badge` when output arrived unseen.
	read SetLog: (active: boolean, badge: boolean) -> (),
	read Focus: () -> (),
	read Release: () -> (),
	read IsFocused: () -> boolean,
	--- Screen X of a byte position.
	read ScreenX: (position: number) -> number,
	read Shake: () -> (),
	read SetTheme: (palette: Theme.Palette) -> (),
	read SetMetrics: (metrics: Ui.Metrics) -> (),
	--- User edits: new text and caret.
	read Changed: Types.Signal<string, number>,
	read CursorMoved: Types.Signal<number>,
	--- The run button (touch).
	read Submitted: Types.Signal<()>,
	read StopRequested: Types.Signal<()>,
	read FocusLost: Types.Signal<boolean>,
	--- The focus look changed (the bar's border follows it).
	read FocusChanged: Types.Signal<boolean>,
	read LogToggled: Types.Signal<()>,
	--- Text pasted with two or more non-empty lines (breaks normalized to "\n"), offered as a script.
	read MultilinePaste: Types.Signal<string>,
	read Destroy: () -> (),
}

type KeyCap = { Frame: Frame, Label: TextLabel, Stroke: UIStroke }

--// Constants
const SPINNER = { "◐", "◓", "◑", "◒" }
const CARET_MARGIN = 24
const MAX_KEYS = 3

--// InputBar
const InputBarModule = {}

function InputBarModule.new(parent: Instance, initialPalette: Theme.Palette, initialMetrics: Ui.Metrics): InputBar
	local palette = initialPalette
	local metrics = initialMetrics
	local knownText = ""
	local knownCursor = 1
	local state: InputState = "idle"
	local mode: InputMode = "command"
	local fontKind: InputFont = "sans"
	local hint: Hint? = nil
	local logActive = false
	local logBadge = false
	local scrollX = 0
	local focused = false
	local blinkClock = 0
	local spinnerIndex = 1
	const touch = metrics.Touch
	const connections: { RBXScriptConnection } = {}
	const changed: Types.Signal<string, number> = Signal.new()
	const cursorMoved: Types.Signal<number> = Signal.new()
	const submitted: Types.Signal<()> = Signal.new()
	const stopRequested: Types.Signal<()> = Signal.new()
	const focusLost: Types.Signal<boolean> = Signal.new()
	const focusChanged: Types.Signal<boolean> = Signal.new()
	const logToggled: Types.Signal<()> = Signal.new()
	const multilinePaste: Types.Signal<string> = Signal.new()

	-- Instances -----------------------------------------------------------------------------------------------
	const bar = Ui.Frame("Input", parent)
	bar.Size = UDim2.fromScale(1, 1)

	const handle = Ui.Button("Handle", bar)
	handle.AnchorPoint = Vector2.new(0, 0.5)
	const prompt = Ui.Label("Prompt", handle, Ui.Fonts.Bold, metrics.IconSize)
	prompt.Size = UDim2.fromScale(1, 1)
	prompt.TextXAlignment = Enum.TextXAlignment.Center

	const viewport = Ui.Frame("Viewport", bar)
	viewport.ClipsDescendants = true
	viewport.AnchorPoint = Vector2.new(0, 0.5)

	const scroller = Ui.Frame("Scroller", viewport)

	const selection = Ui.Frame("Selection", scroller)
	selection.BackgroundTransparency = 0.7
	selection.Visible = false
	selection.AnchorPoint = Vector2.new(0, 0.5)
	Ui.Corner(selection, 3)

	const overlay = Ui.Label("Overlay", scroller, Ui.Fonts.Medium, metrics.BarText)
	overlay.RichText = true
	overlay.Size = UDim2.fromScale(1, 1)

	const placeholder = Ui.Label("Placeholder", viewport, Ui.Fonts.Medium, metrics.BarText)
	placeholder.Size = UDim2.fromScale(1, 1)
	placeholder.TextTruncate = Enum.TextTruncate.AtEnd

	const box = Instance.new("TextBox")
	box.Name = "TextBox"
	box.BackgroundTransparency = 1
	box.BorderSizePixel = 0
	box.ClearTextOnFocus = false
	box.MultiLine = false
	box.TextEditable = true
	box.Text = ""
	box.PlaceholderText = ""
	box.Font = Ui.Fonts.Medium
	box.TextTransparency = 1
	box.TextXAlignment = Enum.TextXAlignment.Left
	box.Size = UDim2.fromScale(1, 1)
	box.ZIndex = 2
	box.Parent = scroller

	const caret = Ui.Frame("Caret", scroller)
	caret.BackgroundTransparency = 0
	caret.ZIndex = 3
	caret.Visible = false
	caret.AnchorPoint = Vector2.new(0, 0.5)
	Ui.Corner(caret, 1)

	-- Right side: hint, history button, run button.
	const hintFrame = Ui.Frame("Hint", bar)
	hintFrame.AnchorPoint = Vector2.new(1, 0.5)
	const keyCaps: { KeyCap } = {}
	for index = 1, MAX_KEYS do
		const frame = Ui.Frame("Key" .. index, hintFrame)
		frame.BackgroundTransparency = 0.85
		frame.AnchorPoint = Vector2.new(0, 0.5)
		Ui.Corner(frame, Ui.Radius.Key)
		const stroke = Ui.Stroke(frame, palette.Accent, 0.45)
		const label = Ui.Label("Label", frame, Ui.Fonts.Medium, metrics.TextXs)
		label.Size = UDim2.fromScale(1, 1)
		label.TextXAlignment = Enum.TextXAlignment.Center
		keyCaps[index] = { Frame = frame, Label = label, Stroke = stroke }
	end
	const hintText = Ui.Label("Text", hintFrame, Ui.Fonts.Sans, metrics.TextSm)
	hintText.AnchorPoint = Vector2.new(0, 0.5)
	hintText.TextTruncate = Enum.TextTruncate.AtEnd

	const logButton = Ui.Button("Log", bar)
	logButton.AnchorPoint = Vector2.new(1, 0.5)
	logButton.BackgroundTransparency = 1
	Ui.Corner(logButton, 999)
	const logIcon = Ui.Label("Icon", logButton, Ui.Fonts.Bold, metrics.IconSize)
	logIcon.Size = UDim2.fromScale(1, 1)
	logIcon.TextXAlignment = Enum.TextXAlignment.Center
	Icons.Apply(logIcon, "log")
	const logDot = Ui.Frame("Badge", logButton)
	logDot.BackgroundTransparency = 0
	logDot.AnchorPoint = Vector2.new(0.5, 0.5)
	logDot.Position = UDim2.fromScale(0.78, 0.24)
	logDot.Visible = false
	Ui.Corner(logDot, 999)

	const run = Ui.Button("Run", bar)
	run.AnchorPoint = Vector2.new(1, 0.5)
	run.BackgroundTransparency = 0
	run.Visible = touch
	Ui.Corner(run, 999)
	const runIcon = Ui.Label("Icon", run, Ui.Fonts.Bold, metrics.IconSize)
	runIcon.Size = UDim2.fromScale(1, 1)
	runIcon.TextXAlignment = Enum.TextXAlignment.Center
	Icons.Apply(runIcon, "run")

	-- Caret position animates with a fast spring so jumps (accepting a completion) glide.
	const caretSpring = Motion.Spring(0, 22, 1, function(x: number)
		caret.Position = UDim2.new(0, math.floor(x + 0.5), 0.5, 0)
	end)

	-- Measurement ------------------------------------------------------------------------------------------
	const function font(): Enum.Font
		return if fontKind == "mono" then Ui.Fonts.Mono else Ui.Fonts.Medium
	end

	const function textSize(): number
		return if fontKind == "mono" then metrics.Mono else metrics.BarText
	end

	const function lineHeight(): number
		return if fontKind == "mono" then metrics.LineHeight else math.ceil(metrics.BarText * 1.25)
	end

	const function widthOf(text: string): number
		return if fontKind == "mono" then Ui.MonoTextWidth(text, metrics) else Ui.TextWidth(text, textSize(), font())
	end

	const function textX(position: number): number
		return widthOf(knownText:sub(1, position - 1))
	end

	-- Layout -----------------------------------------------------------------------------------------------
	const function hintWidth(): number
		const current = hint
		if current == nil then
			return 0
		end
		local width = 0
		const keys = current.Keys or {}
		for index = 1, math.min(#keys, MAX_KEYS) do
			width += Ui.Measure(keys[index], metrics.TextSm, Ui.Fonts.Medium).X + 14 + 4
		end
		const text = current.Text
		if text and text ~= "" then
			width += Ui.Measure(text, metrics.TextSm, Ui.Fonts.Sans).X + (if #keys > 0 then 4 else 0)
		end
		return math.min(width, math.floor(bar.AbsoluteSize.X * 0.42))
	end

	const function layoutHint(width: number)
		const current = hint
		const keys = if current then current.Keys or {} else {}
		local x = 0
		const capHeight = metrics.TextSm + 9
		for index, cap in keyCaps do
			const key = keys[index]
			cap.Frame.Visible = key ~= nil
			if key then
				const capWidth = Ui.Measure(key, metrics.TextSm, Ui.Fonts.Medium).X + 14
				cap.Label.Text = key
				cap.Label.TextSize = metrics.TextSm
				cap.Frame.Size = UDim2.fromOffset(capWidth, capHeight)
				cap.Frame.Position = UDim2.new(0, x, 0.5, 0)
				x += capWidth + 4
			end
		end
		const text = if current then current.Text or "" else ""
		hintText.Text = text
		hintText.TextSize = metrics.TextSm
		hintText.Position = UDim2.new(0, x + (if #keys > 0 then 2 else 0), 0.5, 0)
		hintText.Size = UDim2.new(0, math.max(0, width - x), 1, 0)
		hintFrame.Size = UDim2.new(0, width, 1, 0)
	end

	const function layout()
		const height = metrics.BarHeight
		const side = math.floor(height * 0.3)
		const iconZone = metrics.IconSize + 14
		handle.Size = UDim2.fromOffset(iconZone, height)
		handle.Position = UDim2.new(0, side - 6, 0.5, 0)
		prompt.TextSize = metrics.IconSize + 2
		const buttonSize = height - 16
		local right = side - 6
		run.Visible = touch
		if touch then
			run.Size = UDim2.fromOffset(buttonSize, buttonSize)
			run.Position = UDim2.new(1, -right, 0.5, 0)
			runIcon.TextSize = metrics.IconSize
			right += buttonSize + 6
		end
		logButton.Size = UDim2.fromOffset(buttonSize, buttonSize)
		logButton.Position = UDim2.new(1, -right, 0.5, 0)
		logIcon.TextSize = metrics.IconSize - 1
		logDot.Size = UDim2.fromOffset(7, 7)
		right += buttonSize + 8
		const width = if touch then 0 else hintWidth()
		hintFrame.Visible = width > 0
		hintFrame.Position = UDim2.new(1, -right, 0.5, 0)
		layoutHint(width)
		if width > 0 then
			right += width + 12
		end
		const left = side - 6 + iconZone + 4
		viewport.Position = UDim2.new(0, left, 0.5, 0)
		viewport.Size = UDim2.new(1, -(left + right), 0, lineHeight() + 6)
		const size = textSize()
		const face = font()
		overlay.TextSize = size
		overlay.Font = face
		placeholder.TextSize = size
		placeholder.Font = face
		box.TextSize = size
		box.Font = face
		caret.Size = UDim2.fromOffset(2, lineHeight())
	end

	const function scrollIntoView(snap: boolean)
		const viewWidth = viewport.AbsoluteSize.X
		const caretX = textX(knownCursor)
		const fullWidth = widthOf(knownText)
		if caretX - scrollX > viewWidth - CARET_MARGIN then
			scrollX = caretX - viewWidth + CARET_MARGIN
		elseif caretX - scrollX < CARET_MARGIN then
			scrollX = math.max(0, caretX - CARET_MARGIN)
		end
		scrollX = math.max(0, math.min(scrollX, math.max(0, fullWidth + CARET_MARGIN - viewWidth)))
		scroller.Size = UDim2.new(0, math.max(viewWidth, fullWidth + viewWidth), 1, 0)
		scroller.Position = UDim2.fromOffset(-scrollX, 0)
		if snap then
			caretSpring.Snap(caretX)
		else
			caretSpring.SetTarget(caretX)
		end
		blinkClock = 0
	end

	const function drawSelection()
		const start = box.SelectionStart
		const cursor = box.CursorPosition
		if not focused or start < 1 or cursor < 1 or start == cursor then
			selection.Visible = false
			return
		end
		const from = math.min(start, cursor)
		const to = math.max(start, cursor)
		const x1 = textX(from)
		const x2 = textX(to)
		selection.Visible = true
		selection.Position = UDim2.new(0, x1, 0.5, 0)
		selection.Size = UDim2.fromOffset(math.max(2, x2 - x1), lineHeight())
	end

	-- Appearance -----------------------------------------------------------------------------------------------
	const function hintColor(): Color3
		const level = if hint then hint.Level else nil
		if level == "error" then
			return palette.Error
		elseif level == "warning" then
			return palette.Warning
		elseif level == "success" then
			return palette.Success
		end
		return palette.TextMuted
	end

	const function applyState()
		local promptColor = palette.TextSecondary
		if state == "valid" then
			promptColor = palette.Accent
		elseif state == "invalid" then
			promptColor = palette.Error
		elseif state == "running" then
			promptColor = palette.Warning
		end
		if mode == "search" then
			promptColor = palette.Accent
		end
		if state == "running" and mode == "command" then
			Icons.Clear(prompt)
			prompt.Font = Ui.Fonts.Bold
			prompt.Text = SPINNER[spinnerIndex]
		else
			Icons.Apply(prompt, if mode == "search" then "search" else "prompt")
		end
		Icons.Apply(runIcon, if state == "running" then "stop" else "run")
		Motion.Tween(prompt, 0.15, { TextColor3 = promptColor })
		Motion.Tween(run, 0.15, {
			BackgroundColor3 = if state == "running" then palette.Error
				elseif state == "valid" then palette.Accent
				else palette.Hover,
		})
		runIcon.TextColor3 = if state == "running" or state == "valid" then palette.TextInverse else palette.TextMuted
	end

	const function applyLog()
		logIcon.TextColor3 = if logActive then palette.Accent else palette.TextMuted
		logButton.BackgroundColor3 = palette.Accent
		logButton.BackgroundTransparency = if logActive then 1 - Theme.SelectionTint else 1
		logDot.BackgroundColor3 = palette.Accent
		logDot.Visible = logBadge and not logActive
	end

	const function applyTheme()
		selection.BackgroundColor3 = palette.Accent
		overlay.TextColor3 = palette.Text
		placeholder.TextColor3 = palette.TextMuted
		caret.BackgroundColor3 = palette.Accent
		for _, cap in keyCaps do
			cap.Frame.BackgroundColor3 = palette.Accent
			cap.Stroke.Color = palette.Accent
			cap.Label.TextColor3 = palette.Accent
		end
		hintText.TextColor3 = hintColor()
		applyLog()
		applyState()
	end

	--- Applies a focus change once, whether it comes from an event or is noticed on a frame: capturing focus again
	--- right after Enter released it can leave the box focused without a Focused event.
	const function setFocused(isFocused: boolean)
		if isFocused == focused then
			return
		end
		focused = isFocused
		caret.Visible = isFocused
		if isFocused then
			scrollIntoView(true)
		else
			selection.Visible = false
		end
		focusChanged:Fire(isFocused)
	end

	const function syncFromBox(): boolean
		const cleaned = InputText.Clean(box.Text, box.CursorPosition, knownText)
		if cleaned.Kind == "script" then
			-- A multi-line paste: keep the previous text and offer the paste as a script.
			box.Text = knownText
			box.CursorPosition = knownCursor
			multilinePaste:Fire(cleaned.Text)
			return false
		end
		const text = cleaned.Text
		if text ~= box.Text then
			-- Tabs and stray line breaks (see InputText) never stay in the box.
			box.Text = text
			box.CursorPosition = cleaned.Cursor
		end
		if text == knownText then
			return false
		end
		knownText = text
		knownCursor = if box.CursorPosition > 0 then box.CursorPosition else #text + 1
		placeholder.Visible = text == ""
		return true
	end

	-- Events ---------------------------------------------------------------------------------------------------
	table.insert(
		connections,
		box:GetPropertyChangedSignal("Text"):Connect(function()
			if syncFromBox() then
				scrollIntoView(false)
				drawSelection()
				changed:Fire(knownText, knownCursor)
			end
		end)
	)
	table.insert(
		connections,
		box:GetPropertyChangedSignal("CursorPosition"):Connect(function()
			const cursor = box.CursorPosition
			if cursor < 1 or cursor == knownCursor or box.Text ~= knownText then
				return
			end
			knownCursor = cursor
			scrollIntoView(false)
			drawSelection()
			cursorMoved:Fire(cursor)
		end)
	)
	table.insert(connections, box:GetPropertyChangedSignal("SelectionStart"):Connect(drawSelection))
	table.insert(
		connections,
		box.Focused:Connect(function()
			setFocused(true)
		end)
	)
	table.insert(
		connections,
		box.FocusLost:Connect(function(enterPressed: boolean)
			setFocused(false)
			focusLost:Fire(enterPressed)
		end)
	)
	table.insert(
		connections,
		viewport:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
			scrollIntoView(true)
		end)
	)
	table.insert(
		connections,
		bar:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
			layout()
		end)
	)
	table.insert(
		connections,
		run.Activated:Connect(function()
			if state == "running" then
				stopRequested:Fire()
			else
				submitted:Fire()
			end
		end)
	)
	table.insert(
		connections,
		logButton.Activated:Connect(function()
			logToggled:Fire()
		end)
	)
	Ui.Hover(logButton, function(hovered: boolean)
		if not logActive then
			logIcon.TextColor3 = if hovered then palette.Text else palette.TextMuted
		end
	end)
	-- Focus look, caret blink and the running spinner.
	table.insert(
		connections,
		game:GetService("RunService").RenderStepped:Connect(
			function(dt: number)
				-- The engine's focus state wins over the events (see setFocused).
				const engineFocused = box:IsFocused()
				if engineFocused ~= focused then
					setFocused(engineFocused)
				end
				if focused then
					blinkClock += dt
					-- Solid for half a second after any movement, then a soft sine pulse.
					const alpha = if blinkClock < 0.5 or Motion.Reduced() then 0
						else 0.5 - 0.5 * math.cos((blinkClock - 0.5) * math.pi * 2)
					caret.BackgroundTransparency = alpha
				end
				if state == "running" and mode == "command" then
					const index = math.floor(os.clock() * 8) % #SPINNER + 1
					if index ~= spinnerIndex then
						spinnerIndex = index
						prompt.Text = SPINNER[index]
					end
				end
			end
		)
	)

	const input: InputBar = {
		Frame = bar,
		TextBox = box,
		Handle = handle,
		GetText = function(): string
			return knownText
		end,
		GetCursor = function(): number
			return knownCursor
		end,
		Sync = function(): string
			if syncFromBox() then
				scrollIntoView(false)
				drawSelection()
				changed:Fire(knownText, knownCursor)
			end
			return knownText
		end,
		GetSelection = function(): (number?, number?)
			const start = box.SelectionStart
			const cursor = box.CursorPosition
			if start < 1 or cursor < 1 or start == cursor then
				return nil, nil
			end
			return math.min(start, cursor), math.max(start, cursor)
		end,
		SetText = function(value: string, cursor: number?)
			-- The box holds one line. Text from code (history, completions) that has line breaks or tabs is rewritten
			-- as the equivalent line, so it is never mistaken for a multi-line paste.
			const text = Lexer.ToLine(value)
			const position = math.clamp(if text == value then cursor or #text + 1 else #text + 1, 1, #text + 1)
			knownText = text
			knownCursor = position
			box.Text = text
			box.CursorPosition = position
			box.SelectionStart = -1
			placeholder.Visible = text == ""
			scrollIntoView(false)
			drawSelection()
		end,
		SetCursor = function(cursor: number)
			const position = math.clamp(cursor, 1, #knownText + 1)
			knownCursor = position
			box.CursorPosition = position
			box.SelectionStart = -1
			scrollIntoView(false)
			drawSelection()
		end,
		SetRich = function(rich: string)
			overlay.Text = rich
		end,
		SetState = function(next: InputState)
			if next == state then
				return
			end
			state = next
			applyState()
		end,
		SetMode = function(next: InputMode)
			if next == mode then
				return
			end
			mode = next
			applyState()
		end,
		SetFont = function(next: InputFont)
			if next == fontKind then
				return
			end
			fontKind = next
			layout()
			scrollIntoView(true)
			drawSelection()
		end,
		SetHint = function(next: Hint?)
			const current = hint
			if current and next and current.Text == next.Text and current.Level == next.Level then
				const a = current.Keys or {}
				const b = next.Keys or {}
				if #a == #b and table.concat(a, "\0") == table.concat(b, "\0") then
					return
				end
			elseif current == nil and next == nil then
				return
			end
			hint = next
			hintText.TextColor3 = hintColor()
			layout()
		end,
		SetPlaceholder = function(text: string)
			placeholder.Text = text
		end,
		SetLog = function(active: boolean, badge: boolean)
			logActive = active
			logBadge = badge
			applyLog()
		end,
		Focus = function()
			box:CaptureFocus()
		end,
		Release = function()
			box:ReleaseFocus()
		end,
		IsFocused = function(): boolean
			-- The engine's state, not the (deferred) Focused/FocusLost events.
			return box:IsFocused()
		end,
		ScreenX = function(position: number): number
			return scroller.AbsolutePosition.X + textX(position)
		end,
		Shake = function()
			Motion.Shake(viewport, 6)
		end,
		SetTheme = function(next: Theme.Palette)
			palette = next
			applyTheme()
		end,
		SetMetrics = function(next: Ui.Metrics)
			metrics = next
			layout()
			scrollIntoView(true)
		end,
		Changed = changed,
		CursorMoved = cursorMoved,
		Submitted = submitted,
		StopRequested = stopRequested,
		FocusLost = focusLost,
		FocusChanged = focusChanged,
		LogToggled = logToggled,
		MultilinePaste = multilinePaste,
		Destroy = function()
			for _, connection in connections do
				connection:Disconnect()
			end
			caretSpring.Destroy()
			bar:Destroy()
		end,
	}
	layout()
	applyTheme()
	placeholder.Visible = true
	return input
end

return table.freeze(InputBarModule)
