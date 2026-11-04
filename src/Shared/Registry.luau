--!strict
--[[
	The registry: commands (with aliases and subcommands), types, hooks, middleware, selectors, `$functions`,
	plugins, typed environment values and stores. Lookups are O(1) by lowercase name; registering N commands is
	O(N). Every change bumps `Version()` and fires `Changed`, which caches (completion index, UI) listen to, so
	commands and types can be hot-reloaded (`UnregisterCommand` + `RegisterCommand`).
--]]

--// Imports
const Command = require(script.Parent.Command)
const Signal = require(script.Parent.Signal)
const TypeBuilder = require(script.Parent.TypeBuilder)
const Types = require(script.Parent.Types)

--// Types
type Registry = Types.Registry

--- What servers and clients register on `Start` (their `DefaultCommands` and `Commands` options).
export type SetupOptions = {
	--- The built-in commands: true or nil (all), a list of groups, or false (none).
	DefaultCommands: (boolean | { string })?,
	--- Folders or ModuleScripts of commands.
	Commands: (Instance | { Instance })?,
}

--// Globals
-- Hooks declared with `Registry.Hooks`, so modules loaded by `RegisterHooksIn` are recognized without casts.
const knownHooks: { [unknown]: Types.CommandHooks } = setmetatable({}, { __mode = "k" })

--// Functions
const function insertSorted<T>(list: { { Priority: number } & T }, entry: { Priority: number } & T)
	local index = #list + 1
	for position, existing in list do
		if entry.Priority < existing.Priority then
			index = position
			break
		end
	end
	table.insert(list, index, entry)
end

const function removeEntry<T>(list: { T }, entry: T)
	const index = table.find(list, entry)
	if index then
		table.remove(list, index)
	end
end

const function bump(self: Registry, change: Types.RegistryChange)
	self._version += 1
	self.Changed:Fire(change)
end

const function warnMessage(message: string)
	const warnFunction: ((...unknown) -> ())? = (warn :: ((...unknown) -> ())?)
	if warnFunction then
		warnFunction(message)
	end
end

--// Registry Class
const Registry = {}
Registry.__index = Registry

function Registry.RegisterType(self: Registry, valueType: Types.Type<unknown>)
	const key = valueType.Name:lower()
	const existing = self._types[key]
	if existing then
		const index = table.find(self._typeList, existing)
		if index then
			table.remove(self._typeList, index)
		end
	end
	self._types[key] = valueType
	table.insert(self._typeList, valueType)
	bump(self, "types")
end

function Registry.RegisterTypes(self: Registry, valueTypes: { Types.Type<unknown> })
	for _, valueType in valueTypes do
		self:RegisterType(valueType)
	end
end

function Registry.GetType(self: Registry, name: string): Types.Type<unknown>?
	return self._types[name:lower()]
end

function Registry.GetTypes(self: Registry): { Types.Type<unknown> }
	return table.clone(self._typeList)
end

function Registry.RegisterCommand(self: Registry, command: Types.Command)
	const key = command.Name:lower()
	const existing = self._commands[key]
	if existing and existing ~= command then
		if command._isDefault and not existing._isDefault then
			-- A developer command already took this name; keep it.
			return
		end
		self:UnregisterCommand(existing.Name)
	end
	self._commands[key] = command
	for _, alias in command.Aliases do
		const aliasKey = alias:lower()
		const holder = self._commands[aliasKey]
		if holder == nil or holder._isDefault or holder == command then
			self._commands[aliasKey] = command
		else
			warnMessage(`[RoShell] Alias '{alias}' of '{command.Name}' is already taken by '{holder.Name}'`)
		end
	end
	if not table.find(self._commandList, command) then
		table.insert(self._commandList, command)
	end
	bump(self, "commands")
end

function Registry.RegisterCommands(self: Registry, commands: { Types.Command })
	for _, command in commands do
		self:RegisterCommand(command)
	end
end

--- Loads the commands returned by every ModuleScript in `container`. `fresh` requires clones (hot reload).
const function loadCommandsIn(
	self: Registry,
	container: Instance,
	filter: ((command: Types.Command) -> boolean)?,
	fresh: boolean
): number
	local loaded = 0
	const modules: { ModuleScript } = {}
	for _, descendant in container:GetDescendants() do
		if descendant:IsA("ModuleScript") then
			table.insert(modules, descendant)
		end
	end
	if container:IsA("ModuleScript") then
		table.insert(modules, 1, container)
	end
	for _, moduleScript in modules do
		const source = if fresh then moduleScript:Clone() else moduleScript
		if fresh then
			-- Relative requires inside the module resolve against its place in the tree.
			source.Parent = moduleScript.Parent
		end
		const ok, result = pcall(require, source)
		if fresh then
			source:Destroy()
		end
		if not ok then
			warnMessage(`[RoShell] Could not load commands from {moduleScript:GetFullName()}: {result}`)
			continue
		end
		const commands: { Types.Command } = {}
		const single = Command.Lookup(result)
		if single then
			table.insert(commands, single)
		elseif typeof(result) == "table" then
			for _, item in result do
				const found = Command.Lookup(item)
				if found then
					table.insert(commands, found)
				end
			end
		end
		for _, command in commands do
			if filter == nil or filter(command) then
				self:RegisterCommand(command)
				loaded += 1
			end
		end
	end
	return loaded
end

function Registry.RegisterCommandsIn(
	self: Registry,
	container: Instance,
	filter: ((command: Types.Command) -> boolean)?
)
	table.insert(self._containers, { Container = container, Filter = filter })
	loadCommandsIn(self, container, filter, false)
end

function Registry.ReloadCommands(self: Registry): number
	local count = 0
	for _, entry in self._containers do
		count += loadCommandsIn(self, entry.Container, entry.Filter, true)
	end
	return count
end

function Registry.RegisterDefaultCommands(self: Registry, filter: ({ string } | (command: Types.Command) -> boolean)?)
	self._defaultsRegistered = true
	-- Required lazily: the built-in commands depend on modules that depend on the registry.
	const BuiltInCommands = require(script.Parent.Parent.Commands)
	for _, command in BuiltInCommands do
		local include = true
		if typeof(filter) == "table" then
			include = command.Group ~= nil and table.find(filter, command.Group) ~= nil
		elseif typeof(filter) == "function" then
			include = filter(command)
		end
		if include then
			command._isDefault = true
			self:RegisterCommand(command)
		end
	end
end

function Registry.UnregisterCommand(self: Registry, name: string): boolean
	const command = self._commands[name:lower()]
	if command == nil then
		return false
	end
	for key, holder in table.clone(self._commands) do
		if holder == command then
			self._commands[key] = nil
		end
	end
	removeEntry(self._commandList, command)
	bump(self, "commands")
	return true
end

function Registry.GetCommand(self: Registry, name: string): Types.Command?
	return self._commands[name:lower()]
end

function Registry.GetCommands(self: Registry): { Types.Command }
	return table.clone(self._commandList)
end

function Registry.GetCommandNames(self: Registry, includeAliases: boolean?): { string }
	const names: { string } = {}
	for _, command in self._commandList do
		if command.Hidden then
			continue
		end
		table.insert(names, command.Name)
		if includeAliases then
			for _, alias in command.Aliases do
				table.insert(names, alias)
			end
		end
	end
	table.sort(names)
	return names
end

function Registry.RegisterHooks(self: Registry, hooks: Types.CommandHooks, priority: number?): () -> ()
	const order = priority or 0
	const entries: { () -> () } = {}
	const beforeRun = hooks.BeforeRun
	if beforeRun then
		const entry = { Priority = order, Hook = beforeRun }
		insertSorted(self._beforeRun, entry)
		table.insert(entries, function()
			removeEntry(self._beforeRun, entry)
		end)
	end
	const afterRun = hooks.AfterRun
	if afterRun then
		const entry = { Priority = order, Hook = afterRun }
		insertSorted(self._afterRun, entry)
		table.insert(entries, function()
			removeEntry(self._afterRun, entry)
		end)
	end
	const onError = hooks.OnError
	if onError then
		const entry = { Priority = order, Hook = onError }
		insertSorted(self._onError, entry)
		table.insert(entries, function()
			removeEntry(self._onError, entry)
		end)
	end
	return function()
		for _, remove in entries do
			remove()
		end
	end
end

function Registry.RegisterMiddleware(self: Registry, middleware: Types.Middleware, priority: number?): () -> ()
	const entry = { Priority = priority or 0, Middleware = middleware }
	insertSorted(self._middleware, entry)
	return function()
		removeEntry(self._middleware, entry)
	end
end

function Registry.RegisterSelector(self: Registry, valueType: Types.TypeInfo, selector: Types.Selector<unknown>)
	assert(selector.Prefix:sub(1, 1) == "@", "RoShell: registry selectors use an '@name:' prefix")
	const list = self._selectors[valueType.Id] or {}
	self._selectors[valueType.Id] = list
	table.insert(list, selector)
	bump(self, "types")
end

function Registry.GetSelectors(self: Registry, typeId: number): { Types.Selector<unknown> }
	return self._selectors[typeId] or {}
end

function Registry.RegisterFunction(self: Registry, definition: Types.FunctionDefinition)
	self._functions[definition.Name:lower()] = definition
	bump(self, "functions")
end

function Registry.GetFunction(self: Registry, name: string): Types.FunctionDefinition?
	return self._functions[name:lower()]
end

function Registry.GetFunctions(self: Registry): { Types.FunctionDefinition }
	const list: { Types.FunctionDefinition } = {}
	for _, definition in self._functions do
		table.insert(list, definition)
	end
	table.sort(list, function(a: Types.FunctionDefinition, b: Types.FunctionDefinition): boolean
		return a.Name < b.Name
	end)
	return list
end

function Registry.RegisterPlugin(self: Registry, plugin: Types.Plugin)
	for _, valueType in plugin.Types or {} do
		self:RegisterType(valueType)
	end
	for _, command in plugin.Commands or {} do
		self:RegisterCommand(command)
	end
	for _, definition in plugin.Functions or {} do
		self:RegisterFunction(definition)
	end
	if plugin.Hooks then
		self:RegisterHooks(plugin.Hooks)
	end
	for _, middleware in plugin.Middleware or {} do
		self:RegisterMiddleware(middleware)
	end
	for _, theme in plugin.Themes or {} do
		table.insert(self._themes, theme)
	end
	for name, renderer in plugin.Renderers or {} do
		self._renderers[name] = renderer
	end
	if plugin.Setup then
		-- Required lazily to avoid a load-time cycle (ShellDirectory is tiny and has no dependencies besides Types).
		const ShellDirectory = require(script.Parent.ShellDirectory)
		plugin.Setup(ShellDirectory.Expect(self._handle))
	end
	bump(self, "all")
end

function Registry.AddEnv<T>(self: Registry, key: Types.EnvKey<T>, value: T)
	key._set(self, value)
end

function Registry.GetEnv<T>(self: Registry, key: Types.EnvKey<T>): T?
	return key._get(self)
end

function Registry.GetStore(self: Registry, name: string): Types.Store
	const existing = self._stores[name]
	if existing then
		return existing
	end
	const store: Types.Store = {}
	self._stores[name] = store
	return store
end

function Registry.Version(self: Registry): number
	return self._version
end

function Registry.GetThemes(self: Registry): { Types.ThemeOptions }
	return table.clone(self._themes)
end

function Registry.RegisterTheme(self: Registry, options: Types.ThemeOptions)
	for index, existing in self._themes do
		if existing.Name == options.Name then
			table.remove(self._themes, index)
			break
		end
	end
	table.insert(self._themes, options)
	bump(self, "all")
end

function Registry.RegisterOutputRenderer(self: Registry, name: string, renderer: Types.OutputRenderer)
	self._renderers[name] = renderer
end

function Registry.GetOutputRenderer(self: Registry, name: string): Types.OutputRenderer?
	return self._renderers[name]
end

--- Requires every ModuleScript in `container` (and the container itself), returning the loaded results.
const function requireAll(container: Instance, what: string): { unknown }
	const modules: { ModuleScript } = {}
	if container:IsA("ModuleScript") then
		table.insert(modules, container)
	end
	for _, descendant in container:GetDescendants() do
		if descendant:IsA("ModuleScript") then
			table.insert(modules, descendant)
		end
	end
	const results: { unknown } = {}
	for _, moduleScript in modules do
		const ok, result = pcall(require, moduleScript)
		if ok then
			table.insert(results, result)
		else
			warnMessage(`[RoShell] Could not load {what} from {moduleScript:GetFullName()}: {result}`)
		end
	end
	return results
end

function Registry.RegisterTypesIn(self: Registry, container: Instance): number
	local count = 0
	for _, result in requireAll(container, "types") do
		const single = TypeBuilder.Lookup(result)
		if single then
			self:RegisterType(single)
			count += 1
		elseif typeof(result) == "table" then
			for _, item in result do
				const found = TypeBuilder.Lookup(item)
				if found then
					self:RegisterType(found)
					count += 1
				end
			end
		end
	end
	return count
end

function Registry.RegisterHooksIn(self: Registry, container: Instance): number
	local count = 0
	for _, result in requireAll(container, "hooks") do
		const hooks = knownHooks[result]
		if hooks then
			self:RegisterHooks(hooks)
			count += 1
		end
	end
	return count
end

--- Registers a container of commands unless it already is (the containers a server shares reach every client,
--- which may also list them itself).
function Registry.Include(registry: Registry, container: Instance)
	for _, entry in registry._containers do
		if entry.Container == container then
			return
		end
	end
	registry:RegisterCommandsIn(container)
end

--- Registers the built-in commands (unless `RegisterDefaultCommands` was already called, or `DefaultCommands` is
--- false) and the `Commands` containers.
function Registry.Setup(registry: Registry, options: SetupOptions)
	const defaults = options.DefaultCommands
	if defaults ~= false and not registry._defaultsRegistered then
		registry:RegisterDefaultCommands(if typeof(defaults) == "table" then defaults else nil)
	end
	const commands = options.Commands
	if commands == nil then
		return
	end
	const containers: { Instance } = if typeof(commands) == "Instance" then { commands } else commands
	for _, container in containers do
		Registry.Include(registry, container)
	end
end

--- Declares hooks in a module for `RegisterHooksIn`: `return RoShell.Hooks({ BeforeRun = ... })`.
function Registry.Hooks(hooks: Types.CommandHooks): Types.CommandHooks
	knownHooks[hooks] = hooks
	return hooks
end

--- Creates an empty registry for a shell.
function Registry.new(handle: Types.ShellHandle): Registry
	return setmetatable(
		{
			Changed = Signal.new(),
			_commands = {},
			_commandList = {},
			_types = {},
			_typeList = {},
			_functions = {},
			_selectors = {},
			_beforeRun = {},
			_afterRun = {},
			_onError = {},
			_middleware = {},
			_stores = {},
			_version = 0,
			_themes = {},
			_renderers = {},
			_handle = handle,
			_containers = {},
			_defaultsRegistered = false,
		},
		Registry
	)
end

return table.freeze(Registry)
