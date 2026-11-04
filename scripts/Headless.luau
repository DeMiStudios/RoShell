--!strict
--[[
	Headless loader: runs code that uses Roblox instance requires (`require(script.Parent.Shared.Fuzzy)`) under the
	standalone Luau CLI, which only resolves string requires and has no `script` global.

	`scripts/headless.py` mirrors the Rojo tree of `demo.project.json` and writes a program that loads this module
	with the tree and every script's source (`bash scripts/run.sh tests/cli.luau`). This module then:

	- builds a read-only proxy for each instance of the tree, with `Name`, `ClassName`, `Parent`, children by name
	  (`script.Parent.Shared`, `script.Parent["02-CustomTypes"]`), `FindFirstChild`, `WaitForChild`,
	  `GetChildren`, `GetFullName` and `IsA`. As in Roblox, a property wins over a child of the same name and a
	  missing member is an error;
	- runs each module with its own proxy as `script` and a `require` that takes a ModuleScript proxy, loads the
	  matching file once and returns the cached value afterwards. As in Roblox, a module must return exactly one
	  value, a module that failed to load fails again for every later require, and a require cycle is an error
	  naming the whole chain.

	Sources are compiled with `loadstring` under their file path, with `local script, require = ...;` put in front
	of their first line, so errors and tracebacks name the real file and line and the module's globals stay the
	standard library's. In Studio none of this runs: the same code requires the real instances.
--]]

--// Types
--- One instance of the mirrored tree, as `scripts/headless.py` writes it.
export type Node = {
	Name: string,
	ClassName: string,
	--- The file holding the script's source, relative to the repository (scripts only).
	Path: string?,
	Children: { Node }?,
}

--- How a script is loaded: its source text, or (in `--codegen` programs) its body compiled as a function.
export type Module = string | (...unknown) -> ...unknown

type Instance = {
	read Node: Node,
	read Parent: Instance?,
	read Children: { Instance },
}

type State = "loading" | "loaded" | "failed"

--// Constants
-- Put in front of every source, on its first line, so line numbers stay those of the file.
const PRELUDE = "local script, require = ...; "

--// Functions
const function fullName(instance: Instance): string
	const names: { string } = {}
	local current: Instance? = instance
	-- Like `Instance:GetFullName()`, the DataModel itself is not named.
	while current and current.Node.ClassName ~= "DataModel" do
		table.insert(names, 1, current.Node.Name)
		current = current.Parent
	end
	return table.concat(names, ".")
end

const function isA(node: Node, className: string): boolean
	const class = node.ClassName
	if className == class or className == "Instance" then
		return true
	elseif className == "LuaSourceContainer" then
		return class == "ModuleScript" or class == "Script" or class == "LocalScript"
	elseif className == "BaseScript" then
		return class == "Script" or class == "LocalScript"
	end
	return false
end

const function findChild(instance: Instance, name: string, recursive: boolean?): Instance?
	for _, child in instance.Children do
		if child.Node.Name == name then
			return child
		end
	end
	if recursive then
		for _, child in instance.Children do
			const found = findChild(child, name, true)
			if found then
				return found
			end
		end
	end
	return nil
end

--// Headless
const Headless = {}

--- Loads `entry` (a script's file path) from `tree` and runs it as the main program. `modules` maps every
--- script's file path to its source (or compiled body).
function Headless.Run(tree: Node, modules: { [string]: Module }, entry: string)
	-- Each instance has one proxy; the proxy is what code sees as `script` and passes to `require`.
	const proxies: { [Instance]: unknown } = {}
	const instances: { [unknown]: Instance } = {}
	const states: { [Instance]: State } = {}
	const results: { [Instance]: unknown } = {}
	-- Modules being loaded, outermost first (for the cycle error).
	const loading: { Instance } = {}
	local entries: { Instance } = {}

	local proxyOf: (instance: Instance) -> unknown

	const function MemberOf(instance: Instance, key: string): unknown
		const node = instance.Node
		if key == "Name" then
			return node.Name
		elseif key == "ClassName" then
			return node.ClassName
		elseif key == "Parent" then
			const parent = instance.Parent
			return if parent then proxyOf(parent) else nil
		elseif key == "FindFirstChild" then
			return function(_self: unknown, name: string, recursive: boolean?): unknown
				const child = findChild(instance, name, recursive)
				return if child then proxyOf(child) else nil
			end
		elseif key == "WaitForChild" then
			return function(_self: unknown, name: string, _timeout: number?): unknown
				const child = findChild(instance, name)
				if child == nil then
					-- Nothing is ever added to the tree, so waiting would never end.
					error(
						`Infinite yield: {name} is not a child of {fullName(instance)} (the headless tree is fixed)`,
						2
					)
				end
				return proxyOf(child)
			end
		elseif key == "GetChildren" then
			return function(_self: unknown): { unknown }
				const children: { unknown } = {}
				for _, child in instance.Children do
					table.insert(children, proxyOf(child))
				end
				return children
			end
		elseif key == "GetFullName" then
			return function(_self: unknown): string
				return fullName(instance)
			end
		elseif key == "IsA" then
			return function(_self: unknown, className: string): boolean
				return isA(node, className)
			end
		end
		const child = findChild(instance, key)
		if child == nil then
			error(`{key} is not a valid member of {node.ClassName} "{fullName(instance)}"`, 3)
		end
		return proxyOf(child)
	end

	const ProxyMetatable = {
		__index = function(proxy: unknown, key: unknown): unknown
			return MemberOf(instances[proxy], tostring(key))
		end,
		__newindex = function(proxy: unknown, key: unknown)
			error(`Cannot set {tostring(key)} of {fullName(instances[proxy])}: the headless tree is read-only`, 2)
		end,
		__tostring = function(proxy: unknown): string
			return instances[proxy].Node.Name
		end,
		__metatable = "The metatable is locked",
	}

	proxyOf = function(instance: Instance): unknown
		const existing = proxies[instance]
		if existing then
			return existing
		end
		const proxy = setmetatable({}, ProxyMetatable)
		proxies[instance] = proxy
		instances[proxy] = instance
		return proxy
	end

	const function Build(node: Node, parent: Instance?): Instance
		const children: { Instance } = {}
		const instance: Instance = { Node = node, Parent = parent, Children = children }
		for _, child in node.Children or {} do
			table.insert(children, Build(child, instance))
		end
		if node.Path == entry then
			table.insert(entries, instance)
		end
		return instance
	end

	-- Compiles a script and runs it with its `script` and `require`, returning everything it returned.
	local requireModule: (target: unknown) -> unknown
	const function Execute(instance: Instance): { n: number, [number]: unknown }
		const path = instance.Node.Path :: string
		const module = modules[path]
		if typeof(module) == "function" then
			return table.pack(module(proxyOf(instance), requireModule))
		elseif typeof(module) ~= "string" then
			error(`No source for {path}`, 0)
		end
		const chunk, compileError = loadstring(PRELUDE .. module, `@{path}`)
		if chunk == nil then
			error(compileError, 0)
		end
		return table.pack(chunk(proxyOf(instance), requireModule))
	end

	requireModule = function(target: unknown): unknown
		const instance = instances[target]
		if instance == nil then
			error(`require expects a ModuleScript of the headless tree, got {typeof(target)} {tostring(target)}`, 2)
		end
		const name = fullName(instance)
		if instance.Node.ClassName ~= "ModuleScript" then
			error(`Attempted to call require with a {instance.Node.ClassName} ({name}); only ModuleScripts load`, 2)
		end
		const state = states[instance]
		if state == "loaded" then
			return results[instance]
		elseif state == "failed" then
			error(`Requested module experienced an error while loading: {name}`, 2)
		elseif state == "loading" then
			const chain: { string } = {}
			local cycleStarted = false
			for _, pending in loading do
				cycleStarted = cycleStarted or pending == instance
				if cycleStarted then
					table.insert(chain, fullName(pending))
				end
			end
			table.insert(chain, name)
			error(`Cyclic require: {table.concat(chain, " -> ")}`, 2)
		end

		states[instance] = "loading"
		table.insert(loading, instance)
		const ok, packed = pcall(Execute, instance)
		table.remove(loading)
		if not ok then
			states[instance] = "failed"
			error(packed, 0)
		end
		if packed.n ~= 1 then
			states[instance] = "failed"
			error(`Module code did not return exactly one value: {name}`, 2)
		end
		states[instance] = "loaded"
		results[instance] = packed[1]
		return packed[1]
	end

	Build(tree, nil)
	if #entries ~= 1 then
		error(`{entry} must be exactly one script of the tree, found {#entries}`, 0)
	end
	-- The entry is the main program, as with `luau entry.luau`: what it returns is ignored.
	const main = entries[1]
	states[main] = "loading"
	table.insert(loading, main)
	Execute(main)
	table.remove(loading)
	states[main] = "loaded"
end

return table.freeze(Headless)
