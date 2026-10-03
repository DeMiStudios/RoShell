--!strict
--[[
	`RoShell.Client`: the player's console. Runs `ClientRun` commands locally, forwards server commands through the
	transport, keeps history/aliases/binds/variables/settings (persisted per user on the server), and drives the
	console UI.

		local client = RoShell.Client.new({ ActivationKeys = { Enum.KeyCode.F2 } })
		client.Registry:RegisterDefaultCommands()
		client.Registry:RegisterCommandsIn(ReplicatedStorage.Commands)
		client:Start()
]]

--// Imports
const CancelToken = require("./Shared/CancelToken")
const Command = require("./Shared/Command")
const Constants = require("./Shared/Constants")
const Host = require("@self/Host")
const Keymap = require("@self/UI/Keymap")
const Keys = require("./Shared/Keys")
const Platform = require("./Shared/Platform")
const Settings = require("@self/Settings")
const Shell = require("./Shared/Shell")
const Signal = require("./Shared/Signal")
const Transport = require("@self/Transport")
const Types = require("./Shared/Types")
const Util = require("./Shared/Util")

--// Types
export type ClientOptions = {
	--- Namespace (must match the server's). Defaults to "RoShell".
	Name: string?,
	--- Create the console UI (default true). Without it the client still runs commands from code and binds.
	Interface: boolean?,
	--- Keys that toggle the console (default F2 and `).
	ActivationKeys: { Enum.KeyCode }?,
	--- Require pressing an activation key 5 times quickly to open the console the first time.
	MashToEnable: boolean?,
	--- Hide the console when clicking outside of it (default true).
	HideOnLostFocus: boolean?,
	--- Free the mouse while the console is open (first-person games).
	ActivationUnlocksMouse: boolean?,
	--- Show a floating button to open the console on touch/gamepad devices (default true).
	TouchButton: boolean?,
	--- Title shown in the console header.
	PlaceName: string?,
	--- Remapped console keys (whole actions are replaced), e.g. { Palette = { { Key = Enum.KeyCode.P, Ctrl = true } } }.
	Keymap: Keymap.Keymap?,
	--- Initial values for settings the player has not changed (e.g. { theme = "Graphite" }).
	Settings: { [string]: string | number | boolean }?,
	Locale: { [string]: string }?,
	Platform: Types.PlatformInfo?,
}

export type Client = {
	read Shell: Types.Shell,
	read Registry: Types.Registry,
	read Dispatcher: Types.Dispatcher,
	read Locale: Types.Locale,
	read Settings: Settings.Settings,
	--- Fires when the console opens or closes.
	read Toggled: Types.Signal<boolean>,
	--- Fires after each line typed in the console finishes.
	read Executed: Types.Signal<string, Types.RunResult>,
	--- Connects to the server, loads user data and creates the UI. Returns the client for chaining.
	read Start: (self: Client) -> Client,
	--- Runs a command line from code (no echo, not added to history).
	read Run: (self: Client, text: string, options: Types.RunOptions?) -> Types.RunResult,
	--- Runs a command line as if typed in the console (echo + history).
	read Execute: (self: Client, text: string) -> (),
	read Show: (self: Client) -> (),
	read Hide: (self: Client) -> (),
	read Toggle: (self: Client) -> (),
	read IsVisible: (self: Client) -> boolean,
	read SetEnabled: (self: Client, enabled: boolean) -> (),
	read SetActivationKeys: (self: Client, keys: { Enum.KeyCode }) -> (),
	read SetActivationUnlocksMouse: (self: Client, enabled: boolean) -> (),
	read SetMashToEnable: (self: Client, enabled: boolean) -> (),
	read SetHideOnLostFocus: (self: Client, enabled: boolean) -> (),
	read SetPlaceName: (self: Client, name: string) -> (),
	read SetTheme: (self: Client, name: string) -> boolean,
	--- Handles custom events sent with `server:SendEvent(player, name, payload)` / `ctx:SendEvent(...)`.
	read OnEvent: (self: Client, name: string, handler: (payload: unknown) -> ()) -> Types.Connection,
	read GetHistory: (self: Client) -> { string },
	_options: ClientOptions,
	_transport: Transport.ClientTransport,
	_console: Host.Console?,
	_activation: Host.ActivationOptions,
	_placeName: string,
	_history: { string },
	_aliases: { [string]: string },
	_binds: { [string]: string },
	_frecency: { [string]: number },
	_running: Types.CancelToken?,
	_started: boolean,
	_bindConnection: RBXScriptConnection?,
}

--// Constants
const MAX_HISTORY = 500
const SAVE_DELAY = 2

--// Helpers

const function readStringMap(value: unknown): { [string]: string }
	const map: { [string]: string } = {}
	if type(value) == "table" then
		for key, item in pairs(value) do
			if type(key) == "string" and type(item) == "string" then
				map[key] = item
			end
		end
	end
	return map
end

const function readStringList(value: unknown): { string }
	const list: { string } = {}
	if type(value) == "table" then
		for _, item in pairs(value) do
			if type(item) == "string" then
				table.insert(list, item)
			end
		end
	end
	return list
end

--// Client class
const ClientClass = {}
ClientClass.__index = ClientClass

--- Debounced persistence of a user data key.
const pendingSaves: { [Client]: { [string]: boolean } } = setmetatable({}, { __mode = "k" })

const function save(self: Client, key: string)
	local keys = pendingSaves[self]
	if keys == nil then
		keys = {}
		pendingSaves[self] = keys
	end
	if keys[key] then
		return
	end
	keys[key] = true
	task.delay(SAVE_DELAY, function()
		keys[key] = nil
		if key == "History" then
			self._transport.SaveUserData("History", self._history)
		elseif key == "Aliases" then
			self._transport.SaveUserData("Aliases", self._aliases)
		elseif key == "Binds" then
			self._transport.SaveUserData("Binds", self._binds)
		elseif key == "Variables" then
			self._transport.SaveUserData(
				"Variables",
				self.Shell:GetSession(self.Shell.Platform.GetLocalPlayer()).Variables
			)
		elseif key == "Settings" then
			self._transport.SaveUserData("Settings", self.Settings:Serialize())
		end
	end)
end

const function emit(self: Client, block: Types.Block)
	const console = self._console
	if console then
		console.AddBlock(block)
	elseif block.Kind == "text" then
		print(`[{self.Shell.Name}] {block.Text}`)
	end
end

const function prompt(self: Client, request: Types.PromptRequest): Types.PromptAnswer
	const console = self._console
	if console then
		return console.Prompt(request)
	end
	return nil
end

function ClientClass.Run(self: Client, text: string, options: Types.RunOptions?): Types.RunResult
	return self.Dispatcher:Run({
		Text = text,
		Executor = self.Shell.Platform.GetLocalPlayer(),
		Options = options,
		OnBlock = function(block: Types.Block)
			emit(self, block)
		end,
		OnPrompt = function(request: Types.PromptRequest): Types.PromptAnswer
			return prompt(self, request)
		end,
	})
end

function ClientClass.Execute(self: Client, text: string)
	const trimmed = Util.Trim(text)
	if trimmed == "" then
		return
	end
	if self._history[#self._history] ~= trimmed then
		table.insert(self._history, trimmed)
		while #self._history > MAX_HISTORY do
			table.remove(self._history, 1)
		end
		save(self, "History")
	end
	const console = self._console
	if console then
		console.AddEcho(trimmed)
	end
	const token = CancelToken.new()
	self._running = token
	if console then
		console.SetRunning(true)
	end
	task.spawn(function()
		const result = self.Dispatcher:Run({
			Text = trimmed,
			Executor = self.Shell.Platform.GetLocalPlayer(),
			Options = { IsHuman = true },
			Token = token,
			OnBlock = function(block: Types.Block)
				emit(self, block)
			end,
			OnPrompt = function(request: Types.PromptRequest): Types.PromptAnswer
				return prompt(self, request)
			end,
		})
		if self._running == token then
			self._running = nil
			const current = self._console
			if current then
				current.SetRunning(false)
			end
		end
		if result.Cancelled then
			emit(self, { Kind = "text", Text = self.Locale:Get("run.cancelled"), Level = "muted" })
		end
		self.Executed:Fire(trimmed, result)
	end)
end

function ClientClass.Show(self: Client)
	if self._console then
		self._console.Show()
	end
end

function ClientClass.Hide(self: Client)
	if self._console then
		self._console.Hide()
	end
end

function ClientClass.Toggle(self: Client)
	if self._console then
		self._console.Toggle()
	end
end

function ClientClass.IsVisible(self: Client): boolean
	const console = self._console
	return console ~= nil and console.IsVisible()
end

function ClientClass.SetEnabled(self: Client, enabled: boolean)
	if self._console then
		self._console.SetEnabled(enabled)
	end
end

function ClientClass.SetActivationKeys(self: Client, keys: { Enum.KeyCode })
	self._activation.Keys = table.clone(keys)
	if self._console then
		self._console.RefreshActivation()
	end
end

function ClientClass.SetActivationUnlocksMouse(self: Client, enabled: boolean)
	self._activation.UnlocksMouse = enabled
	if self._console then
		self._console.RefreshActivation()
	end
end

function ClientClass.SetMashToEnable(self: Client, enabled: boolean)
	self._activation.MashToEnable = enabled
	if self._console then
		self._console.RefreshActivation()
	end
end

function ClientClass.SetHideOnLostFocus(self: Client, enabled: boolean)
	self._activation.HideOnLostFocus = enabled
end

function ClientClass.SetPlaceName(self: Client, name: string)
	self._placeName = name
	if self._console then
		self._console.RefreshTitle()
	end
end

function ClientClass.SetTheme(self: Client, name: string): boolean
	const console = self._console
	if console then
		return console.SetTheme(name)
	end
	self.Settings:Set("theme", name)
	return true
end

function ClientClass.OnEvent(self: Client, name: string, handler: (payload: unknown) -> ()): Types.Connection
	return self._transport.CustomEvent:Connect(function(eventName: string, payload: unknown)
		if eventName == name then
			handler(payload)
		end
	end)
end

function ClientClass.GetHistory(self: Client): { string }
	return table.clone(self._history)
end

--- Builds the console API used by client commands (clear, theme, bind, history, ...).
const function consoleApi(self: Client): Keys.ConsoleApi
	return table.freeze({
		Clear = function()
			if self._console then
				self._console.Clear()
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
			if self._console then
				self._console.OpenPalette()
			end
		end,
		SetTheme = function(name: string): boolean
			return self:SetTheme(name)
		end,
		GetThemes = function(): { string }
			const console = self._console
			return if console then console.GetThemes() else {}
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
			save(self, "History")
		end,
		Bind = function(keybind: string, line: string): (boolean, string?)
			self._binds[keybind] = line
			save(self, "Binds")
			return true, nil
		end,
		Unbind = function(keybind: string): boolean
			if self._binds[keybind] == nil then
				return false
			end
			self._binds[keybind] = nil
			save(self, "Binds")
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
			save(self, "Aliases")
		end,
		RemoveAlias = function(name: string)
			self._aliases[name] = nil
			save(self, "Aliases")
		end,
		SaveVariables = function()
			save(self, "Variables")
		end,
		SetSetting = function(key: string, value: string): (boolean, string?)
			const ok, err = self.Settings:SetText(key, value)
			if ok then
				save(self, "Settings")
			end
			return ok, err
		end,
		GetSettings = function(): { { Key: string, Value: string, Description: string } }
			return self.Settings:List()
		end,
		Notify = function(text: string, level: Types.Level?)
			if self._console then
				self._console.Notify(text, level)
			end
		end,
	})
end

--- Runs bound command lines when their keys are pressed (outside text boxes).
const function connectBinds(self: Client)
	const UserInputService = game:GetService("UserInputService")
	self._bindConnection = UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if processed or UserInputService:GetFocusedTextBox() then
			return
		end
		const ctrl = UserInputService:IsKeyDown(Enum.KeyCode.LeftControl)
			or UserInputService:IsKeyDown(Enum.KeyCode.RightControl)
		const shift = UserInputService:IsKeyDown(Enum.KeyCode.LeftShift)
			or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)
		const alt = UserInputService:IsKeyDown(Enum.KeyCode.LeftAlt)
			or UserInputService:IsKeyDown(Enum.KeyCode.RightAlt)
		const prefix = (if ctrl then "Ctrl+" else "")
			.. (if shift then "Shift+" else "")
			.. (if alt then "Alt+" else "")
		const name = if input.UserInputType == Enum.UserInputType.Keyboard or input.UserInputType.Name:match("^Gamepad") then input.KeyCode.Name
			else input.UserInputType.Name
		const line = self._binds[prefix .. name]
		if line then
			task.spawn(function()
				self:Run(line, { IsHuman = false })
			end)
		end
	end)
end

function ClientClass.Start(self: Client): Client
	if self._started then
		return self
	end
	self._started = true
	const shell = self.Shell

	const handshake = self._transport.Connect(30)
	if handshake == nil then
		warn(`[{Constants.Name}] Could not reach the server; server commands are unavailable.`)
	else
		const visible: { [string]: true } = {}
		for _, name in handshake.Visible do
			visible[name] = true
		end
		shell.Permissions._visibility = visible
		self._transport.VisibilityChanged:Connect(function(names: { string })
			const updated: { [string]: true } = {}
			for _, name in names do
				updated[name] = true
			end
			shell.Permissions._visibility = updated
		end)

		const data = handshake.UserData
		self._history = readStringList(data.History)
		self._aliases = readStringMap(data.Aliases)
		self._binds = readStringMap(data.Binds)
		const variables = shell:GetSession(shell.Platform.GetLocalPlayer()).Variables
		for key, value in readStringMap(data.Variables) do
			variables[key] = value
		end
		const saved = Settings.new(data.Settings, self._options.Settings)
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
		save(self, "Settings")
	end)

	if self._options.Interface ~= false then
		const ConsoleModule = require("@self/UI/Console")
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
				const running = self._running
				if running then
					running:Cancel("Cancelled by user")
					return true
				end
				return false
			end,
			IsRunning = function(): boolean
				return self._running ~= nil
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
		const console = ConsoleModule.new(host)
		self._console = console
		console.Toggled:Connect(function(visible: boolean)
			self.Toggled:Fire(visible)
		end)
	end

	self._transport.Announced:Connect(function(text: string, level: Types.Level, from: string?)
		const console = self._console
		if console then
			console.Notify(if from then `{text}  — {from}` else text, level)
		end
		emit(self, { Kind = "text", Text = if from then `{from}: {text}` else text, Level = level })
	end)
	self._transport.Notified:Connect(function(block: Types.Block)
		emit(self, block)
	end)
	connectBinds(self)

	-- AutoExec lines of registered commands.
	for _, command in shell.Registry:GetCommands() do
		for _, line in command.AutoExec do
			task.spawn(function()
				self:Run(line, { IsHuman = false })
			end)
		end
	end
	return self
end

table.freeze(ClientClass)

--// Client module
const ClientModule = {}

--- Creates the client shell. Register commands, then call `:Start()`.
function ClientModule.new(options: ClientOptions?): Client
	const opts: ClientOptions = options or {}
	const platform = opts.Platform or Platform.Roblox()
	assert(platform.GetLocalPlayer() ~= nil, "RoShell.Client must be created on a client")
	const shell = Shell.new({
		IsServer = false,
		IsClient = true,
		Platform = platform,
		Options = { Name = opts.Name },
		Locale = opts.Locale,
	})
	const transport = Transport.new(shell.Name, shell.Registry)
	shell._transport = transport
	const settings = Settings.new(nil, opts.Settings)
	const client: Client = setmetatable(
		{
			Shell = shell,
			Registry = shell.Registry,
			Dispatcher = shell.Dispatcher,
			Locale = shell.Locale,
			Settings = settings,
			Toggled = Signal.new(),
			Executed = Signal.new(),
			_options = opts,
			_transport = transport,
			_console = nil :: Host.Console?,
			_activation = {
				Keys = opts.ActivationKeys or { Enum.KeyCode.F2, Enum.KeyCode.Backquote },
				MashToEnable = opts.MashToEnable == true,
				HideOnLostFocus = opts.HideOnLostFocus ~= false,
				UnlocksMouse = opts.ActivationUnlocksMouse == true,
				TouchButton = opts.TouchButton ~= false,
			},
			_placeName = opts.PlaceName or "",
			_history = {},
			_aliases = {},
			_binds = {},
			_frecency = {},
			_running = nil :: Types.CancelToken?,
			_started = false,
			_bindConnection = nil :: RBXScriptConnection?,
		},
		ClientClass
	)
	shell.Registry:AddEnv(Keys.Console, consoleApi(client))
	return client
end

return table.freeze(ClientModule)
