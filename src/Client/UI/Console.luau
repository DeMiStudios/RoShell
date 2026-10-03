--!strict
--[[
	The console: a command bar — a pill docked to the top of the screen by default — and a panel that pops out of it
	when there is something to show: while typing, commands on the left and the argument being typed (type,
	description, candidates) on the right; after running a command, its output; on demand, the whole log; and
	prompts, pickers (command palette, history search, themes, settings) and copyable text.

	Builds the UI from code and implements the behavior behind it — live completion, syntax highlighting, Tab/ghost
	acceptance and cycling, history navigation, input undo/redo, activation keys, click-away hiding and settings.
	Implements `Host.Console` for the client core. Per keystroke the console does one evaluation + one completion
	query, coalesced to at most one per frame.
]]

--// Imports
const Assist = require("./Assist")
const Bar = require("./Bar")
const Command = require("../../Shared/Command")
const Completion = require("../../Shared/Completion")
const Constants = require("../../Shared/Constants")
const Dialog = require("./Dialog")
const Format = require("./Format")
const Highlight = require("./Highlight")
const Host = require("../Host")
const Icons = require("./Icons")
const InputBar = require("./InputBar")
const InputText = require("./InputText")
const Keymap = require("./Keymap")
const LogView = require("./LogView")
const Model = require("./Model")
const Motion = require("./Motion")
const Panel = require("./Panel")
const Picker = require("./Picker")
const Signal = require("../../Shared/Signal")
const Surface = require("./Surface")
const Theme = require("./Theme")
const Toasts = require("./Toasts")
const Types = require("../../Shared/Types")
const Ui = require("./Ui")
const Util = require("../../Shared/Util")

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

--- What the panel shows.
type PanelMode = "none" | "assist" | "log" | "dialog" | "picker" | "sheet"

--// Constants
const PLACEHOLDER = "Type a command…"
const MASH_COUNT = 5
const MASH_WINDOW = 1.2
const UNDO_LIMIT = 100
const UNDO_COALESCE = 0.6
--- Other commands listed under the current one while an argument is typed.
const CONTEXT_COMMANDS = 5
--- A line that shows off every syntax color of a theme (picker preview): token text and syntax class.
const THEME_SAMPLE: { { string } } = {
	{ "give", "Command" },
	{ "%Red", "Operator" },
	{ '"Sword"', "String" },
	{ "3", "Number" },
	{ "--silent", "Flag" },
	{ "$target", "Variable" },
	{ "# gift", "Comment" },
}

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

--- Reads the floating bar position saved in the `layout` setting: fractions (`f:0.500,0.180`), or the pixel rect
--- older versions saved (`x,y,width,height`).
const function parseLayout(raw: string, screen: Vector2): Vector2?
	const fx, fy = raw:match("^f:([%d%.]+),([%d%.]+)$")
	if fx and fy then
		const x = tonumber(fx)
		const y = tonumber(fy)
		if x and y then
			return Vector2.new(math.clamp(x, 0, 1), math.clamp(y, 0, 1))
		end
	end
	const x, y, width = raw:match("^(%-?%d+),(%-?%d+),(%d+),%d+$")
	if x and y and width and screen.X > 0 and screen.Y > 0 then
		const left = tonumber(x) or 0
		const top = tonumber(y) or 0
		return Vector2.new(
			math.clamp((left + (tonumber(width) or 0) / 2) / screen.X, 0, 1),
			math.clamp(top / screen.Y, 0, 1)
		)
	end
	return nil
end

--// Console
const ConsoleModule = {}

function ConsoleModule.new(host: Host.ConsoleHost): Host.Console
	const shell = host.Shell
	const settings = host.Settings
	const Players = game:GetService("Players")
	const UserInputService = game:GetService("UserInputService")
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
	local diagnostic: Types.Diagnostic? = nil
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
	-- Prompts being shown through `ask` (the input steps aside meanwhile).
	local asking = 0
	-- Line and caret the suggestions were last presented for.
	local presentedText: string? = nil
	local presentedCursor = 0
	-- Panel state: the suggestions are showing, the output/log is showing (expanded: the whole log), output arrived
	-- while something else showed (the history button gets a dot).
	local assistActive = false
	local logShown = false
	local logExpanded = false
	local unseen = false
	local panelMode: PanelMode = "none"
	local sheetOpen = false
	-- The bar's line before a picker took the input over.
	local pickerSaved: Snapshot? = nil
	local pickerShown = false
	-- Commands in the left column while an argument is typed (index 1 is the current one).
	local contextList: { Types.Command } = {}

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

	const bar = Bar.new(root, palette, metrics)
	const input = InputBar.new(bar.Content, palette, metrics)
	bar.AttachHandle(input.Handle)
	const unlock = Ui.Button("MouseUnlock", bar.Content)
	unlock.Size = UDim2.fromOffset(0, 0)
	unlock.Modal = host.Activation.UnlocksMouse

	const panel = Panel.new(root, palette, metrics)
	const assist = Assist.new(panel.Content, palette, metrics)
	const log = LogView.new(panel.Content, palette, metrics)
	log.Frame.Size = UDim2.fromScale(1, 1)
	const dialog = Dialog.new(panel.Content, palette, metrics)
	const picker = Picker.new()
	const toasts = Toasts.new(root, palette, metrics)

	-- Copy sheet (export log / copy a row): selectable text in the panel.
	const sheet = Ui.Frame("Sheet", panel.Content)
	sheet.Size = UDim2.fromScale(1, 1)
	sheet.Visible = false
	const sheetTitle = Ui.Label("Title", sheet, Ui.Fonts.Bold, metrics.TextMd)
	sheetTitle.Position = UDim2.fromOffset(16, 10)
	sheetTitle.Size = UDim2.new(1, -32, 0, 22)
	const sheetScroll = Instance.new("ScrollingFrame")
	sheetScroll.Name = "Scroll"
	sheetScroll.BackgroundTransparency = 0
	sheetScroll.BorderSizePixel = 0
	sheetScroll.Position = UDim2.fromOffset(10, 38)
	sheetScroll.Size = UDim2.new(1, -20, 1, -48)
	sheetScroll.AutomaticCanvasSize = Enum.AutomaticSize.XY
	sheetScroll.CanvasSize = UDim2.new()
	sheetScroll.ScrollBarThickness = 4
	sheetScroll.Parent = sheet
	Ui.Corner(sheetScroll, Ui.Radius.M + 2)
	const sheetBox = Instance.new("TextBox")
	sheetBox.Name = "Text"
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

	-- Touch button: a glass circle that toggles the console.
	const touchSurface = Surface.new("TouchButton", root, 999, palette, {})
	const touchButton = Ui.Button("Button", touchSurface.Card)
	touchButton.Size = UDim2.fromScale(1, 1)
	const touchIcon = Ui.Label("Icon", touchButton, Ui.Fonts.Bold, metrics.IconSize)
	touchIcon.Size = UDim2.fromScale(1, 1)
	touchIcon.TextXAlignment = Enum.TextXAlignment.Center
	Icons.Apply(touchIcon, "prompt")
	touchSurface.Holder.ZIndex = 60
	touchSurface.Holder.Position = UDim2.fromOffset(16, game:GetService("GuiService"):GetGuiInset().Y + 8)

	-- Helpers ------------------------------------------------------------------------------------------------
	const function formatColors(): Format.Colors
		return {
			Accent = Ui.Hex(palette.Accent),
			Secondary = Ui.Hex(palette.TextSecondary),
			Muted = Ui.Hex(palette.TextMuted),
			Link = Ui.Hex(palette.Info),
		}
	end

	const function modelColors(): Model.Colors
		const types = palette.Types
		return {
			Text = Ui.Hex(palette.Text),
			Secondary = Ui.Hex(palette.TextSecondary),
			Muted = Ui.Hex(palette.TextMuted),
			Accent = Ui.Hex(palette.Accent),
			Type = function(token: string?): string
				return Ui.Hex(Theme.TypeToken(types, token))
			end,
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

	--- The theme picker's sample line in `theme`'s syntax colors.
	const function themeSample(theme: Theme.Palette): string
		const syntax = theme.Syntax
		const colors: { [string]: Color3 } = {
			Command = syntax.Command,
			Operator = syntax.Operator,
			String = syntax.String,
			Number = syntax.Number,
			Flag = syntax.Flag,
			Variable = syntax.Variable,
			Comment = syntax.Comment,
		}
		const parts: { string } = {}
		for _, token in THEME_SAMPLE do
			table.insert(parts, `<font color="{Ui.Hex(colors[token[2]])}">{Ui.Escape(token[1])}</font>`)
		end
		return table.concat(parts, " ")
	end

	const function getCommand(name: string): Types.Command?
		return shell.Registry:GetCommand(name)
	end

	--- Commands listed under `current` in the left column: recently run ones first, then its group.
	const function otherCommands(current: Types.Command?): { Types.Command }
		const list: { Types.Command } = {}
		const seen: { [Types.Command]: true } = {}
		if current then
			seen[current] = true
		end
		const function add(command: Types.Command?)
			if command and not seen[command] and not command.Hidden and host.CanSee(command) then
				seen[command] = true
				table.insert(list, command)
			end
		end
		const history = host.History()
		for index = #history, math.max(1, #history - 50), -1 do
			if #list >= CONTEXT_COMMANDS then
				return list
			end
			const word = history[index]:match("^%s*([^%s;|&]+)")
			if word then
				add(getCommand(word))
			end
		end
		if current and current.Group then
			const sameGroup: { Types.Command } = {}
			for _, command in shell.Registry:GetCommands() do
				if command.Group == current.Group then
					table.insert(sameGroup, command)
				end
			end
			table.sort(sameGroup, function(a: Types.Command, b: Types.Command): boolean
				return a.Name < b.Name
			end)
			for _, command in sameGroup do
				if #list >= CONTEXT_COMMANDS then
					break
				end
				add(command)
			end
		end
		return list
	end

	const function placeholderText(): string
		const place = host.PlaceName()
		return if place ~= "" then `Type a command  ·  {place}` else PLACEHOLDER
	end

	-- Panel ----------------------------------------------------------------------------------------------------
	const function placePanel()
		const dock = bar.GetDock()
		panel.Place(bar.Rect(), dock == "float", dock == "bottom", bar.FloorY(), bar.CeilingY())
		toasts.SetTop(if touch and visible and dock == "top" then bar.Rect().Y + bar.Rect().Height + 8 else nil)
	end

	const function sheetHeight(): number
		const text = sheetBox.Text
		const measured = Ui.Measure(text, metrics.Mono, Ui.Fonts.Mono)
		return math.min(measured.Y + 70, panel.MaxHeight())
	end

	local updateHint: () -> ()

	--- Decides what the panel shows and how tall it is.
	const function refreshPanel()
		local mode: PanelMode = "none"
		if not visible then
			mode = "none"
		elseif dialog.IsOpen() then
			mode = "dialog"
		elseif sheetOpen then
			mode = "sheet"
		elseif picker.IsOpen() then
			mode = "picker"
		elseif assistActive then
			mode = "assist"
		elseif logShown and log.Count() > 0 then
			mode = "log"
		end
		panelMode = mode
		assist.Frame.Visible = mode == "assist" or mode == "picker"
		log.Frame.Visible = mode == "log"
		dialog.Frame.Visible = mode == "dialog"
		sheet.Visible = mode == "sheet"
		local height = 0
		if mode == "assist" or mode == "picker" then
			assist.SetWidth(panel.Width())
			assist.SetLimit(panel.MaxHeight())
			height = assist.DesiredHeight()
		elseif mode == "log" then
			height = if logExpanded then math.min(log.ContentHeight(), panel.MaxHeight()) else log.TailHeight()
			unseen = false
		elseif mode == "dialog" then
			dialog.SetWidth(panel.Width())
			height = dialog.DesiredHeight()
		elseif mode == "sheet" then
			height = sheetHeight()
		end
		if mode == "none" or height <= 0 then
			panel.Hide()
		else
			panel.SetHeight(height)
			panel.Show()
		end
		input.SetLog(mode == "log", unseen)
		updateHint()
	end

	-- Suggestions --------------------------------------------------------------------------------------------
	const function hideSuggestions()
		assistActive = false
		selected = nil
		explicitNavigation = false
		refreshPanel()
	end

	const function suggestModel(current: Completion.CompletionResult, index: number?): Model.Assist
		const signature = current.Signature
		const command = if signature then Model.FindCommand(getCommand, signature.Command) else nil
		const others = if current.Context == "Command" or current.Context == "Subcommand" then {}
			else otherCommands(command)
		contextList = {}
		if command then
			table.insert(contextList, command)
		end
		for _, other in others do
			table.insert(contextList, other)
		end
		return Model.Suggest({
			Result = current,
			Selected = index,
			Diagnostic = diagnostic,
			GetCommand = getCommand,
			Others = others,
			Colors = modelColors(),
		})
	end

	const function presentSuggestions(current: Completion.CompletionResult, highlightIndex: number?)
		const index = highlightIndex or (if #current.Suggestions > 0 then 1 else nil)
		selected = index
		const model = suggestModel(current, index)
		if model.Left == nil and model.Details == nil and model.Right == nil then
			assistActive = false
			refreshPanel()
			return
		end
		const opening = panelMode ~= "assist"
		assistActive = true
		assist.SetWidth(panel.Width())
		assist.Set(model, opening)
		refreshPanel()
	end

	-- Hint -------------------------------------------------------------------------------------------------------
	const function keys(list: { string }, text: string?): InputBar.Hint
		return { Keys = list, Text = text }
	end

	const function message(text: string, level: Types.Level): InputBar.Hint
		return { Text = text, Level = level }
	end

	updateHint = function()
		if not visible then
			return
		end
		local hint: InputBar.Hint? = nil
		if dialog.IsOpen() then
			hint = if dialog.Kind() == "confirm" then keys({ "Y", "N" }) else keys({ "Enter" }, "to confirm")
		elseif sheetOpen then
			hint = keys({ "Ctrl", "C" }, "to copy")
		elseif picker.IsOpen() then
			hint = keys({ "Enter" }, "to choose")
		elseif host.IsRunning() then
			hint = keys({ "Ctrl", "C" }, "to stop")
		else
			const text = input.GetText()
			const current = result
			const canComplete = current ~= nil and #current.Suggestions > 0
			const runnable = evaluation ~= nil and evaluation.Ok
			const failing = diagnostic ~= nil and diagnostic.Severity == "error"
			-- A word being typed with completions offers Tab; otherwise Enter for a valid line, then the error.
			const offerTab = (canComplete and assistActive and current ~= nil and current.Partial ~= "")
				or (canComplete and not runnable and not failing)
			if text == "" then
				hint = if host.IsConnected() then keys({ "Tab" }, "to browse") else message("offline", "warning")
			elseif offerTab then
				hint = keys({ "Tab" }, "to autocomplete")
			elseif runnable then
				hint = keys({ "Enter" }, "to run")
			elseif diagnostic and failing then
				hint = message(diagnostic.Message, "error")
			end
		end
		input.SetHint(hint)
	end

	-- Updates ----------------------------------------------------------------------------------------------
	const function update()
		updateQueued = false
		if picker.IsOpen() then
			return
		end
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
			-- A missing argument the caret is heading towards is not a mistake yet (until Enter was refused).
			if item.Code == "missing" and cursor >= item.Span.Start and rejectedText ~= text then
				return true
			end
			if lenient == nil then
				return false
			end
			return item.Span.Start >= lenient.Start and item.Span.End <= lenient.End
		end
		input.SetRich(highlightText(text, evaluation, ghost, lenient))

		-- Validation state of the prompt icon / run button.
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
		local nearest: Types.Diagnostic? = nil
		if evaluation then
			for _, item in evaluation.Diagnostics do
				if (item.Severity == "error" or item.Severity == "warning") and not excused(item) then
					if item.Span.Start <= cursor and cursor <= item.Span.End then
						nearest = item
						break
					end
					if nearest == nil then
						nearest = item
					end
				end
			end
		end
		diagnostic = nearest

		-- Suggestions (a Tab cycle keeps showing the list it is cycling through).
		const cycle = tabCycle
		if cycle and cycle.Text == text and cycle.Cursor == cursor then
			presentSuggestions(cycle.Result, cycle.Index)
			return
		end
		tabCycle = nil
		if current == nil or (text == "" and not forceOpen) or dismissedText == text then
			presentedText = nil
			hideSuggestions()
			return
		end
		-- Re-rendering the same line and caret (a theme change, a stray caret event) keeps the keyboard selection.
		const sameLine = text == presentedText and cursor == presentedCursor
		const keep = sameLine and explicitNavigation and selected or nil
		if keep == nil then
			explicitNavigation = false
		end
		presentedText = text
		presentedCursor = cursor
		presentSuggestions(current, keep)
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

	local previousText = ""
	local previousCursor = 1

	--- Programmatic edit (completion, history, undo): records undo and refreshes.
	const function setText(text: string, cursor: number?, recordUndo: boolean?)
		if recordUndo ~= false then
			pushUndo(input.GetText(), input.GetCursor(), true)
		end
		input.SetText(text, cursor)
		previousText = input.GetText()
		previousCursor = input.GetCursor()
		queueUpdate()
	end

	input.Changed:Connect(
		function(text: string, cursor: number)
			-- Swallow the activation key's character typed into the box while opening/closing.
			const pending = stripChar
			if pending and os.clock() < stripUntil and text:sub(cursor - #pending, cursor - 1) == pending then
				stripChar = nil
				const position = cursor - #pending
				input.SetText(text:sub(1, position - 1) .. text:sub(cursor), position)
				return
			end
			-- A picker filters with the bar's text.
			if picker.IsOpen() then
				input.SetRich(Ui.Escape(text))
				picker.SetQuery(text)
				return
			end
			-- `?` on an empty line opens help.
			if previousText == "" and text == "?" then
				input.SetText("", 1)
				logShown = true
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
		if not picker.IsOpen() then
			queueUpdate()
		end
	end)

	local acceptSuggestion: (index: number, fromTab: boolean) -> ()

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
		const originalCursor = input.GetCursor()
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
		if fromTab and #current.Suggestions > 1 then
			const cycle = tabCycle
			tabCycle = {
				Text = previousText,
				Cursor = previousCursor,
				OriginalText = if cycle then cycle.OriginalText else text,
				OriginalCursor = if cycle then cycle.OriginalCursor else originalCursor,
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
		if current == nil or #current.Suggestions == 0 or not assistActive then
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
				const rest = text:sub(math.max(cursor, replace.Start))
				setText(before .. prefix .. rest, #before + #prefix + 1)
				return
			end
		end
		const index = if selected and (explicitNavigation or direction > 0) then selected
			elseif direction > 0 then 1
			else #current.Suggestions
		acceptSuggestion(index, true)
	end

	--- Moves the highlight through the suggestions (the details follow it).
	const function moveSelection(delta: number)
		const current = result
		if current == nil or #current.Suggestions == 0 then
			return
		end
		if not assistActive then
			presentSuggestions(current, nil)
		end
		const count = #current.Suggestions
		const base = if explicitNavigation and selected then selected else (if delta > 0 then 0 else count + 1)
		selected = (base + delta - 1) % count + 1
		explicitNavigation = true
		assist.SetSelected(assist.Focus(), selected)
		assist.SetDetails(suggestModel(current, selected).Details)
		refreshPanel()
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
				if not visible or dialog.IsOpen() or sheetOpen then
					return
				end
				if input.IsFocused() then
					return
				end
				input.Focus()
			end
		end)
	end

	--- Shows a prompt in the panel and yields for the answer. The input gives up focus meanwhile, so Enter and
	--- Y/N answer the prompt instead of submitting the line being typed.
	const function ask(request: Types.PromptRequest): Types.PromptAnswer
		if input.IsFocused() then
			input.Release()
		end
		asking += 1
		const answer = dialog.Ask(request)
		asking -= 1
		refreshPanel()
		refocus()
		return answer
	end

	const function submit()
		const text = input.Sync()
		if Util.Trim(text) == "" then
			return
		end
		const evaluated = evaluate(text)
		if evaluated and not evaluated.Ok and rejectedText ~= text then
			-- First Enter on an invalid line shakes (and shows why); a second Enter sends it anyway (the server decides).
			rejectedText = text
			input.Shake()
			queueUpdate()
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
		assistActive = false
		selected = nil
		explicitNavigation = false
		logShown = true
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

	local closePicker: (chosen: boolean) -> ()

	const function show()
		if visible or not enabled then
			return
		end
		visible = true
		bar.Open()
		placePanel()
		unlock.Modal = host.Activation.UnlocksMouse
		unlock.Visible = true
		setBlur(true)
		queueUpdate()
		refreshPanel()
		refocus()
		toggled:Fire(true)
	end

	const function hide()
		if not visible then
			return
		end
		closePicker(false)
		sheetOpen = false
		visible = false
		assistActive = false
		logShown = false
		logExpanded = false
		if input.IsFocused() then
			input.Release()
		end
		unlock.Visible = false
		setBlur(false)
		refreshPanel()
		bar.Close()
		placePanel()
		toggled:Fire(false)
	end

	const function toggle()
		if visible then
			hide()
		else
			show()
		end
	end

	--- Shows the latest output (or, `expanded`, the whole log), or hides it when it is already showing that way.
	const function toggleLog(expanded: boolean)
		if panelMode == "log" and logExpanded == expanded then
			logShown = false
			logExpanded = false
		else
			logShown = true
			logExpanded = expanded
			-- Typing: put the suggestions away for this line.
			if input.GetText() ~= "" then
				dismissedText = input.GetText()
			end
			assistActive = false
			log.ScrollToBottom(false)
		end
		refreshPanel()
	end

	-- Overlays -------------------------------------------------------------------------------------------------
	const function closeSheet()
		if not sheetOpen then
			return
		end
		sheetOpen = false
		if sheetBox:IsFocused() then
			sheetBox:ReleaseFocus()
		end
		refreshPanel()
		refocus()
	end

	const function openSheet(title: string, text: string)
		if not visible then
			show()
		end
		sheetOpen = true
		sheetTitle.Text = title
		sheetBox.Text = text
		sheetBox.TextSize = metrics.Mono
		refreshPanel()
		task.defer(function()
			sheetBox:CaptureFocus()
			sheetBox.SelectionStart = 1
			sheetBox.CursorPosition = #sheetBox.Text + 1
		end)
	end

	--- Switches the bar to a picker: its text filters the entries, Enter chooses, Esc goes back to the line.
	const function openPicker(options: Picker.OpenOptions)
		if not visible then
			show()
		end
		if not picker.IsOpen() then
			pickerSaved = { Text = input.GetText(), Cursor = input.GetCursor() }
		end
		assistActive = false
		tabCycle = nil
		historyIndex = nil
		input.SetMode("search")
		input.SetState("idle")
		input.SetPlaceholder(options.Placeholder)
		const query = options.Query or ""
		input.SetText(query)
		input.SetRich(Ui.Escape(query))
		previousText = query
		previousCursor = #query + 1
		picker.Open(options)
		refocus()
	end

	closePicker = function(chosen: boolean)
		if picker.IsOpen() then
			picker.Close(chosen)
		end
	end

	picker.Changed:Connect(function()
		if picker.IsOpen() then
			assist.SetWidth(panel.Width())
			assist.Set(picker.Model(), not pickerShown)
			pickerShown = true
			refreshPanel()
			return
		end
		pickerShown = false
		input.SetMode("command")
		input.SetPlaceholder(placeholderText())
		const saved = pickerSaved
		pickerSaved = nil
		if saved then
			input.SetText(saved.Text, saved.Cursor)
			previousText = saved.Text
			previousCursor = saved.Cursor
		end
		queueUpdate()
		refreshPanel()
	end)

	const function escape()
		if sheetOpen then
			closeSheet()
		elseif picker.IsOpen() then
			closePicker(false)
			refocus()
		elseif dialog.IsOpen() then
			dialog.Cancel()
			refocus()
		elseif panelMode == "assist" then
			dismissedText = input.GetText()
			hideSuggestions()
			refocus()
		elseif panelMode == "log" then
			logShown = false
			logExpanded = false
			refreshPanel()
			refocus()
		elseif input.GetText() ~= "" then
			setText("", 1)
			refocus()
		else
			hide()
		end
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
			logShown = true
			host.Execute(Command.FullName(command))
		else
			setText(Command.FullName(command) .. " ")
		end
		refocus()
	end

	local openSettings: () -> ()
	local openThemes: () -> ()
	local applyTheme: () -> ()

	const function openHistorySearch()
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
				Item = { Label = line, Icon = "history", Tint = "muted" },
				Search = line,
				Details = function(): Model.Details
					const word = line:match("^%s*([^%s;|&]+)")
					const command = if word then getCommand(word) else nil
					return {
						Title = highlightText(line, evaluate(line), nil),
						Description = if command then command.Description else nil,
						Sections = {
							{ Heading = "Keys", Rich = "Enter edits it · Shift+Enter runs it" },
						},
					}
				end,
				Choose = function(alternate: boolean)
					if alternate then
						logShown = true
						host.Execute(line)
					else
						setText(line)
					end
					refocus()
				end,
			})
		end
		openPicker({ Placeholder = "Search history…", Entries = entries, Query = input.GetText() })
	end

	const function openPalette()
		const entries: { Picker.Entry } = {}
		const colors = modelColors()
		const commands: { Types.Command } = {}
		for _, command in shell.Registry:GetCommands() do
			if not command.Hidden and host.CanSee(command) then
				table.insert(commands, command)
			end
		end
		table.sort(commands, function(a: Types.Command, b: Types.Command): boolean
			return a.Name < b.Name
		end)
		for _, command in commands do
			table.insert(entries, {
				Item = {
					Label = command.Name,
					Subtitle = command.Description,
					Icon = command.Icon or (if command._isAlias then "alias" else "command"),
					Deprecated = command.Deprecated ~= nil,
				},
				Search = `{command.Name} {Util.Join(command.Aliases, " ")} {command.Description}`,
				Details = function(): Model.Details
					return Model.CommandDetails(command, colors)
				end,
				Choose = function(alternate: boolean)
					insertCommand(command, alternate)
				end,
			})
		end
		const function action(label: string, icon: string, description: string, run: () -> ())
			table.insert(entries, {
				Item = { Label = label, Subtitle = description, Icon = icon },
				Search = `{label} {description}`,
				Details = function(): Model.Details
					return { Title = `<b>{Ui.Escape(label)}</b>`, Description = description, Sections = {} }
				end,
				Choose = function()
					run()
				end,
			})
		end
		action("Themes…", "theme", "Browse the themes with a live preview", function()
			task.defer(openThemes)
		end)
		action("Settings…", "setting", "Browse and change console settings", function()
			task.defer(openSettings)
		end)
		action("History search", "history", "Search previously run commands (Ctrl+R)", function()
			task.defer(openHistorySearch)
		end)
		action("Show the log", "log", "Every command and its output (Ctrl+H)", function()
			toggleLog(true)
			refocus()
		end)
		action("Clear the log", "close", "Remove every row from the log (Ctrl+L)", function()
			log.Clear()
			refocus()
		end)
		action("Export the log", "copy", "Show the log as copyable text", function()
			openSheet("Log", log.Export())
		end)
		openPicker({ Placeholder = "Search commands and actions…", Entries = entries })
	end

	openThemes = function()
		const original = palette.Name
		const entries: { Picker.Entry } = {}
		local current = 1
		for index, name in Theme.Names() do
			const theme = Theme.Get(name)
			if name == original then
				current = index
			end
			const description = theme.Description or "Custom theme"
			table.insert(entries, {
				Item = {
					Label = name,
					Subtitle = description,
					Detail = if name == original then "current" elseif theme.Dark then "dark" else "light",
					Swatches = { theme.Window, theme.Accent, theme.Text, theme.Syntax.String },
				},
				Search = `{name} {description} {if theme.Dark then "dark" else "light"}`,
				Details = function(): Model.Details
					return {
						Title = `<b>{Ui.Escape(name)}</b>`,
						Description = description,
						Sections = {
							{
								Heading = "Preview",
								Rich = themeSample(theme),
								Mono = true,
							},
						},
						Swatches = {
							theme.Window,
							theme.Elevated,
							theme.Accent,
							theme.Text,
							theme.Success,
							theme.Warning,
							theme.Error,
							theme.Info,
						},
					}
				end,
				Preview = function()
					if palette.Name ~= name then
						palette = theme
						applyTheme()
					end
				end,
				Choose = function()
					settings:Set("theme", name)
					refocus()
				end,
			})
		end
		openPicker({
			Placeholder = "Search themes…",
			Entries = entries,
			Selected = current,
			OnCancel = function()
				const saved = Theme.Get(Theme.Find(settings:GetString("theme")) or "Midnight")
				if palette ~= saved then
					palette = saved
					applyTheme()
				end
			end,
		})
	end

	openSettings = function()
		const entries: { Picker.Entry } = {}
		for _, entry in settings:List() do
			table.insert(entries, {
				Item = { Label = entry.Key, Subtitle = entry.Description, Detail = entry.Value, Icon = "setting" },
				Search = `{entry.Key} {entry.Description}`,
				Details = function(): Model.Details
					return {
						Title = `<b>{Ui.Escape(entry.Key)}</b>`,
						Description = entry.Description,
						Sections = {
							{ Heading = "Value", Rich = Ui.Escape(entry.Value) },
							{ Heading = "Change", Rich = Ui.Escape(`config {entry.Key} <value>`), Mono = true },
						},
					}
				end,
				Choose = function()
					if entry.Value == "true" or entry.Value == "false" then
						settings:SetText(entry.Key, if entry.Value == "true" then "false" else "true")
						task.defer(openSettings)
					elseif entry.Key == "theme" then
						task.defer(openThemes)
					else
						setText(`config {entry.Key} `)
						refocus()
					end
				end,
			})
		end
		openPicker({ Placeholder = "Search settings…", Entries = entries })
	end

	-- Theme & metrics ------------------------------------------------------------------------------------------
	local opacity = settings:GetNumber("opacity")

	applyTheme = function()
		bar.SetTheme(palette)
		input.SetTheme(palette)
		panel.SetTheme(palette)
		assist.SetTheme(palette)
		log.SetTheme(palette)
		dialog.SetTheme(palette)
		toasts.SetTheme(palette)
		touchSurface.SetTheme(palette)
		touchIcon.TextColor3 = palette.Accent
		sheetTitle.TextColor3 = palette.Text
		sheetScroll.BackgroundColor3 = palette.Input
		sheetScroll.ScrollBarImageColor3 = palette.TextMuted
		sheetBox.TextColor3 = palette.Text
		if picker.IsOpen() then
			assist.Set(picker.Model(), false)
			refreshPanel()
		else
			queueUpdate()
		end
	end

	const function applyOpacity()
		bar.SetOpacity(opacity)
		panel.SetOpacity(opacity)
		toasts.SetOpacity(opacity)
		touchSurface.SetOpacity(opacity)
	end

	const function applyMetrics()
		bar.SetMetrics(metrics)
		input.SetMetrics(metrics)
		panel.SetMetrics(metrics)
		assist.SetMetrics(metrics)
		log.SetMetrics(metrics)
		dialog.SetMetrics(metrics)
		toasts.SetMetrics(metrics)
		const touchSize = if metrics.Touch then 52 else 44
		touchSurface.Holder.Size = UDim2.fromOffset(touchSize, touchSize)
		touchIcon.TextSize = metrics.IconSize + 2
		sheetTitle.TextSize = metrics.TextMd
		placePanel()
		refreshPanel()
		queueUpdate()
	end

	const function refreshTouchButton()
		const available = UserInputService.TouchEnabled or UserInputService.GamepadEnabled
		touchSurface.Holder.Visible = host.Activation.TouchButton and available and enabled
	end

	const function readLayout()
		bar.SetFloat(parseLayout(settings:GetString("layout"), root.AbsoluteSize))
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
			-- Phones get a bar docked to the top (clear of the on-screen keyboard) instead of a floating one.
			bar.SetDock(if dock == "top" or dock == "bottom" then dock elseif touch then "top" else "float")
		elseif key == "layout" then
			readLayout()
		elseif key == "blur" then
			setBlur(visible)
		elseif key == "timestamps" then
			log.SetTimestamps(settings:GetBoolean("timestamps"))
		elseif key == "opacity" then
			opacity = settings:GetNumber("opacity")
			applyOpacity()
		elseif key == "maxLog" then
			log.SetLimit(settings:GetNumber("maxLog"))
		elseif key == "ghostText" then
			queueUpdate()
		elseif key == "font" then
			input.SetFont(if settings:GetString("font") == "mono" then "mono" else "sans")
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
	readLayout()
	for _, key in { "theme", "dock", "timestamps", "opacity", "maxLog", "font" } do
		applySetting(key)
	end

	bar.Dragged:Connect(
		function()
			-- The floating position is saved before the dock so that applying the dock sees it.
			const position = bar.GetFloat()
			if bar.GetDock() == "float" and position then
				settings:Set("layout", string.format("f:%.3f,%.3f", position.X, position.Y))
			end
			if bar.GetDock() ~= settings:GetString("dock") then
				settings:Set("dock", bar.GetDock())
			end
		end
	)
	bar.Moved:Connect(function()
		placePanel()
		refreshPanel()
	end)

	-- Wiring --------------------------------------------------------------------------------------------------
	input.FocusChanged:Connect(function(focused: boolean)
		bar.SetFocused(focused)
	end)
	log.ContentResized:Connect(function()
		if panelMode == "log" then
			refreshPanel()
		end
	end)
	log.Activated:Connect(function(entry: Format.Entry)
		openSheet(if entry.Kind == "echo" then "Command" else "Output", entry.Plain)
	end)
	assist.Resized:Connect(function()
		if panelMode == "assist" or panelMode == "picker" then
			refreshPanel()
		end
	end)
	assist.Hovered:Connect(
		function(which: Assist.Which, index: number)
			-- Hover previews: Enter still runs the line unless the keyboard picked a suggestion.
			if picker.IsOpen() then
				picker.Select(index)
				return
			end
			const current = result
			if current and current.Suggestions[index] then
				selected = index
				assist.SetSelected(which, index)
				assist.SetDetails(suggestModel(current, index).Details)
				refreshPanel()
			end
		end
	)
	assist.Activated:Connect(
		function(which: Assist.Which, index: number)
			if picker.IsOpen() then
				picker.Choose(false, index)
				return
			end
			if which == assist.Focus() then
				acceptSuggestion(index, false)
			elseif which == "left" and index > 1 then
				-- Another command from the context column: start that one instead.
				const command = contextList[index]
				if command then
					setText(Command.FullName(command) .. " ")
				end
			end
			refocus()
		end
	)
	dialog.Presented:Connect(function()
		updateHint()
		refreshPanel()
	end)
	dialog.Finished:Connect(function()
		refreshPanel()
	end)
	input.Submitted:Connect(submit)
	input.StopRequested:Connect(function()
		host.Cancel()
	end)
	input.LogToggled:Connect(function()
		toggleLog(true)
		refocus()
	end)
	input.MultilinePaste:Connect(
		function(pasted: string)
			-- Only text with two or more non-empty lines gets here (see InputText).
			const lines = InputText.CountLines(pasted)
			task.spawn(function()
				const answer = ask({
					Kind = "confirm",
					Title = "Run pasted script?",
					Message = `The pasted text has {lines} lines. Run them as a script?`,
				})
				if answer == "yes" then
					logShown = true
					host.Execute(pasted)
				end
			end)
		end
	)
	input.FocusLost:Connect(
		function(enterPressed: boolean)
			-- While a prompt is up, Enter answers it (the input releases focus when a prompt opens; this guards the
			-- frame in between).
			if not visible or asking > 0 or dialog.IsOpen() then
				return
			end
			if enterPressed then
				if picker.IsOpen() then
					const modifiers = Keymap.Modifiers()
					picker.Choose(modifiers.Shift)
				elseif explicitNavigation and selected and result and assistActive then
					acceptSuggestion(selected, false)
				else
					submit()
				end
				refocus()
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

	--- A single-line TextBox may move its caret on Up/Down (to the start/end of the line). Completion depends on the
	--- caret, so it is put back where it was, now and after the TextBox has handled the key.
	const function keepCursor(position: number)
		const expected = input.GetText()
		input.SetCursor(position)
		task.defer(function()
			if input.GetText() == expected and input.TextBox.CursorPosition ~= position then
				input.SetCursor(position)
			end
		end)
	end

	const function handleAction(action: Keymap.Action): boolean
		const text = input.GetText()
		const cursor = input.GetCursor()
		if picker.IsOpen() then
			-- The bar is a search field: arrows and Tab move through the entries.
			if action == "Up" or action == "AcceptBackward" then
				picker.Move(-1)
				keepCursor(cursor)
				return true
			elseif action == "Down" or action == "Accept" then
				picker.Move(1)
				keepCursor(cursor)
				return true
			elseif action == "Palette" or action == "HistorySearch" then
				closePicker(false)
				return true
			end
			return false
		end
		if action == "Accept" or action == "AcceptBackward" then
			onTab(if action == "Accept" then 1 else -1)
			return true
		elseif action == "AcceptGhost" then
			if cursor == #text + 1 and result and Completion.Ghost(result) then
				const ghost = Completion.Ghost(result) :: string
				setText(text .. ghost, #text + #ghost + 1)
				return true
			end
			return false
		elseif action == "Up" or action == "Down" then
			const delta = if action == "Up" then -1 else 1
			if historyIndex == nil and text ~= "" and assistActive then
				moveSelection(delta)
				keepCursor(cursor)
			else
				navigateHistory(delta)
				keepCursor(#input.GetText() + 1)
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
		elseif action == "ToggleLog" then
			toggleLog(true)
			return true
		elseif action == "ClearLog" then
			log.Clear()
			refreshPanel()
			return true
		elseif action == "DeleteWord" then
			const start = wordLeft(text, cursor)
			setText(text:sub(1, start - 1) .. text:sub(cursor), start)
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
			-- Show the help in the panel instead of the suggestions for this line.
			if text ~= "" then
				dismissedText = text
			end
			assistActive = false
			logShown = true
			host.Execute(if hint then `help {hint.Command}` else "help")
			return true
		end
		return false
	end

	--- Whether a screen point lies on the console (bar, panel or touch button).
	const function onConsole(point: Vector2): boolean
		if Ui.Contains(bar.Holder, point) then
			return true
		end
		if panel.IsOpen() and Ui.Contains(panel.Holder, point) then
			return true
		end
		return touchSurface.Holder.Visible and Ui.Contains(touchSurface.Holder, point)
	end

	table.insert(
		connections,
		UserInputService.InputBegan:Connect(
			function(inputObject: InputObject, processed: boolean)
				const kind = inputObject.UserInputType
				if kind == Enum.UserInputType.MouseButton1 or kind == Enum.UserInputType.Touch then
					-- Click-away hiding. InputObject.Position and AbsolutePosition share a space (both exclude the top
					-- bar inset).
					if visible and host.Activation.HideOnLostFocus and not dialog.IsOpen() then
						const point = Vector2.new(inputObject.Position.X, inputObject.Position.Y)
						if not onConsole(point) then
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
				const typingElsewhere = focusedBox ~= nil and focusedBox ~= input.TextBox and focusedBox ~= sheetBox
				-- With a modifier held the key types a character (Shift+` is ~), so it does not toggle.
				const modifiers = Keymap.Modifiers()
				const modified = modifiers.Shift or modifiers.Ctrl or modifiers.Alt
				if isActivationKey(key) and not typingElsewhere and not (modified and focusedBox ~= nil) then
					if not dialog.IsOpen() then
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
				if sheetOpen then
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
				const action = Keymap.Match(host.Keymap, key, Keymap.Modifiers())
				if focusedBox ~= input.TextBox then
					-- Keys while the console is open but unfocused: its shortcuts still work, and typing refocuses the
					-- input (unless the player is typing somewhere else, such as the chat).
					if typingElsewhere then
						return
					end
					if action == "Palette" or action == "ToggleLog" or action == "HistorySearch" or action == "ClearLog" then
						handleAction(action)
					end
					if not processed then
						refocus()
					end
					return
				end
				if action then
					handleAction(action)
				end
			end
		)
	)
	table.insert(connections, UserInputService:GetPropertyChangedSignal("TouchEnabled"):Connect(refreshTouchButton))
	table.insert(connections, UserInputService.GamepadConnected:Connect(refreshTouchButton))

	-- Initial state --------------------------------------------------------------------------------------------
	const function refreshTitle()
		if not picker.IsOpen() then
			input.SetPlaceholder(placeholderText())
		end
	end
	refreshTitle()
	applyTheme()
	applyOpacity()
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
			if not (entry.Kind == "progress" and log.UpdateProgress(entry)) then
				log.Add(entry)
			end
			if panelMode ~= "log" then
				unseen = true
			end
			refreshPanel()
		end,
		AddEcho = function(text: string)
			log.Add(echoEntry(text))
			log.ScrollToBottom(true)
			refreshPanel()
		end,
		Notify = function(text: string, level: Types.Level?)
			toasts.Show(text, level)
		end,
		Prompt = function(request: Types.PromptRequest): Types.PromptAnswer
			show()
			return ask(request)
		end,
		SetRunning = function(_running: boolean)
			queueUpdate()
			updateHint()
		end,
		Clear = function()
			log.Clear()
			refreshPanel()
		end,
		OpenPalette = openPalette,
		OpenThemes = function()
			openThemes()
		end,
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
		RefreshTitle = refreshTitle,
		Toggled = toggled,
		Destroy = function()
			for _, connection in connections do
				connection:Disconnect()
			end
			setBlur(false)
			bar.Destroy()
			panel.Destroy()
			assist.Destroy()
			log.Destroy()
			dialog.Destroy()
			input.Destroy()
			toasts.Destroy()
			gui:Destroy()
		end,
	}
	return table.freeze(console)
end

return table.freeze(ConsoleModule)
