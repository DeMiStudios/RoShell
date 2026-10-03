--!strict
--[[
	The command input: a transparent `TextBox` on top of a RichText overlay that carries the syntax colors and the
	ghost completion. The caret and selection are drawn by hand (the native ones disappear with the transparent
	text) and the content scrolls horizontally to keep the caret in view.

	Text changes are detected by comparing against the last known text instead of suppression flags, because
	property signals are deferred.
]]

--// Imports
const InputText = require("./InputText")
const Lexer = require("../../Shared/Lexer")
const Motion = require("./Motion")
const Signal = require("../../Shared/Signal")
const Theme = require("./Theme")
const Types = require("../../Shared/Types")
const Ui = require("./Ui")

--// Types
export type InputState = "idle" | "valid" | "invalid" | "running"

export type InputBar = {
	read Frame: Frame,
	read TextBox: TextBox,
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
	read SetPreview: (text: string?, ok: boolean) -> (),
	read SetPlaceholder: (text: string) -> (),
	read Focus: () -> (),
	read Release: () -> (),
	read IsFocused: () -> boolean,
	--- Screen X of a byte position (for anchoring the suggestion list).
	read ScreenX: (position: number) -> number,
	read Shake: () -> (),
	read SetTheme: (palette: Theme.Palette) -> (),
	read SetMetrics: (metrics: Ui.Metrics) -> (),
	--- User edits: new text and caret.
	read Changed: Types.Signal<string, number>,
	read CursorMoved: Types.Signal<number>,
	read Submitted: Types.Signal<()>,
	read FocusLost: Types.Signal<boolean>,
	read Focused: Types.Signal<()>,
	read StopRequested: Types.Signal<()>,
	read PreviewActivated: Types.Signal<()>,
	--- Text pasted with two or more non-empty lines (breaks normalized to "\n"), offered as a script.
	read MultilinePaste: Types.Signal<string>,
	read Destroy: () -> (),
}

--// Constants
const SPINNER = { "◐", "◓", "◑", "◒" }
const CARET_MARGIN = 24

--// InputBar
const InputBarModule = {}

function InputBarModule.new(parent: Instance, initialPalette: Theme.Palette, initialMetrics: Ui.Metrics): InputBar
	local palette = initialPalette
	local metrics = initialMetrics
	local knownText = ""
	local knownCursor = 1
	local state: InputState = "idle"
	local scrollX = 0
	local focused = false
	local blinkClock = 0
	local spinnerIndex = 1
	local previewText: string? = nil
	local previewOk = true
	const connections: { RBXScriptConnection } = {}
	const changed: Types.Signal<string, number> = Signal.new()
	const cursorMoved: Types.Signal<number> = Signal.new()
	const submitted: Types.Signal<()> = Signal.new()
	const focusLost: Types.Signal<boolean> = Signal.new()
	const focusedSignal: Types.Signal<()> = Signal.new()
	const stopRequested: Types.Signal<()> = Signal.new()
	const previewActivated: Types.Signal<()> = Signal.new()
	const multilinePaste: Types.Signal<string> = Signal.new()

	-- Container ---------------------------------------------------------------------------------------------
	const bar = Instance.new("Frame")
	bar.Name = "Input"
	bar.BorderSizePixel = 0
	bar.Parent = parent
	Ui.Corner(bar, Ui.Radius.Input)
	const stroke = Ui.Stroke(bar, palette.Border)

	const glow = Ui.Frame("Glow", bar)
	glow.Size = UDim2.new(1, 6, 1, 6)
	glow.Position = UDim2.fromOffset(-3, -3)
	glow.ZIndex = 0
	Ui.Corner(glow, Ui.Radius.Input + 3)
	const glowStroke = Ui.Stroke(glow, palette.Accent, 1, 3)

	const prompt = Ui.Label("Prompt", bar, Ui.Fonts.Mono, metrics.Mono)
	prompt.Text = "›"
	prompt.TextXAlignment = Enum.TextXAlignment.Center

	const viewport = Ui.Frame("Viewport", bar)
	viewport.ClipsDescendants = true

	const scroller = Ui.Frame("Scroller", viewport)

	const selection = Ui.Frame("Selection", scroller)
	selection.BackgroundTransparency = 0.65
	selection.Visible = false
	Ui.Corner(selection, 2)

	const overlay = Ui.Label("Overlay", scroller, Ui.Fonts.Mono, metrics.Mono)
	overlay.RichText = true
	overlay.Size = UDim2.fromScale(1, 1)

	const placeholder = Ui.Label("Placeholder", viewport, Ui.Fonts.Mono, metrics.Mono)
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
	box.Font = Ui.Fonts.Mono
	box.TextTransparency = 1
	box.TextXAlignment = Enum.TextXAlignment.Left
	box.Size = UDim2.fromScale(1, 1)
	box.ZIndex = 2
	box.Parent = scroller

	const caret = Ui.Frame("Caret", scroller)
	caret.BackgroundTransparency = 0
	caret.ZIndex = 3
	caret.Visible = false
	Ui.Corner(caret, 1)

	const preview = Ui.Button("Preview", bar)
	preview.Font = Ui.Fonts.Medium
	preview.AnchorPoint = Vector2.new(1, 0.5)
	preview.Visible = false
	Ui.Corner(preview, 999)

	const run = Ui.Button("Run", bar)
	run.Font = Ui.Fonts.Bold
	run.AnchorPoint = Vector2.new(1, 0.5)
	run.BackgroundTransparency = 0
	Ui.Corner(run, 8)

	-- Caret position animates with a fast spring so jumps (accepting a completion) glide.
	const caretSpring = Motion.Spring(0, 22, 1, function(x: number)
		caret.Position = UDim2.new(0, math.floor(x + 0.5), 0.5, 0)
	end)

	-- Layout -----------------------------------------------------------------------------------------------
	const function textX(position: number): number
		return Ui.MonoTextWidth(knownText:sub(1, position - 1), metrics)
	end

	const function runWidth(): number
		return metrics.InputHeight - 12
	end

	const function previewWidth(): number
		if not preview.Visible then
			return 0
		end
		return Ui.Measure(preview.Text, metrics.TextSm, Ui.Fonts.Medium).X + 20
	end

	const function layout()
		-- The console owns the bar's size; only the content is laid out here.
		const promptWidth = math.ceil(metrics.MonoWidth * 2) + 10
		prompt.TextSize = metrics.Mono
		prompt.Position = UDim2.fromOffset(4, 0)
		prompt.Size = UDim2.new(0, promptWidth, 1, 0)
		const right = runWidth() + 8 + (if preview.Visible then previewWidth() + 6 else 0)
		viewport.Position = UDim2.new(0, promptWidth + 4, 0.5, -metrics.LineHeight // 2 - 2)
		viewport.Size = UDim2.new(1, -(promptWidth + 4 + right + 6), 0, metrics.LineHeight + 4)
		overlay.TextSize = metrics.Mono
		placeholder.TextSize = metrics.Mono
		box.TextSize = metrics.Mono
		caret.AnchorPoint = Vector2.new(0, 0.5)
		caret.Size = UDim2.fromOffset(2, metrics.LineHeight)
		run.TextSize = metrics.TextMd
		run.Size = UDim2.fromOffset(runWidth(), runWidth())
		run.Position = UDim2.new(1, -6, 0.5, 0)
		preview.TextSize = metrics.TextSm
		preview.Size = UDim2.fromOffset(previewWidth(), math.max(20, metrics.LineHeight + 4))
		preview.Position = UDim2.new(1, -(runWidth() + 12), 0.5, 0)
	end

	const function scrollIntoView(snap: boolean)
		const viewWidth = viewport.AbsoluteSize.X
		const caretX = textX(knownCursor)
		const fullWidth = Ui.MonoTextWidth(knownText, metrics)
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
		selection.Position = UDim2.new(0, x1, 0.5, -metrics.LineHeight // 2)
		selection.Size = UDim2.fromOffset(math.max(2, x2 - x1), metrics.LineHeight)
	end

	const function applyState()
		local promptColor = palette.TextMuted
		local runBackground = palette.Hover
		local runText = palette.TextMuted
		local glyph = "⏎"
		if state == "valid" then
			promptColor = palette.Accent
			runBackground = palette.Accent
			runText = palette.TextInverse
		elseif state == "invalid" then
			promptColor = palette.Error
		elseif state == "running" then
			promptColor = palette.Warning
			runBackground = palette.Error
			runText = palette.TextInverse
			glyph = "■"
		end
		prompt.Text = if state == "running" then SPINNER[spinnerIndex] else "›"
		run.Text = glyph
		Motion.Tween(prompt, 0.15, { TextColor3 = promptColor })
		Motion.Tween(run, 0.15, { BackgroundColor3 = runBackground, TextColor3 = runText })
	end

	const function applyTheme()
		bar.BackgroundColor3 = palette.Input
		stroke.Color = if focused then palette.BorderFocus else palette.Border
		glowStroke.Color = palette.Accent
		selection.BackgroundColor3 = palette.Accent
		overlay.TextColor3 = palette.Text
		placeholder.TextColor3 = palette.TextMuted
		caret.BackgroundColor3 = palette.Accent
		preview.BackgroundColor3 = palette.Selected
		preview.TextColor3 = if previewOk then palette.Accent else palette.Error
		applyState()
	end

	const function setFocusVisual(isFocused: boolean)
		Motion.Tween(stroke, 0.15, { Color = if isFocused then palette.BorderFocus else palette.Border })
		Motion.Tween(glowStroke, 0.2, { Transparency = if isFocused then 0.82 else 1 })
		caret.Visible = isFocused
	end

	--- Applies a focus change once, whether it comes from an event or is noticed on a frame: capturing focus again
	--- right after Enter released it can leave the box focused without a Focused event.
	const function setFocused(isFocused: boolean)
		if isFocused == focused then
			return
		end
		focused = isFocused
		setFocusVisual(isFocused)
		if isFocused then
			scrollIntoView(true)
			focusedSignal:Fire()
		else
			selection.Visible = false
		end
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
		preview.Activated:Connect(function()
			previewActivated:Fire()
		end)
	)
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
				if state == "running" then
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
		SetPreview = function(text: string?, ok: boolean)
			previewText = text
			previewOk = ok
			preview.Visible = text ~= nil
			preview.Text = text or ""
			preview.TextColor3 = if ok then palette.Accent else palette.Error
			layout()
		end,
		SetPlaceholder = function(text: string)
			placeholder.Text = text
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
			Motion.Shake(bar, 6)
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
		FocusLost = focusLost,
		Focused = focusedSignal,
		StopRequested = stopRequested,
		PreviewActivated = previewActivated,
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
	glowStroke.Transparency = 1
	placeholder.Visible = true
	if previewText then
		input.SetPreview(previewText, previewOk)
	end
	return input
end

return table.freeze(InputBarModule)
