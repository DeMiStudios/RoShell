--!strict
--[[
	The client half of `RoShell.new`: the player's console. Runs `ClientRun` commands locally, forwards server
	commands through the transport, registers the commands the server describes (whose code stays there), keeps
	history, aliases, binds, variables and settings (persisted per user on the server), and drives the console UI.
--]]

--// Services
const HttpService = game:GetService("HttpService")
const UserInputService = game:GetService("UserInputService")

--// Imports
const CancelToken = require(script.Parent.Shared.CancelToken)
const Command = require(script.Parent.Shared.Command)
const Constants = require(script.Parent.Shared.Constants)
const Host = require(script.Host)
const Keymap = require(script.UI.Keymap)
const Keys = require(script.Parent.Shared.Keys)
const Lexer = require(script.Parent.Shared.Lexer)
const Manifest = require(script.Parent.Shared.Manifest)
const Net = require(script.Parent.Shared.Net)
const Registry = require(script.Parent.Shared.Registry)
const Settings = require(script.Settings)
const Shell = require(script.Parent.Shared.Shell)
const Signal = require(script.Parent.Shared.Signal)
const Transport = require(script.Transport)
const Types = require(script.Parent.Shared.Types)
const Util = require(script.Parent.Shared.Util)

--// Types
export type ClientOptions = {
	Commands: (Instance | { Instance })?,
	DefaultCommands: (boolean | { string })?,
	Name: string?,
	StudioBypass: boolean?,
	Interface: boolean?,
	ActivationKeys: { Enum.KeyCode }?,
	MashToEnable: boolean?,
	HideOnLostFocus: boolean?,
	ActivationUnlocksMouse: boolean?,
	TouchButton: boolean?,
	PlaceName: string?,
	Keymap: Keymap.Keymap?,
	Settings: { [string]: string | number | boolean }?,
	Locale: { [string]: string }?,
	Platform: Types.PlatformInfo,
}

type ClientData = {
	read Shell: Types.Shell,
	read Settings: Settings.Settings,
	read Toggled: Types.Signal<boolean>,
	read Executed: Types.Signal<string, Types.RunResult>,
	_options: ClientOptions,
	_transport: Transport.ClientTransport,
	_console: Host.Console?,
	_activation: Host.ActivationOptions,
	_placeName: string,
	_history: { string },
	_aliases: { [string]: string },
	_binds: { [string]: string },
	_frecency: { [string]: number },
	-- Commands started from the console that have not finished, oldest first.
	_running: { Types.CancelToken },
	-- User data keys waiting to be saved (saves are debounced).
	_pendingSaves: { [string]: true },
	-- The last command descriptions applied (an update that changes nothing is skipped).
	_manifest: string?,
	_started: boolean,
}

--// Constants
const MAX_HISTORY = 500
-- History entries saved for the next session (network payloads keep at most 256 entries per table).
const SAVED_HISTORY = 200
const SAVE_DELAY = 2

--// Functions
const function readStringMap(value: unknown): { [string]: string }
	const map: { [string]: string } = {}
	if typeof(value) == "table" then
		for key, item in value do
			if typeof(key) == "string" and typeof(item) == "string" then
				map[key] = item
			end
		end
	end
	return map
end

const function readStringList(value: unknown): { string }
	const list: { string } = {}
	if typeof(value) == "table" then
		for _, item in value do
			if typeof(item) == "string" then
				table.insert(list, item)
			end
		end
	end
	return list
end

-- The history entry for `text`: one line (the input is single-line, so a pasted script is kept as the equivalent
-- `a; b` line that Up can bring back), or nil when nothing is left.
const function historyLine(text: string): string?
	const line = Lexer.ToLine(Util.Trim(text))
	return if line == "" then nil else line
end

const function visibilitySet(names: { string }): { [string]: true }
	const set: { [string]: true } = {}
	for _, name in names do
		set[name] = true
	end
	return set
end

--// Client Class
const Client = {}
Client.__index = Client

export type Client = setmetatable<ClientData, typeof(Client)>

--- Creates the client half of a shell. `RoShell.new` calls this on clients.
function Client.new(options: ClientOptions): Client
	const shell = Shell.new({
		IsServer = false,
		IsClient = true,
		Platform = options.Platform,
		Options = { Name = options.Name, StudioBypass = options.StudioBypass },
		Locale = options.Locale,
	})
	const transport = Transport.new(shell.Name, shell.Registry)
	shell._transport = transport
	const data: ClientData = {
		Shell = shell,
		Settings = Settings.new(nil, options.Settings),
		Toggled = Signal.new(),
		Executed = Signal.new(),
		_options = options,
		_transport = transport,
		_console = nil,
		_activation = {
			Keys = options.ActivationKeys or { Enum.KeyCode.F2, Enum.KeyCode.Backquote },
			MashToEnable = options.MashToEnable == true,
			HideOnLostFocus = options.HideOnLostFocus ~= false,
			UnlocksMouse = options.ActivationUnlocksMouse == true,
			TouchButton = options.TouchButton ~= false,
		},
		_placeName = options.PlaceName or "",
		_history = {},
		_aliases = {},
		_binds = {},
		_frecency = {},
		_running = {},
		_pendingSaves = {},
		_manifest = nil,
		_started = false,
	}
	const self = setmetatable(data, Client)
	shell.Registry:AddEnv(Keys.Console, self:_consoleApi())
	return self
end

--- Connects to the server, registers the commands, loads user data and creates the UI.
function Client.Start(self: Client)
	if self._started then
		return
	end
	self._started = true
	const shell = self.Shell

	const handshake = self._transport.Connect(30)
	Registry.Setup(shell.Registry, {
		DefaultCommands = self._options.DefaultCommands,
		Commands = self._options.Commands,
	})
	if handshake == nil then
		warn(`[{Constants.Name}] Could not reach the server; server commands are unavailable.`)
	else
		for _, container in handshake.Commands do
			Registry.Include(shell.Registry, container)
		end
		self:_applyManifest(handshake.Remote)
		shell.Permissions._visibility = visibilitySet(handshake.Visible)
		self._transport.VisibilityChanged:Connect(function(names: { string }, remote: { Net.CommandInfo })
			self:_applyManifest(remote)
			shell.Permissions._visibility = visibilitySet(names)
		end)

		const userData = handshake.UserData
		self._history = {}
		for _, entry in readStringList(userData.History) do
			const line = historyLine(entry)
			if line and self._history[#self._history] ~= line then
				table.insert(self._history, line)
			end
		end
		self._aliases = readStringMap(userData.Aliases)
		self._binds = readStringMap(userData.Binds)
		const variables = shell:GetSession(shell.Platform.GetLocalPlayer()).Variables
		for key, value in readStringMap(userData.Variables) do
			variables[key] = value
		end
		const saved = Settings.new(userData.Settings, self._options.Settings)
		for key, value in saved:Serialize() do
			self.Settings:Set(key, value)
		end
	end

	for name, body in self._aliases do
		if shell.Registry:GetCommand(name) == nil then
			shell.Registry:RegisterCommand(Command.Alias(name, body))
		end
	end
	self.Settings.Changed:Connect(function()
		self:_save("Settings")
	end)

	if self._options.Interface ~= false then
		self:_createConsole()
	end

	self._transport.Announced:Connect(function(text: string, level: Types.Level, from: string?)
		const console = self._console
		if console then
			console.Notify(if from then `{text} (from {from})` else text, level)
		end
		self:_emit({ Kind = "text", Text = if from then `{from}: {text}` else text, Level = level })
	end)
	self._transport.Notified:Connect(function(block: Types.Block)
		self:_emit(block)
	end)
	self:_connectBinds()

	-- AutoExec lines of registered commands.
	for _, command in shell.Registry:GetCommands() do
		for _, line in command.AutoExec do
			task.spawn(function()
				self:Run(line, { IsHuman = false })
			end)
		end
	end
end

--- Runs a command line from code (no echo, not added to history).
function Client.Run(self: Client, text: string, options: Types.RunOptions?): Types.RunResult
	return self.Shell.Dispatcher:Run({
		Text = text,
		Executor = self.Shell.Platform.GetLocalPlayer(),
		Options = options,
		OnBlock = function(block: Types.Block)
			self:_emit(block)
		end,
		OnPrompt = function(request: Types.PromptRequest): Types.PromptAnswer
			return self:_prompt(request)
		end,
	})
end

--- Runs a command line as if typed in the console (echo and history).
function Client.Execute(self: Client, text: string)
	const trimmed = Util.Trim(text)
	if trimmed == "" then
		return
	end
	const line = historyLine(trimmed)
	if line and self._history[#self._history] ~= line then
		table.insert(self._history, line)
		while #self._history > MAX_HISTORY do
			table.remove(self._history, 1)
		end
		self:_save("History")
	end
	const console = self._console
	if console then
		console.AddEcho(trimmed)
	end
	const token = CancelToken.new()
	table.insert(self._running, token)
	if console then
		console.SetRunning(true)
	end
	task.spawn(function()
		const result = self.Shell.Dispatcher:Run({
			Text = trimmed,
			Executor = self.Shell.Platform.GetLocalPlayer(),
			Options = { IsHuman = true },
			Token = token,
			OnBlock = function(block: Types.Block)
				self:_emit(block)
			end,
			OnPrompt = function(request: Types.PromptRequest): Types.PromptAnswer
				return self:_prompt(request)
			end,
		})
		const index = table.find(self._running, token)
		if index then
			table.remove(self._running, index)
		end
		const current = self._console
		if current and #self._running == 0 then
			current.SetRunning(false)
		end
		if result.Canceled then
			self:_emit({ Kind = "text", Text = self.Shell.Locale:Get("run.canceled"), Level = "muted" })
		end
		self.Executed:Fire(trimmed, result)
	end)
end

function Client.Show(self: Client)
	const console = self._console
	if console then
		console.Show()
	end
end

function Client.Hide(self: Client)
	const console = self._console
	if console then
		console.Hide()
	end
end

function Client.Toggle(self: Client)
	const console = self._console
	if console then
		console.Toggle()
	end
end

--- Opens the console (when it is closed) and then the command palette.
function Client.OpenPalette(self: Client)
	const console = self._console
	if console then
		console.Show()
		-- A disabled console stays closed, and so does its palette.
		if console.IsVisible() then
			console.OpenPalette()
		end
	end
end

--- Opens the console with `text` on the line, the caret at its end and its suggestions showing.
function Client.SetInput(self: Client, text: string)
	const console = self._console
	if console then
		console.SetInput(text)
	end
end

function Client.IsVisible(self: Client): boolean
	const console = self._console
	return console ~= nil and console.IsVisible()
end

function Client.SetEnabled(self: Client, enabled: boolean)
	const console = self._console
	if console then
		console.SetEnabled(enabled)
	end
end

function Client.SetActivationKeys(self: Client, keys: { Enum.KeyCode })
	self._activation.Keys = table.clone(keys)
	self:_refreshActivation()
end

function Client.SetActivationUnlocksMouse(self: Client, enabled: boolean)
	self._activation.UnlocksMouse = enabled
	self:_refreshActivation()
end

function Client.SetMashToEnable(self: Client, enabled: boolean)
	self._activation.MashToEnable = enabled
	self:_refreshActivation()
end

function Client.SetHideOnLostFocus(self: Client, enabled: boolean)
	self._activation.HideOnLostFocus = enabled
end

function Client.SetPlaceName(self: Client, name: string)
	self._placeName = name
	const console = self._console
	if console then
		console.RefreshTitle()
	end
end

function Client.SetTheme(self: Client, name: string): boolean
	const console = self._console
	if console then
		return console.SetTheme(name)
	end
	self.Settings:Set("theme", name)
	return true
end

function Client.OnEvent(self: Client, name: string, handler: (payload: unknown) -> ()): Types.Connection
	return self._transport.CustomEvent:Connect(function(eventName: string, payload: unknown)
		if eventName == name then
			handler(payload)
		end
	end)
end

function Client.GetHistory(self: Client): { string }
	return table.clone(self._history)
end

-- Registers the commands the server described, unless they are the same as last time.
function Client._applyManifest(self: Client, remote: { Net.CommandInfo })
	const ok, encoded = pcall(HttpService.JSONEncode, HttpService, remote)
	const key = if ok then encoded else nil
	if key ~= nil and key == self._manifest then
		return
	end
	self._manifest = key
	Manifest.Apply(self.Shell, remote)
end

function Client._refreshActivation(self: Client)
	const console = self._console
	if console then
		console.RefreshActivation()
	end
end

-- Debounced persistence of a user data key.
function Client._save(self: Client, key: string)
	if self._pendingSaves[key] then
		return
	end
	self._pendingSaves[key] = true
	task.delay(SAVE_DELAY, function()
		self._pendingSaves[key] = nil
		const transport = self._transport
		if key == "History" then
			const history = self._history
			transport.SaveUserData(
				"History",
				table.move(history, math.max(1, #history - SAVED_HISTORY + 1), #history, 1, {})
			)
		elseif key == "Aliases" then
			transport.SaveUserData("Aliases", self._aliases)
		elseif key == "Binds" then
			transport.SaveUserData("Binds", self._binds)
		elseif key == "Variables" then
			transport.SaveUserData("Variables", self.Shell:GetSession(self.Shell.Platform.GetLocalPlayer()).Variables)
		elseif key == "Settings" then
			transport.SaveUserData("Settings", self.Settings:Serialize())
		end
	end)
end

function Client._emit(self: Client, block: Types.Block)
	const console = self._console
	if console then
		console.AddBlock(block)
	elseif block.Kind == "text" then
		print(`[{self.Shell.Name}] {block.Text}`)
	end
end

function Client._prompt(self: Client, request: Types.PromptRequest): Types.PromptAnswer
	const console = self._console
	if console then
		return console.Prompt(request)
	end
	return nil
end

-- The console API used by client commands (clear, theme, bind, history, ...).
function Client._consoleApi(self: Client): Keys.ConsoleApi
	return table.freeze({
		Clear = function()
			const console = self._console
			if console then
				console.Clear()
			end
		end,
		Show = function()
			self:Show()
		end,
		Hide = function()
			self:Hide()
		end,
		Toggle = function()
			self:Toggle()
		end,
		OpenPalette = function()
			self:OpenPalette()
		end,
		OpenThemes = function()
			const console = self._console
			if console then
				console.OpenThemes()
			end
		end,
		SetTheme = function(name: string): boolean
			return self:SetTheme(name)
		end,
		GetThemes = function(): { string }
			const console = self._console
			return if console then console.GetThemes() else {}
		end,
		DescribeTheme = function(name: string): string?
			const console = self._console
			return if console then console.DescribeTheme(name) else nil
		end,
		GetTheme = function(): string
			const console = self._console
			return if console then console.GetTheme() else self.Settings:GetString("theme")
		end,
		ExportLog = function(): string
			const console = self._console
			return if console then console.ExportLog() else ""
		end,
		GetHistory = function(): { string }
			return table.clone(self._history)
		end,
		ClearHistory = function()
			table.clear(self._history)
			self:_save("History")
		end,
		Bind = function(keybind: string, line: string): (boolean, string?)
			self._binds[keybind] = line
			self:_save("Binds")
			return true, nil
		end,
		Unbind = function(keybind: string): boolean
			if self._binds[keybind] == nil then
				return false
			end
			self._binds[keybind] = nil
			self:_save("Binds")
			return true
		end,
		GetBinds = function(): { { Key: string, Command: string } }
			const list: { { Key: string, Command: string } } = {}
			for key, line in self._binds do
				table.insert(list, { Key = key, Command = line })
			end
			table.sort(list, function(a: { Key: string, Command: string }, b: { Key: string, Command: string }): boolean
				return a.Key < b.Key
			end)
			return list
		end,
		SaveAlias = function(name: string, body: string)
			self._aliases[name] = body
			self:_save("Aliases")
		end,
		RemoveAlias = function(name: string)
			self._aliases[name] = nil
			self:_save("Aliases")
		end,
		SaveVariables = function()
			self:_save("Variables")
		end,
		SetSetting = function(key: string, value: string): (boolean, string?)
			const ok, err = self.Settings:SetText(key, value)
			if ok then
				self:_save("Settings")
			end
			return ok, err
		end,
		GetSettings = function(): { { Key: string, Value: string, Description: string } }
			return self.Settings:List()
		end,
		SettingType = Settings.TypeOf,
		Notify = function(text: string, level: Types.Level?)
			const console = self._console
			if console then
				console.Notify(text, level)
			end
		end,
	})
end

function Client._createConsole(self: Client)
	const shell = self.Shell
	const Console = require(script.UI.Console)
	const host: Host.ConsoleHost = {
		Shell = shell,
		Settings = self.Settings,
		Activation = self._activation,
		Keymap = Keymap.Merge(self._options.Keymap),
		PlaceName = function(): string
			return self._placeName
		end,
		IsConnected = function(): boolean
			return self._transport.IsConnected()
		end,
		Execute = function(text: string)
			self:Execute(text)
		end,
		Cancel = function(): boolean
			-- The most recently started command that is still running.
			const running = self._running[#self._running]
			if running then
				running:Cancel("Canceled by user")
				return true
			end
			return false
		end,
		IsRunning = function(): boolean
			return #self._running > 0
		end,
		History = function(): { string }
			return self._history
		end,
		CanSee = function(command: Types.Command): boolean
			return shell.Permissions:CanSee(shell.Platform.GetLocalPlayer(), command)
		end,
		Boost = function(kind: string, text: string): number
			return math.min(60, (self._frecency[kind .. ":" .. text] or 0) * 12)
		end,
		Accepted = function(kind: string, text: string)
			const key = kind .. ":" .. text
			self._frecency[key] = (self._frecency[key] or 0) + 1
		end,
	}
	const console = Console.new(host)
	self._console = console
	console.Toggled:Connect(function(visible: boolean)
		self.Toggled:Fire(visible)
	end)
end

-- Runs bound command lines when their keys are pressed (outside text boxes).
function Client._connectBinds(self: Client)
	UserInputService.InputBegan:Connect(
		function(input: InputObject, processed: boolean)
			if processed or UserInputService:GetFocusedTextBox() then
				return
			end
			-- Cmd counts as Ctrl, as in the `bind` command's key names.
			const ctrl = UserInputService:IsKeyDown(Enum.KeyCode.LeftControl)
				or UserInputService:IsKeyDown(Enum.KeyCode.RightControl)
				or UserInputService:IsKeyDown(Enum.KeyCode.LeftMeta)
				or UserInputService:IsKeyDown(Enum.KeyCode.RightMeta)
			const shift = UserInputService:IsKeyDown(Enum.KeyCode.LeftShift)
				or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)
			const alt = UserInputService:IsKeyDown(Enum.KeyCode.LeftAlt)
				or UserInputService:IsKeyDown(Enum.KeyCode.RightAlt)
			const prefix = (if ctrl then "Ctrl+" else "")
				.. (if shift then "Shift+" else "")
				.. (if alt then "Alt+" else "")
			const name = if input.UserInputType == Enum.UserInputType.Keyboard
					or input.UserInputType.Name:match("^Gamepad") then input.KeyCode.Name
				else input.UserInputType.Name
			const line = self._binds[prefix .. name]
			if line then
				task.spawn(function()
					self:Run(line, { IsHuman = false })
				end)
			end
		end
	)
end

return table.freeze(Client)
