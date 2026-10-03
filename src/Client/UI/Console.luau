--!strict
--[[
	The console: builds the UI from code and implements the behavior behind it — live completion, syntax
	highlighting, signature hints, resolution previews, Tab/ghost acceptance and cycling, history navigation,
	input undo/redo, the command palette, history search, prompts, toasts, activation keys, click-away hiding,
	touch chips and settings. Implements `Host.Console` for the client core.

	Per keystroke the console does one evaluation + one completion query, coalesced to at most one per frame.
]]

--// Imports
const Command = require("../../Shared/Command")
const Completion = require("../../Shared/Completion")
const Constants = require("../../Shared/Constants")
const Dialog = require("./Dialog")
const Format = require("./Format")
const Highlight = require("./Highlight")
const Host = require("../Host")
const InputBar = require("./InputBar")
const Keymap = require("./Keymap")
const LogView = require("./LogView")
const Motion = require("./Motion")
const Picker = require("./Picker")
const ResultList = require("./ResultList")
const Signal = require("../../Shared/Signal")
const SignatureBar = require("./SignatureBar")
const SuggestionPopup = require("./SuggestionPopup")
const Surface = require("./Surface")
const Theme = require("./Theme")
const Toasts = require("./Toasts")
const Types = require("../../Shared/Types")
const Ui = require("./Ui")
const Util = require("../../Shared/Util")
const Window = require("./Window")

--// Types
type Snapshot = { Text: string, Cursor: number }

type TabCycle = {
	--- Text/caret right after the last cycled insertion (cycling continues only while they match).
	Text: string,
	Cursor: number,
	--- Text/caret before the first insertion.
	OriginalText: string,
	OriginalCursor: number,
	Result: Completion.CompletionResult,
	Index: number,
}

--// Constants
const HINT = "Type a command · Tab completes · Ctrl+K palette · Ctrl+R history · F1 help"
const PLACEHOLDER = "Type a command…"
const MASH_COUNT = 5
const MASH_WINDOW = 1.2
const UNDO_LIMIT = 100
const UNDO_COALESCE = 0.6
const CHIP_LIMIT = 12

--// Helpers

const function wordLeft(text: string, cursor: number): number
	local position = cursor - 1
	while position >= 1 and text:sub(position, position):match("%s") do
		position -= 1
	end
	while position >= 1 and not text:sub(position, position):match("%s") do
		position -= 1
	end
	return position + 1
end

const function wordRight(text: string, cursor: number): number
	local position = cursor
	while position <= #text and text:sub(position, position):match("%s") do
		position += 1
	end
	while position <= #text and not text:sub(position, position):match("%s") do
		position += 1
	end
	return position
end

--// Console
const ConsoleModule = {}

function ConsoleModule.new(host: Host.ConsoleHost): Host.Console
	const shell = host.Shell
	const settings = host.Settings
	const Players = game:GetService("Players")
	const UserInputService = game:GetService("UserInputService")
	const RunService = game:GetService("RunService")
	const localPlayer = Players.LocalPlayer
	const connections: { RBXScriptConnection } = {}
	const toggled: Types.Signal<boolean> = Signal.new()

	local touch = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
	local palette = Theme.Get(Theme.Find(settings:GetString("theme")) or "Midnight")
	local metrics = Ui.Metrics(settings:GetNumber("textScale"), settings:GetString("density") == "compact", touch)
	Motion.SetReduced(settings:GetBoolean("reduceMotion"))

	-- State -------------------------------------------------------------------------------------------------
	local enabled = true
	local visible = false
	local mashUnlocked = not host.Activation.MashToEnable
	local mashTimes: { number } = {}
	local result: Completion.CompletionResult? = nil
	local evaluation: Types.EvaluateResult? = nil
	local selected: number? = nil
	local explicitNavigation = false
	local dismissedText: string? = nil
	local forceOpen = false
	local tabCycle: TabCycle? = nil
	local historyIndex: number? = nil
	local historyDraft = ""
	local undoStack: { Snapshot } = {}
	local redoStack: { Snapshot } = {}
	local lastUndoPush = 0
	local rejectedText: string? = nil
	local updateQueued = false
	local stripChar: string? = nil
	local stripUntil = 0
	local blur: BlurEffect? = nil
	local copySheetOpen = false

	-- Instances ---------------------------------------------------------------------------------------------
	const gui = Instance.new("ScreenGui")
	gui.Name = Constants.Name
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = 10000
	gui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets
	gui.Enabled = true

	const root = Ui.Frame("Root", gui)
	root.Size = UDim2.fromScale(1, 1)

	const window = Window.new(root, palette, metrics)
	const content = window.Content
	const log = LogView.new(content, palette, metrics)
	const chips = Instance.new("ScrollingFrame")
	chips.Name = "Chips"
	chips.BackgroundTransparency = 1
	chips.BorderSizePixel = 0
	chips.ScrollingDirection = Enum.ScrollingDirection.X
	chips.ScrollBarThickness = 0
	chips.AutomaticCanvasSize = Enum.AutomaticSize.X
	chips.CanvasSize = UDim2.new()
	chips.Visible = false
	chips.Parent = content
	Ui.List(chips, Enum.FillDirection.Horizontal, 6)
	const signature = SignatureBar.new(content, palette, metrics)
	const input = InputBar.new(content, palette, metrics)
	input.SetPlaceholder(PLACEHOLDER)
	const unlock = Ui.Button("MouseUnlock", content)
	unlock.Size = UDim2.fromOffset(0, 0)
	unlock.Modal = host.Activation.UnlocksMouse
	const dialog = Dialog.new(window.Card, palette, metrics)
	const popup = SuggestionPopup.new(root, palette, metrics)
	const picker = Picker.new(root, palette, metrics)
	const toasts = Toasts.new(root, palette, metrics)

	-- Touch button
	const touchButton = Ui.Button("TouchButton", root)
	touchButton.Text = "›_"
	touchButton.Font = Ui.Fonts.Bold
	touchButton.AnchorPoint = Vector2.new(0, 0)
	touchButton.Position = UDim2.fromOffset(16, 64)
	touchButton.BackgroundTransparency = 0.15
	touchButton.ZIndex = 60
	Ui.Corner(touchButton, 999)
	const touchStroke = Ui.Stroke(touchButton, palette.Border)

	-- Copy sheet (export log / copy a row)
	const sheetBackdrop = Ui.Button("CopySheet", root)
	sheetBackdrop.Size = UDim2.fromScale(1, 1)
	sheetBackdrop.BackgroundTransparency = 0.5
	sheetBackdrop.ZIndex = 70
	sheetBackdrop.Visible = false
	const sheet = Surface.new("Sheet", sheetBackdrop, Ui.Radius.L, palette, true)
	sheet.SetElevation(2.5)
	sheet.Holder.AnchorPoint = Vector2.new(0.5, 0.5)
	sheet.Holder.Position = UDim2.fromScale(0.5, 0.5)
	sheet.Holder.Size = UDim2.fromScale(0.7, 0.6)
	const sheetTitle = Ui.Label("Title", sheet.Card, Ui.Fonts.Bold, metrics.TextMd)
	sheetTitle.Position = UDim2.fromOffset(18, 10)
	sheetTitle.Size = UDim2.new(1, -36, 0, 24)
	const sheetHint = Ui.Label("Hint", sheet.Card, Ui.Fonts.Sans, metrics.TextXs)
	sheetHint.Text = "Ctrl+A, Ctrl+C to copy · Esc to close"
	sheetHint.TextXAlignment = Enum.TextXAlignment.Right
	sheetHint.Position = UDim2.fromOffset(18, 10)
	sheetHint.Size = UDim2.new(1, -36, 0, 24)
	const sheetScroll = Instance.new("ScrollingFrame")
	sheetScroll.BackgroundTransparency = 0
	sheetScroll.BorderSizePixel = 0
	sheetScroll.Position = UDim2.fromOffset(12, 42)
	sheetScroll.Size = UDim2.new(1, -24, 1, -54)
	sheetScroll.AutomaticCanvasSize = Enum.AutomaticSize.XY
	sheetScroll.CanvasSize = UDim2.new()
	sheetScroll.ScrollBarThickness = 4
	sheetScroll.Parent = sheet.Card
	Ui.Corner(sheetScroll, Ui.Radius.M)
	const sheetBox = Instance.new("TextBox")
	sheetBox.BackgroundTransparency = 1
	sheetBox.ClearTextOnFocus = false
	sheetBox.TextEditable = false
	sheetBox.MultiLine = true
	sheetBox.Font = Ui.Fonts.Mono
	sheetBox.TextXAlignment = Enum.TextXAlignment.Left
	sheetBox.TextYAlignment = Enum.TextYAlignment.Top
	sheetBox.AutomaticSize = Enum.AutomaticSize.XY
	sheetBox.Size = UDim2.fromScale(1, 0)
	sheetBox.Parent = sheetScroll
	Ui.Padding(sheetBox, 10)

	-- Helpers ------------------------------------------------------------------------------------------------
	const function formatColors(): Format.Colors
		return {
			Accent = Ui.Hex(palette.Accent),
			Secondary = Ui.Hex(palette.TextSecondary),
			Muted = Ui.Hex(palette.TextMuted),
			Link = Ui.Hex(palette.Info),
		}
	end

	const function syntaxColor(class: Highlight.SyntaxClass, token: string?): string?
		const syntax = palette.Syntax
		if class == "command" then
			return Ui.Hex(syntax.Command)
		elseif class == "number" then
			return Ui.Hex(syntax.Number)
		elseif class == "string" then
			return Ui.Hex(syntax.String)
		elseif class == "operator" then
			return Ui.Hex(syntax.Operator)
		elseif class == "flag" then
			return Ui.Hex(syntax.Flag)
		elseif class == "variable" then
			return Ui.Hex(syntax.Variable)
		elseif class == "comment" then
			return Ui.Hex(syntax.Comment)
		elseif class == "error" then
			return Ui.Hex(syntax.Error)
		elseif class == "type" then
			return Ui.Hex(Theme.TypeToken(palette.Types, token))
		elseif class == "argument" then
			return Ui.Hex(syntax.Argument)
		end
		return nil
	end

	const function highlightText(text: string, evaluated: Types.EvaluateResult?, ghost: string?, lenient: Types.Span?): string
		return Highlight.Render(
			text,
			Highlight.Classify(text, evaluated, lenient),
			syntaxColor,
			ghost,
			Ui.Hex(palette.TextMuted)
		)
	end

	const function evaluate(text: string): Types.EvaluateResult?
		const ok, value = pcall(function(): Types.EvaluateResult
			return shell.Dispatcher:Evaluate({ Text = text, Executor = localPlayer })
		end)
		return if ok then value else nil
	end

	const function echoEntry(text: string): Format.Entry
		return {
			Kind = "echo",
			Level = "echo",
			Rich = highlightText(text, evaluate(text), nil),
			Plain = text,
			Wrap = true,
		}
	end

	--- Re-renders an entry with the current palette.
	const function reformat(entry: Format.Entry): Format.Entry
		const source = entry.Source
		if source then
			return Format.Block(source, formatColors())
		elseif entry.Kind == "echo" then
			return echoEntry(entry.Plain)
		end
		return entry
	end

	const function contentLayout()
		const pad = metrics.Pad
		const inputHeight = metrics.InputHeight
		const signatureHeight = metrics.SignatureHeight
		const chipsHeight = if chips.Visible then metrics.SuggestionRow else 0
		const bottom = pad + inputHeight + signatureHeight + (if chipsHeight > 0 then chipsHeight + 6 else 0)
		log.Frame.Position = UDim2.fromOffset(0, 4)
		log.Frame.Size = UDim2.new(1, 0, 1, -(bottom + 6))
		input.Frame.Position = UDim2.new(0, pad, 1, -(pad + inputHeight))
		input.Frame.Size = UDim2.new(1, -pad * 2, 0, inputHeight)
		signature.Frame.Position = UDim2.new(0, 0, 1, -(pad + inputHeight + signatureHeight))
		chips.Position = UDim2.new(0, pad, 1, -(pad + inputHeight + signatureHeight + chipsHeight + 2))
		chips.Size = UDim2.new(1, -pad * 2, 0, chipsHeight)
	end

	-- Suggestions ------------------------------------------------------------------------------------------
	const chipPool: { TextButton } = {}

	const function hideSuggestions()
		popup.Hide()
		chips.Visible = false
		contentLayout()
		selected = nil
		explicitNavigation = false
	end

	const function suggestionItems(list: { Types.Suggestion }): { ResultList.Item }
		const items: { ResultList.Item } = {}
		for index, suggestion in list do
			items[index] = {
				Label = suggestion.Display,
				Ranges = suggestion.MatchRanges,
				Detail = suggestion.Detail,
				Icon = Ui.Icon(suggestion.Icon or suggestion.Kind),
				Tint = if suggestion.Color then Theme.TypeToken(palette.Types, suggestion.Color)
					elseif suggestion.Kind == "command" or suggestion.Kind == "alias" then palette.Syntax.Command
					elseif suggestion.Kind == "flag" then palette.Syntax.Flag
					elseif suggestion.Kind == "operator" then palette.Syntax.Operator
					elseif suggestion.Kind == "variable" then palette.Syntax.Variable
					else nil,
				Swatch = suggestion.Swatch,
				Deprecated = suggestion.Deprecated,
			}
		end
		return items
	end

	const function headerFor(current: Completion.CompletionResult): string
		const hint = current.Signature
		if current.Context ~= "Command" and hint then
			for _, part in hint.Parts do
				if part.Active and part.ArgName then
					return if hint.ActiveType and hint.ActiveType ~= part.ArgName then `{part.ArgName} · {hint.ActiveType}`
						else part.ArgName
				end
			end
		end
		return current.Context
	end

	local acceptSuggestion: (index: number, fromTab: boolean) -> ()

	const function showChips(list: { Types.Suggestion })
		for index = 1, math.max(#chipPool, math.min(#list, CHIP_LIMIT)) do
			local chip = chipPool[index]
			if index > math.min(#list, CHIP_LIMIT) then
				if chip then
					chip.Visible = false
				end
				continue
			end
			if chip == nil then
				const created = Ui.Button("Chip", chips)
				created.Font = Ui.Fonts.Mono
				created.BackgroundTransparency = 0
				created.AutomaticSize = Enum.AutomaticSize.X
				Ui.Corner(created, 999)
				Ui.Padding(created, 0, 14)
				const chipIndex = index
				created.Activated:Connect(function()
					acceptSuggestion(chipIndex, false)
				end)
				chipPool[index] = created
				chip = created
			end
			const button: TextButton = chip
			button.Visible = true
			button.LayoutOrder = index
			button.Text = list[index].Display
			button.TextSize = metrics.TextMd
			button.Size = UDim2.new(0, 0, 1, -4)
			button.BackgroundColor3 = if index == 1 then palette.Selected else palette.Hover
			button.TextColor3 = palette.Text
		end
		chips.Visible = #list > 0
		contentLayout()
	end

	--- Places the popup above the signature bar (below the input when there is no room above).
	const function placePopup(anchorX: number)
		const top = signature.Frame.AbsolutePosition.Y
		const inputBottom = input.Frame.AbsolutePosition.Y + input.Frame.AbsoluteSize.Y
		const rootPosition = root.AbsolutePosition
		const bounds = Rect.new(rootPosition + Vector2.new(8, 8), rootPosition + root.AbsoluteSize - Vector2.new(8, 8))
		const below = top - popup.Holder.AbsoluteSize.Y - 8 < bounds.Min.Y
		popup.Place(Vector2.new(anchorX, if below then inputBottom else top), bounds, below)
	end

	const function presentSuggestions(current: Completion.CompletionResult, highlightIndex: number?)
		const list = current.Suggestions
		if #list == 0 then
			hideSuggestions()
			return
		end
		if metrics.Touch then
			popup.Hide()
			showChips(list)
			return
		end
		const index = highlightIndex or 1
		selected = index
		const description = list[index] and list[index].Description
		popup.Show(headerFor(current), suggestionItems(list), index, description)
		-- Anchor at the start of the replaced text, above the input (below when there is no room).
		const anchorX = input.ScreenX(current.Replace.Start)
		placePopup(anchorX)
	end

	-- Updates ----------------------------------------------------------------------------------------------
	const function update()
		updateQueued = false
		const text = input.GetText()
		const cursor = input.GetCursor()
		evaluation = if text ~= "" then evaluate(text) else nil

		local current: Completion.CompletionResult? = nil
		const ok, value = pcall(function(): Completion.CompletionResult
			return Completion.Query({
				Shell = shell,
				Text = text,
				Cursor = cursor,
				Executor = localPlayer,
				Limit = Constants.DefaultSuggestionLimit,
				Boost = host.Boost,
				CanSee = host.CanSee,
			})
		end)
		if ok then
			current = value
		else
			warn(`[{Constants.Name}] completion failed: {value}`)
		end
		result = current

		-- Ghost text: the rest of the top suggestion, only with the caret at the end.
		local ghost: string? = nil
		if current and cursor == #text + 1 and text ~= "" and settings:GetBoolean("ghostText") and not metrics.Touch then
			ghost = Completion.Ghost(current)
		end
		-- The word under the caret is still being typed while it has completions: don't flag it yet.
		const lenient: Types.Span? = if current and #current.Suggestions > 0 and cursor == current.Replace.End then current.Replace
			else nil
		const function excused(item: Types.Diagnostic): boolean
			if lenient == nil then
				return false
			end
			return item.Span.Start >= lenient.Start and item.Span.End <= lenient.End
		end
		input.SetRich(highlightText(text, evaluation, ghost, lenient))

		-- Validation state of the prompt glyph / run button.
		local hasError = false
		local onlyExcused = true
		if evaluation then
			for _, item in evaluation.Diagnostics do
				if item.Severity == "error" then
					hasError = true
					if not excused(item) then
						onlyExcused = false
					end
				end
			end
		end
		if host.IsRunning() then
			input.SetState("running")
		elseif text == "" or (hasError and onlyExcused) then
			input.SetState("idle")
		elseif evaluation and not hasError then
			input.SetState("valid")
		else
			input.SetState("invalid")
		end

		-- Diagnostic nearest to the caret.
		local diagnostic: Types.Diagnostic? = nil
		if evaluation then
			for _, item in evaluation.Diagnostics do
				if (item.Severity == "error" or item.Severity == "warning") and not excused(item) then
					if item.Span.Start <= cursor and cursor <= item.Span.End then
						diagnostic = item
						break
					end
					if diagnostic == nil then
						diagnostic = item
					end
				end
			end
		end
		signature.Set(if current then current.Signature else nil, diagnostic, HINT)

		const preview = if current then current.Preview else nil
		-- Failures are already explained by the signature bar; the chip only shows what a value resolves to.
		if preview and preview.Ok and preview.Text ~= "" then
			input.SetPreview("→ " .. preview.Text, preview.Ok)
		else
			input.SetPreview(nil, true)
		end

		-- Suggestions (a Tab cycle keeps showing the list it is cycling through).
		const cycle = tabCycle
		if cycle and cycle.Text == text and cycle.Cursor == cursor then
			presentSuggestions(cycle.Result, cycle.Index)
			return
		end
		tabCycle = nil
		if current == nil or (text == "" and not forceOpen) or dismissedText == text then
			hideSuggestions()
			return
		end
		explicitNavigation = false
		presentSuggestions(current, nil)
	end

	const function queueUpdate()
		if updateQueued then
			return
		end
		updateQueued = true
		task.defer(update)
	end

	-- Text editing -----------------------------------------------------------------------------------------
	const function pushUndo(text: string, cursor: number, force: boolean)
		const now = os.clock()
		if not force and now - lastUndoPush < UNDO_COALESCE and #undoStack > 0 then
			return
		end
		lastUndoPush = now
		table.insert(undoStack, { Text = text, Cursor = cursor })
		if #undoStack > UNDO_LIMIT then
			table.remove(undoStack, 1)
		end
		table.clear(redoStack)
	end

	--- Programmatic edit (completion, history, undo): records undo and refreshes.
	const function setText(text: string, cursor: number?, recordUndo: boolean?)
		if recordUndo ~= false then
			pushUndo(input.GetText(), input.GetCursor(), true)
		end
		input.SetText(text, cursor)
		queueUpdate()
	end

	local previousText = ""
	local previousCursor = 1

	input.Changed:Connect(
		function(text: string, cursor: number)
			-- Swallow the activation key's character typed into the box while opening/closing.
			const pending = stripChar
			if pending and os.clock() < stripUntil then
				const position = text:find(pending, 1, true)
				if position then
					stripChar = nil
					input.SetText(text:sub(1, position - 1) .. text:sub(position + #pending), position)
					return
				end
			end
			-- `?` on an empty line opens help.
			if previousText == "" and text == "?" then
				input.SetText("", 1)
				host.Execute("help")
				return
			end
			-- Optional auto-pairing of quotes and `${`.
			if settings:GetBoolean("autoPair") and #text == #previousText + 1 and cursor == previousCursor + 1 then
				const typed = text:sub(cursor - 1, cursor - 1)
				const nextChar = text:sub(cursor, cursor)
				local closing: string? = nil
				if (typed == '"' or typed == "'") and nextChar ~= typed then
					closing = typed
				elseif typed == "{" and text:sub(cursor - 2, cursor - 2) == "$" then
					closing = "}"
				end
				if closing then
					input.SetText(text:sub(1, cursor - 1) .. closing .. text:sub(cursor), cursor)
					text = input.GetText()
				end
			end
			pushUndo(previousText, previousCursor, false)
			previousText = input.GetText()
			previousCursor = input.GetCursor()
			historyIndex = nil
			rejectedText = nil
			if dismissedText ~= nil and dismissedText ~= previousText then
				dismissedText = nil
			end
			forceOpen = false
			queueUpdate()
		end
	)

	input.CursorMoved:Connect(function(cursor: number)
		previousCursor = cursor
		queueUpdate()
	end)

	acceptSuggestion = function(index: number, fromTab: boolean)
		const current = result
		if current == nil then
			return
		end
		const suggestion = current.Suggestions[index]
		if suggestion == nil then
			return
		end
		const text = input.GetText()
		const replace = current.Replace
		const before = text:sub(1, replace.Start - 1)
		const after = text:sub(replace.End)
		const snippet = suggestion.Insert
		local insert = if snippet then snippet.Text else suggestion.Text
		local cursorOffset = if snippet then snippet.Cursor else #insert
		if snippet == nil and not suggestion.Partial and after:sub(1, 1) ~= " " then
			insert ..= " "
			cursorOffset += 1
		end
		host.Accepted(suggestion.Kind, suggestion.Text)
		setText(before .. insert .. after, #before + cursorOffset + 1)
		previousText = input.GetText()
		previousCursor = input.GetCursor()
		if fromTab and #current.Suggestions > 1 then
			const cycle = tabCycle
			tabCycle = {
				Text = previousText,
				Cursor = previousCursor,
				OriginalText = if cycle then cycle.OriginalText else text,
				OriginalCursor = if cycle then cycle.OriginalCursor else input.GetCursor(),
				Result = current,
				Index = index,
			}
		else
			tabCycle = nil
		end
		explicitNavigation = false
	end

	const function cycleTab(direction: number)
		const cycle = tabCycle
		if cycle == nil then
			return
		end
		const count = #cycle.Result.Suggestions
		const index = (cycle.Index - 1 + direction) % count + 1
		-- Restore the original text and apply the next suggestion against the original result.
		input.SetText(cycle.OriginalText, cycle.OriginalCursor)
		result = cycle.Result
		acceptSuggestion(index, true)
		const updated = tabCycle
		if updated then
			updated.OriginalText = cycle.OriginalText
			updated.OriginalCursor = cycle.OriginalCursor
		end
	end

	const function onTab(direction: number)
		const text = input.GetText()
		const cursor = input.GetCursor()
		const cycle = tabCycle
		if cycle and cycle.Text == text and cycle.Cursor == cursor then
			cycleTab(direction)
			return
		end
		const current = result
		if current == nil or #current.Suggestions == 0 then
			forceOpen = true
			dismissedText = nil
			queueUpdate()
			return
		end
		if not explicitNavigation and direction > 0 and #current.Suggestions > 1 then
			-- First Tab completes the longest common prefix when it adds something.
			const prefix = Completion.CommonPrefix(current.Suggestions, current.Partial)
			if prefix then
				const replace = current.Replace
				const before = text:sub(1, replace.Start - 1)
				const after = text:sub(math.max(cursor, replace.Start))
				setText(before .. prefix .. after, #before + #prefix + 1)
				return
			end
		end
		const index = if explicitNavigation and selected then selected
			elseif direction > 0 then 1
			else #current.Suggestions
		acceptSuggestion(index, true)
	end

	const function moveSelection(delta: number)
		const current = result
		if current == nil or #current.Suggestions == 0 then
			return
		end
		if not popup.IsOpen() and not chips.Visible then
			presentSuggestions(current, nil)
		end
		const count = #current.Suggestions
		const base = if explicitNavigation and selected then selected else (if delta > 0 then 0 else count + 1)
		selected = (base + delta - 1) % count + 1
		explicitNavigation = true
		popup.List.SetSelected(selected)
		popup.SetFooter(current.Suggestions[selected].Description)
	end

	const function navigateHistory(delta: number)
		const history = host.History()
		if #history == 0 then
			return
		end
		if historyIndex == nil then
			if delta > 0 then
				return
			end
			historyDraft = input.GetText()
			historyIndex = #history + 1
		end
		const index = math.clamp((historyIndex :: number) + delta, 1, #history + 1)
		historyIndex = index
		const text = if index > #history then historyDraft else history[index]
		input.SetText(text)
		previousText = text
		previousCursor = #text + 1
		if index > #history then
			historyIndex = nil
		end
		dismissedText = text
		queueUpdate()
	end

	-- Submission -------------------------------------------------------------------------------------------
	--- Gives the input focus back. Enter releases focus while the key is still being processed, and a capture
	--- in that same frame can be undone, so this retries for a few frames until the box is focused.
	local refocusGeneration = 0
	const function refocus()
		refocusGeneration += 1
		const generation = refocusGeneration
		task.spawn(function()
			for _ = 1, 6 do
				task.wait()
				if generation ~= refocusGeneration then
					return
				end
				if not visible or picker.IsOpen() or dialog.IsOpen() or copySheetOpen then
					return
				end
				if input.IsFocused() then
					return
				end
				input.Focus()
			end
		end)
	end

	const function submit()
		const text = input.Sync()
		if Util.Trim(text) == "" then
			return
		end
		const evaluated = evaluate(text)
		if evaluated and not evaluated.Ok and rejectedText ~= text then
			-- First Enter on an invalid line shakes; a second Enter sends it anyway (the server decides).
			rejectedText = text
			input.Shake()
			return
		end
		rejectedText = nil
		historyIndex = nil
		tabCycle = nil
		dismissedText = nil
		table.clear(undoStack)
		table.clear(redoStack)
		input.SetText("", 1)
		previousText = ""
		previousCursor = 1
		hideSuggestions()
		log.ScrollToBottom(false)
		host.Execute(text)
		queueUpdate()
	end

	-- Visibility ---------------------------------------------------------------------------------------------
	const function setBlur(on: boolean)
		const Lighting = game:GetService("Lighting")
		if on and settings:GetBoolean("blur") then
			local effect = blur
			if effect == nil then
				const created = Instance.new("BlurEffect")
				created.Name = Constants.Name .. "Blur"
				created.Size = 0
				created.Parent = Lighting
				blur = created
				effect = created
			end
			Motion.Tween(effect :: BlurEffect, 0.2, { Size = 10 })
		elseif blur then
			const effect: BlurEffect = blur
			blur = nil
			Motion.Tween(effect, 0.15, { Size = 0 }).Completed:Once(function()
				effect:Destroy()
			end)
		end
	end

	const function show()
		if visible or not enabled then
			return
		end
		visible = true
		window.Open()
		unlock.Modal = host.Activation.UnlocksMouse
		unlock.Visible = true
		setBlur(true)
		queueUpdate()
		refocus()
		toggled:Fire(true)
	end

	const function hide()
		if not visible then
			return
		end
		visible = false
		hideSuggestions()
		picker.Close()
		if input.IsFocused() then
			input.Release()
		end
		unlock.Visible = false
		setBlur(false)
		window.Close()
		toggled:Fire(false)
	end

	const function toggle()
		if visible then
			hide()
		else
			show()
		end
	end

	const function escape()
		if copySheetOpen then
			copySheetOpen = false
			sheetBackdrop.Visible = false
			refocus()
		elseif picker.IsOpen() then
			picker.Close()
			refocus()
		elseif dialog.IsOpen() then
			dialog.Cancel()
			refocus()
		elseif popup.IsOpen() or chips.Visible then
			dismissedText = input.GetText()
			hideSuggestions()
			refocus()
		elseif input.GetText() ~= "" then
			setText("", 1)
			previousText = ""
			previousCursor = 1
			refocus()
		else
			hide()
		end
	end

	-- Overlays -------------------------------------------------------------------------------------------------
	const function openCopySheet(title: string, text: string)
		copySheetOpen = true
		sheetTitle.Text = title
		sheetBox.Text = text
		sheetBox.TextSize = metrics.Mono
		sheetBackdrop.Visible = true
		task.defer(function()
			sheetBox:CaptureFocus()
			sheetBox.SelectionStart = 1
			sheetBox.CursorPosition = #sheetBox.Text + 1
		end)
	end

	const function insertCommand(command: Types.Command, run: boolean)
		local required = false
		for _, arg in command.Args do
			if not arg.Optional and arg.Positional then
				required = true
				break
			end
		end
		if run or not required then
			host.Execute(command.Name)
		else
			setText(command.Name .. " ")
			previousText = input.GetText()
			previousCursor = input.GetCursor()
		end
		refocus()
	end

	local openSettings: () -> ()

	const function openHistorySearch()
		if not visible then
			show()
		end
		hideSuggestions()
		const history = host.History()
		const seen: { [string]: true } = {}
		const entries: { Picker.Entry } = {}
		for index = #history, 1, -1 do
			const line = history[index]
			if seen[line] then
				continue
			end
			seen[line] = true
			table.insert(entries, {
				Item = { Label = line, Icon = Ui.Icon("history"), Tint = palette.TextSecondary },
				Search = line,
				Description = nil,
				Choose = function(alternate: boolean)
					if alternate then
						host.Execute(line)
					else
						setText(line)
						previousText = line
						previousCursor = #line + 1
					end
					refocus()
				end,
			})
		end
		picker.Open({
			Title = "History",
			Placeholder = "Search history…",
			Entries = entries,
			Hint = "Enter edit · Shift+Enter run · Esc close",
			Query = input.GetText(),
		})
	end

	const function openPalette()
		if not visible then
			show()
		end
		hideSuggestions()
		const entries: { Picker.Entry } = {}
		for _, command in shell.Registry:GetCommands() do
			if command.Hidden or not host.CanSee(command) then
				continue
			end
			const isAlias = command._isAlias
			table.insert(entries, {
				Item = {
					Label = command.Name,
					Detail = if isAlias then "alias" else command.Group,
					Icon = Ui.Icon(if isAlias then "alias" else "command"),
					Tint = palette.Syntax.Command,
					Deprecated = command.Deprecated ~= nil,
				},
				Search = `{command.Name} {Util.Join(command.Aliases, " ")} {command.Description}`,
				Description = `{Command.Signature(command)} — {command.Description}`,
				Choose = function(alternate: boolean)
					insertCommand(command, alternate)
				end,
			})
		end
		table.sort(entries, function(a: Picker.Entry, b: Picker.Entry): boolean
			return a.Item.Label < b.Item.Label
		end)
		const function action(label: string, icon: string, description: string, run: () -> ())
			table.insert(entries, {
				Item = { Label = label, Icon = Ui.Icon(icon), Tint = palette.Accent, Detail = "action" },
				Search = label,
				Description = description,
				Choose = function()
					run()
				end,
			})
		end
		for _, name in Theme.Names() do
			action(`Theme: {name}`, "theme", `Switch to the {name} theme`, function()
				settings:Set("theme", name)
				refocus()
			end)
		end
		action("Settings…", "setting", "Browse and change console settings", function()
			openSettings()
		end)
		action("History search", "history", "Search previously run commands (Ctrl+R)", function()
			task.defer(openHistorySearch)
		end)
		action("Clear log", "action", "Remove every row from the log (Ctrl+L)", function()
			log.Clear()
			refocus()
		end)
		action("Export log", "action", "Show the log as copyable text", function()
			openCopySheet("Log", log.Export())
		end)
		picker.Open({
			Title = "Command palette",
			Placeholder = "Search commands, themes and actions…",
			Entries = entries,
			Hint = "Enter insert · Shift+Enter run now · Esc close",
		})
	end

	openSettings = function()
		const entries: { Picker.Entry } = {}
		for _, entry in settings:List() do
			table.insert(entries, {
				Item = { Label = entry.Key, Detail = entry.Value, Icon = Ui.Icon("setting"), Tint = palette.Accent },
				Search = `{entry.Key} {entry.Description}`,
				Description = entry.Description,
				Choose = function()
					if entry.Value == "true" or entry.Value == "false" then
						settings:SetText(entry.Key, if entry.Value == "true" then "false" else "true")
						task.defer(openSettings)
					elseif entry.Key == "theme" then
						setText("theme ")
						refocus()
					else
						setText(`config {entry.Key} `)
						previousText = input.GetText()
						previousCursor = input.GetCursor()
						refocus()
					end
				end,
			})
		end
		picker.Open({
			Title = "Settings",
			Placeholder = "Search settings…",
			Entries = entries,
			Hint = "Enter toggle or edit · Esc close",
		})
	end

	-- Theme & metrics ------------------------------------------------------------------------------------------
	const function applyTheme()
		window.SetTheme(palette)
		log.SetTheme(palette)
		signature.SetTheme(palette)
		input.SetTheme(palette)
		popup.SetTheme(palette)
		picker.SetTheme(palette)
		dialog.SetTheme(palette)
		toasts.SetTheme(palette)
		touchButton.BackgroundColor3 = palette.Elevated
		touchButton.TextColor3 = palette.Accent
		touchStroke.Color = palette.Border
		sheet.SetTheme(palette)
		sheetBackdrop.BackgroundColor3 = palette.Shadow
		sheetTitle.TextColor3 = palette.Text
		sheetHint.TextColor3 = palette.TextMuted
		sheetScroll.BackgroundColor3 = palette.Input
		sheetBox.TextColor3 = palette.Text
		queueUpdate()
	end

	const function applyMetrics()
		window.SetMetrics(metrics)
		log.SetMetrics(metrics)
		signature.SetMetrics(metrics)
		input.SetMetrics(metrics)
		popup.SetMetrics(metrics)
		picker.SetMetrics(metrics)
		dialog.SetMetrics(metrics)
		toasts.SetMetrics(metrics)
		const touchSize = if metrics.Touch then 52 else 44
		touchButton.Size = UDim2.fromOffset(touchSize, touchSize)
		touchButton.TextSize = metrics.TextMd
		contentLayout()
		queueUpdate()
	end

	const function refreshTouchButton()
		const available = UserInputService.TouchEnabled or UserInputService.GamepadEnabled
		touchButton.Visible = host.Activation.TouchButton and available and enabled
	end

	const function readLayout()
		const raw = settings:GetString("layout")
		const x, y, width, height = raw:match("^(%-?%d+),(%-?%d+),(%d+),(%d+)$")
		if x and y and width and height then
			window.SetRect({
				X = tonumber(x) or 0,
				Y = tonumber(y) or 0,
				Width = tonumber(width) or 0,
				Height = tonumber(height) or 0,
			})
		end
	end

	const function applySetting(key: string)
		if key == "theme" then
			const name = Theme.Find(settings:GetString("theme")) or "Midnight"
			palette = Theme.Get(name)
			applyTheme()
			log.Reformat(reformat)
		elseif key == "density" or key == "textScale" then
			metrics = Ui.Metrics(settings:GetNumber("textScale"), settings:GetString("density") == "compact", touch)
			applyMetrics()
		elseif key == "reduceMotion" then
			Motion.SetReduced(settings:GetBoolean("reduceMotion"))
		elseif key == "dock" then
			const dock = settings:GetString("dock")
			-- Phones get a console docked to the top (clear of the on-screen keyboard) instead of a floating window.
			window.SetDock(if dock == "top" or dock == "bottom" then dock elseif touch then "top" else "float")
			readLayout()
		elseif key == "blur" then
			setBlur(visible)
		elseif key == "timestamps" then
			log.SetTimestamps(settings:GetBoolean("timestamps"))
		elseif key == "opacity" then
			window.SetOpacity(settings:GetNumber("opacity"))
		elseif key == "maxLog" then
			log.SetLimit(settings:GetNumber("maxLog"))
		elseif key == "ghostText" then
			queueUpdate()
		end
	end

	--- Creates themes registered on the registry (by plugins or `RegisterTheme`) that do not exist yet.
	const function loadRegisteredThemes()
		for _, options in shell.Registry:GetThemes() do
			if not Theme.Has(options.Name) then
				const ok, err = pcall(Theme.Create, options)
				if not ok then
					warn(`[{Constants.Name}] Theme '{options.Name}' was not created: {err}`)
				end
			end
		end
	end
	loadRegisteredThemes()
	shell.Registry.Changed:Connect(loadRegisteredThemes)

	settings.Changed:Connect(applySetting)
	for _, key in { "theme", "dock", "timestamps", "opacity", "maxLog" } do
		applySetting(key)
	end
	readLayout()

	window.RectChanged:Connect(
		function()
			const rect = window.GetRect()
			-- Dragging can undock the window; keep the setting in sync.
			if window.GetDock() ~= settings:GetString("dock") then
				settings:Set("dock", window.GetDock())
			end
			settings:Set(
				"layout",
				`{math.floor(rect.X)},{math.floor(rect.Y)},{math.floor(rect.Width)},{math.floor(rect.Height)}`
			)
		end
	)

	-- Wiring --------------------------------------------------------------------------------------------------
	window.CloseRequested:Connect(hide)
	window.PaletteRequested:Connect(openPalette)
	window.SettingsRequested:Connect(function()
		openSettings()
	end)
	window.ExportRequested:Connect(function()
		openCopySheet("Log", log.Export())
	end)
	log.Activated:Connect(function(entry: Format.Entry)
		openCopySheet(if entry.Kind == "echo" then "Command" else "Output", entry.Plain)
	end)
	input.Submitted:Connect(submit)
	input.StopRequested:Connect(function()
		host.Cancel()
	end)
	input.PreviewActivated:Connect(function()
		const current = result
		const preview = if current then current.Preview else nil
		if preview and #preview.Items > 0 then
			log.Add({
				Kind = "text",
				Level = "info",
				Rich = Util.EscapeRichText(table.concat(preview.Items, ", ")),
				Plain = table.concat(preview.Items, ", "),
				Wrap = true,
			})
		end
	end)
	input.MultilinePaste:Connect(function(pasted: string)
		const lines = select(2, pasted:gsub("\n", "\n")) + 1
		task.spawn(function()
			const answer = dialog.Ask({
				Kind = "confirm",
				Title = "Run pasted script?",
				Message = `The pasted text has {lines} lines. Run it as a script?`,
			})
			if answer == "yes" then
				host.Execute(pasted)
			end
			refocus()
		end)
	end)
	input.FocusLost:Connect(function(enterPressed: boolean)
		if not visible then
			return
		end
		if enterPressed then
			const current = result
			if explicitNavigation and selected and current and popup.IsOpen() then
				acceptSuggestion(selected, false)
			else
				submit()
			end
			refocus()
		end
	end)
	picker.TextBox.FocusLost:Connect(function(enterPressed: boolean)
		if not enterPressed and not picker.IsOpen() then
			refocus()
		end
	end)
	popup.List.Activated:Connect(function(index: number)
		acceptSuggestion(index, false)
		refocus()
	end)
	popup.List.Hovered:Connect(
		function(index: number)
			-- Hover only previews: Enter still runs the line unless the keyboard picked a suggestion.
			popup.List.SetSelected(index)
			const current = result
			if current and current.Suggestions[index] then
				popup.SetFooter(current.Suggestions[index].Description)
			end
		end
	)
	touchButton.Activated:Connect(toggle)

	-- Keyboard -----------------------------------------------------------------------------------------------
	const function isActivationKey(key: Enum.KeyCode): boolean
		return table.find(host.Activation.Keys, key) ~= nil
	end

	const function activationChar(key: Enum.KeyCode): string?
		if key == Enum.KeyCode.Backquote then
			return "`"
		elseif key == Enum.KeyCode.Tilde then
			return "~"
		end
		return nil
	end

	const function onActivation(key: Enum.KeyCode)
		if not enabled then
			return
		end
		if not mashUnlocked then
			const now = os.clock()
			table.insert(mashTimes, now)
			while #mashTimes > 0 and now - mashTimes[1] > MASH_WINDOW do
				table.remove(mashTimes, 1)
			end
			if #mashTimes < MASH_COUNT then
				return
			end
			mashUnlocked = true
		end
		stripChar = activationChar(key)
		stripUntil = os.clock() + 0.2
		if visible then
			-- Restore the text as it was before the key's character landed.
			const before = input.GetText()
			const cursor = input.GetCursor()
			hide()
			task.defer(function()
				if input.GetText() ~= before then
					input.SetText(before, cursor)
					previousText = before
				end
			end)
		else
			show()
		end
	end

	const function handleAction(action: Keymap.Action): boolean
		const text = input.GetText()
		const cursor = input.GetCursor()
		if action == "Accept" or action == "AcceptBackward" then
			onTab(if action == "Accept" then 1 else -1)
			return true
		elseif action == "AcceptGhost" then
			if cursor == #text + 1 and result and Completion.Ghost(result) then
				const ghost = Completion.Ghost(result) :: string
				setText(text .. ghost, #text + #ghost + 1)
				previousText = input.GetText()
				previousCursor = input.GetCursor()
				return true
			end
			return false
		elseif action == "Up" or action == "Down" then
			const delta = if action == "Up" then -1 else 1
			if historyIndex == nil and text ~= "" and (popup.IsOpen() or chips.Visible) then
				moveSelection(delta)
			else
				navigateHistory(delta)
			end
			return true
		elseif action == "ForceSuggest" then
			forceOpen = true
			dismissedText = nil
			queueUpdate()
			return true
		elseif action == "HistorySearch" then
			openHistorySearch()
			return true
		elseif action == "ClearLog" then
			log.Clear()
			return true
		elseif action == "DeleteWord" then
			const start = wordLeft(text, cursor)
			setText(text:sub(1, start - 1) .. text:sub(cursor), start)
			previousText = input.GetText()
			previousCursor = start
			return true
		elseif action == "WordLeft" or action == "WordRight" then
			const target = if action == "WordLeft" then wordLeft(text, cursor) else wordRight(text, cursor)
			-- Deferred so it wins over the TextBox's own handling of the same keys.
			task.defer(function()
				input.SetCursor(target)
				previousCursor = target
			end)
			return true
		elseif action == "Undo" then
			const snapshot = table.remove(undoStack)
			if snapshot then
				table.insert(redoStack, { Text = text, Cursor = cursor })
				task.defer(function()
					input.SetText(snapshot.Text, snapshot.Cursor)
					previousText = snapshot.Text
					previousCursor = snapshot.Cursor
					queueUpdate()
				end)
			end
			return true
		elseif action == "Redo" then
			const snapshot = table.remove(redoStack)
			if snapshot then
				table.insert(undoStack, { Text = text, Cursor = cursor })
				task.defer(function()
					input.SetText(snapshot.Text, snapshot.Cursor)
					previousText = snapshot.Text
					previousCursor = snapshot.Cursor
					queueUpdate()
				end)
			end
			return true
		elseif action == "Cancel" then
			const selectionStart = input.GetSelection()
			if host.IsRunning() and selectionStart == nil then
				host.Cancel()
				return true
			end
			return false
		elseif action == "Palette" then
			openPalette()
			return true
		elseif action == "Help" then
			const current = result
			const hint = if current then current.Signature else nil
			host.Execute(if hint then `help {hint.Command}` else "help")
			return true
		end
		return false
	end

	table.insert(
		connections,
		UserInputService.InputBegan:Connect(
			function(inputObject: InputObject, processed: boolean)
				const kind = inputObject.UserInputType
				if kind == Enum.UserInputType.MouseButton1 or kind == Enum.UserInputType.Touch then
					-- Click-away hiding.
					if visible and host.Activation.HideOnLostFocus and not picker.IsOpen() and not dialog.IsOpen() then
						const point = Vector2.new(inputObject.Position.X, inputObject.Position.Y)
						const bounds = window.Bounds()
						const inside = point.X >= bounds.X
							and point.X <= bounds.X + bounds.Width
							and point.Y >= bounds.Y
							and point.Y <= bounds.Y + bounds.Height
						const popupHolder = popup.Holder
						const inPopup = popup.IsOpen()
							and point.X >= popupHolder.AbsolutePosition.X
							and point.X <= popupHolder.AbsolutePosition.X + popupHolder.AbsoluteSize.X
							and point.Y >= popupHolder.AbsolutePosition.Y
							and point.Y <= popupHolder.AbsolutePosition.Y + popupHolder.AbsoluteSize.Y
						const onTouchButton = touchButton.Visible
							and point.X >= touchButton.AbsolutePosition.X
							and point.X <= touchButton.AbsolutePosition.X + touchButton.AbsoluteSize.X
							and point.Y >= touchButton.AbsolutePosition.Y
							and point.Y <= touchButton.AbsolutePosition.Y + touchButton.AbsoluteSize.Y
						if not inside and not inPopup and not onTouchButton and not copySheetOpen then
							hide()
						end
					end
					return
				end
				if kind ~= Enum.UserInputType.Keyboard and not kind.Name:match("^Gamepad") then
					return
				end
				const key = inputObject.KeyCode
				const focusedBox = UserInputService:GetFocusedTextBox()
				const typingElsewhere = focusedBox ~= nil
					and focusedBox ~= input.TextBox
					and focusedBox ~= picker.TextBox
					and focusedBox ~= sheetBox
				-- With a modifier held the key types a character (Shift+` is ~), so it does not toggle.
				const modifiers = Keymap.Modifiers()
				const modified = modifiers.Shift or modifiers.Ctrl or modifiers.Alt
				if isActivationKey(key) and not typingElsewhere and not (modified and focusedBox ~= nil) then
					if not (picker.IsOpen() or dialog.IsOpen()) then
						onActivation(key)
					end
					return
				end
				if not visible then
					return
				end
				if key == Enum.KeyCode.Escape then
					escape()
					return
				end
				if copySheetOpen then
					return
				end
				if picker.IsOpen() then
					if key == Enum.KeyCode.Up then
						picker.Move(-1)
					elseif key == Enum.KeyCode.Down then
						picker.Move(1)
					end
					return
				end
				if dialog.IsOpen() then
					if key == Enum.KeyCode.Up then
						dialog.Move(-1)
					elseif key == Enum.KeyCode.Down then
						dialog.Move(1)
					elseif key == Enum.KeyCode.Return or key == Enum.KeyCode.KeypadEnter then
						if dialog.Kind() ~= "text" then
							dialog.Confirm()
						end
					elseif dialog.Kind() == "confirm" and (key == Enum.KeyCode.Y or key == Enum.KeyCode.N) then
						if key == Enum.KeyCode.Y then
							dialog.Confirm()
						else
							dialog.Cancel()
						end
					end
					return
				end
				if focusedBox ~= input.TextBox then
					-- Keys while the console is open but unfocused: typing refocuses the input.
					if not processed and not typingElsewhere then
						refocus()
					end
					return
				end
				const action = Keymap.Match(host.Keymap, key, Keymap.Modifiers())
				if action then
					handleAction(action)
				end
			end
		)
	)
	table.insert(connections, UserInputService:GetPropertyChangedSignal("TouchEnabled"):Connect(refreshTouchButton))
	table.insert(connections, UserInputService.GamepadConnected:Connect(refreshTouchButton))
	table.insert(
		connections,
		RunService.Heartbeat:Connect(
			function()
				-- Keep the popup anchored while the window moves.
				if popup.IsOpen() and result and not updateQueued then
					const current = result
					placePopup(input.ScreenX(current.Replace.Start))
				end
			end
		)
	)

	-- Initial state --------------------------------------------------------------------------------------------
	window.SetTitle(`<b>{Ui.Escape(Constants.Name)}</b>  <font transparency="0.4">{Ui.Escape(host.PlaceName())}</font>`)
	window.SetStatus(
		if host.IsConnected() then "online" else "offline",
		if host.IsConnected() then "success" else "warning"
	)
	applyTheme()
	applyMetrics()
	refreshTouchButton()
	unlock.Visible = false
	gui.Parent = localPlayer:WaitForChild("PlayerGui")

	-- Console API ---------------------------------------------------------------------------------------------
	const console: Host.Console = {
		Show = show,
		Hide = hide,
		Toggle = toggle,
		IsVisible = function(): boolean
			return visible
		end,
		SetEnabled = function(value: boolean)
			enabled = value
			if not value then
				hide()
			end
			refreshTouchButton()
		end,
		AddBlock = function(block: Types.Block)
			local shown = block
			if block.Kind == "custom" then
				-- Registered renderers turn custom data into a standard block.
				const renderer = shell.Registry:GetOutputRenderer(block.Renderer)
				if renderer then
					const ok, rendered = pcall(renderer, block.Data)
					if ok and rendered then
						shown = rendered
					end
				end
			end
			const entry = Format.Block(shown, formatColors())
			if entry.Kind == "progress" and log.UpdateProgress(entry) then
				return
			end
			log.Add(entry)
		end,
		AddEcho = function(text: string)
			log.Add(echoEntry(text))
			log.ScrollToBottom(true)
		end,
		Notify = function(text: string, level: Types.Level?)
			toasts.Show(text, level)
		end,
		Prompt = function(request: Types.PromptRequest): Types.PromptAnswer
			show()
			const answer = dialog.Ask(request)
			refocus()
			return answer
		end,
		SetRunning = function(running: boolean)
			window.SetStatus(
				if running then "running…" elseif host.IsConnected() then "online" else "offline",
				if running then "warning" elseif host.IsConnected() then "success" else "warning"
			)
			queueUpdate()
		end,
		Clear = function()
			log.Clear()
		end,
		OpenPalette = openPalette,
		ExportLog = function(): string
			return log.Export()
		end,
		SetTheme = function(name: string): boolean
			const found = Theme.Find(name)
			if found == nil then
				return false
			end
			settings:Set("theme", found)
			return true
		end,
		GetTheme = function(): string
			return palette.Name
		end,
		GetThemes = Theme.Names,
		RefreshActivation = function()
			unlock.Modal = host.Activation.UnlocksMouse
			if not host.Activation.MashToEnable then
				mashUnlocked = true
			end
			refreshTouchButton()
		end,
		Toggled = toggled,
		Destroy = function()
			for _, connection in connections do
				connection:Disconnect()
			end
			setBlur(false)
			window.Destroy()
			popup.Destroy()
			picker.Destroy()
			toasts.Destroy()
			gui:Destroy()
		end,
	}
	return table.freeze(console)
end

return table.freeze(ConsoleModule)
