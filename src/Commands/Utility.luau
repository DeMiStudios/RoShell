--!strict
--[[
	Utility commands. Most run on the client (`ClientRun`) and never touch the network.
]]

--// Imports
const BuiltInTypes = require("../Shared/BuiltInTypes")
const Command = require("../Shared/Command")
const Constants = require("../Shared/Constants")
const Keys = require("../Shared/Keys")
const MathEval = require("../Shared/MathEval")
const Parser = require("../Shared/Parser")
const Permissions = require("../Shared/Permissions")
const ShellDirectory = require("../Shared/ShellDirectory")
const TypeBuilder = require("../Shared/TypeBuilder")
const Types = require("../Shared/Types")
const Util = require("../Shared/Util")

--// Types
type Context = Types.Context

--// Constants
const EVERYONE = Permissions.Everyone()
const T = BuiltInTypes.Types
const HISTORY_PAGE = 20

const Condition = TypeBuilder.Choice<<"equals" | "notEquals" | "contains" | "startsWith" | "endsWith" | "matches" | "greater" | "less" | "atLeast" | "atMost" | "empty" | "notEmpty">>({
	Name = "condition",
	Choices = {
		"equals",
		"notEquals",
		"contains",
		"startsWith",
		"endsWith",
		"matches",
		"greater",
		"less",
		"atLeast",
		"atMost",
		"empty",
		"notEmpty",
	},
	Aliases = {
		equals = { "==", "eq" },
		notEquals = { "~=", "!=", "ne" },
		greater = { ">", "gt" },
		less = { "<", "lt" },
		atLeast = { ">=", "ge" },
		atMost = { "<=", "le" },
		matches = { "pattern" },
	},
})

--- Theme names offered by the console.
const ThemeName = TypeBuilder.Dynamic({
	Name = "theme",
	Candidates = function(request: Types.CandidateRequest): { Types.Candidate<string> }
		const candidates: { Types.Candidate<string> } = {}
		const shell = ShellDirectory.Get(request.Shell)
		const console = if shell then shell.Registry:GetEnv(Keys.Console) else nil
		if console then
			for _, name in console.GetThemes() do
				table.insert(candidates, { Key = name, Value = name })
			end
		end
		return candidates
	end,
})

--- Setting keys offered by the console.
const SettingKey = TypeBuilder.Dynamic({
	Name = "setting",
	Candidates = function(request: Types.CandidateRequest): { Types.Candidate<string> }
		const candidates: { Types.Candidate<string> } = {}
		const shell = ShellDirectory.Get(request.Shell)
		const console = if shell then shell.Registry:GetEnv(Keys.Console) else nil
		if console then
			for _, setting in console.GetSettings() do
				table.insert(candidates, {
					Key = setting.Key,
					Value = setting.Key,
					Detail = setting.Value,
					Description = setting.Description,
				})
			end
		end
		return candidates
	end,
})

--// Helpers

const function console(ctx: Context): Keys.ConsoleApi?
	return ctx:GetEnv(Keys.Console)
end

const function needsConsole(ctx: Context): Types.Reply
	return ctx:Error("This command needs the console interface")
end

const function joinWords(words: { string }): string
	return table.concat(words, " ")
end

--// Text and values

const echo = Command.new({
	Name = "echo",
	Icon = "paragraph",
	Aliases = { "print" },
	Description = "Prints text (and passes it on through pipes)",
	Group = "Utility",
	Permissions = EVERYONE,
	Examples = { 'echo "Hello, world"', "echo $$" },
	Args = { { text = Command.Rest(T.String, { Description = "Text to print" }) } },
}):ClientRun(function(ctx, args)
	const text = joinWords(args.text)
	return ctx:Value(T.String, text, text)
end)

const mathCommand = Command.new({
	Name = "math",
	Icon = "hashtag",
	Aliases = { "calc", "=" },
	Description = "Evaluates an arithmetic expression",
	Group = "Utility",
	Permissions = EVERYONE,
	Returns = T.Number,
	Examples = { "math (2 + 3) * 4", "math sqrt(2) ^ 2", "math max(1, $$)" },
	Args = { { expression = Command.Rest(T.String, { Description = "e.g. (2 + 3) * 4, sqrt(16), pi * 2" }) } },
}):ClientRun(function(ctx, args)
	const value, err = MathEval.Evaluate(joinWords(args.expression))
	if value == nil then
		return ctx:Error(err or "Invalid expression")
	end
	return ctx:Value(T.Number, value, Util.FormatNumber(value))
end)

const random = Command.new({
	Name = "random",
	Icon = "star",
	Aliases = { "rand" },
	Description = "A random integer between min and max",
	Group = "Utility",
	Permissions = EVERYONE,
	Returns = T.Integer,
	Args = { { min = Command.Default(T.Integer, 1) }, { max = Command.Default(T.Integer, 100) } },
}):ClientRun(function(ctx, args)
	const low = math.min(args.min, args.max)
	const high = math.max(args.min, args.max)
	const value = ctx.Shell.Platform.Random(low, high)
	return ctx:Value(T.Integer, value, tostring(value))
end)

const replace = Command.new({
	Name = "replace",
	Icon = "pencil",
	Description = "Replaces every match of a Luau pattern (or plain text with --plain)",
	Group = "Utility",
	Permissions = EVERYONE,
	Returns = T.String,
	Args = {
		{ text = Command.Arg(T.String) },
		{ pattern = Command.Arg(T.String) },
		{ replacement = Command.Default(T.String, "") },
		{ plain = Command.Flag({ Short = "p", Description = "Treat the pattern as plain text" }) },
	},
}):ClientRun(function(ctx, args)
	local pattern = args.pattern
	if args.plain then
		pattern = pattern:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0")
	end
	const ok, result = pcall(function(): string
		return (args.text:gsub(pattern, (args.replacement:gsub("%%", "%%%%"))))
	end)
	if not ok then
		return ctx:Error(`Invalid pattern: {result}`)
	end
	return ctx:Value(T.String, result, result)
end)

const len = Command.new({
	Name = "len",
	Icon = "hashtag",
	Description = "Length of a text (characters), or number of items piped in",
	Group = "Utility",
	Permissions = EVERYONE,
	Returns = T.Integer,
	Args = { { text = Command.Rest(T.String) } },
}):ClientRun(function(ctx, args)
	const piped = ctx.Piped
	if piped and type(piped.Value) == "table" then
		local count = 0
		for _ in pairs(piped.Value) do
			count += 1
		end
		return ctx:Value(T.Integer, count, tostring(count))
	end
	const text = joinWords(args.text)
	const count = utf8.len(text) or #text
	return ctx:Value(T.Integer, count, tostring(count))
end)

--// Control flow

const run = Command.new({
	Name = "run",
	Icon = "play-small",
	Description = "Runs a command line (useful with variables and aliases)",
	Group = "Utility",
	Permissions = EVERYONE,
	Examples = { 'run "echo hi && echo there"' },
	Args = { { script = Command.Rest(T.String, { Description = "The command line to run" }) } },
}):ClientRun(function(ctx, args)
	const result = ctx:Run(joinWords(args.script))
	const last = result.Last
	if not result.Ok then
		return { Ok = false, Error = if last and last.Message then last.Message else "Failed" }
	end
	return { Ok = true, Value = if last then last.Value else nil }
end)

const runif = Command.new({
	Name = "runif",
	Icon = "play-small",
	Description = "Runs a command line only when a condition holds",
	Group = "Utility",
	Permissions = EVERYONE,
	Examples = { "runif equals $$ yes echo confirmed", "runif greater ${random} 50 echo high" },
	Args = {
		{ condition = Command.Arg(Condition) },
		{ left = Command.Arg(T.String) },
		{ right = Command.Arg(T.String) },
		{ script = Command.Rest(T.String) },
	},
}):ClientRun(function(ctx, args)
	const left, right = args.left, args.right
	const a, b = tonumber(left), tonumber(right)
	local holds = false
	const condition = args.condition
	if condition == "equals" then
		holds = left == right
	elseif condition == "notEquals" then
		holds = left ~= right
	elseif condition == "contains" then
		holds = left:find(right, 1, true) ~= nil
	elseif condition == "startsWith" then
		holds = Util.StartsWith(left, right)
	elseif condition == "endsWith" then
		holds = Util.EndsWith(left, right)
	elseif condition == "matches" then
		const ok, found = pcall(function(): number?
			return (left:find(right))
		end)
		holds = ok and found ~= nil
	elseif condition == "empty" then
		holds = left == ""
	elseif condition == "notEmpty" then
		holds = left ~= ""
	elseif a and b then
		holds = (condition == "greater" and a > b)
			or (condition == "less" and a < b)
			or (condition == "atLeast" and a >= b)
			or (condition == "atMost" and a <= b)
	end
	if not holds then
		return ctx:Info("Condition not met")
	end
	const result = ctx:Run(joinWords(args.script))
	if not result.Ok then
		const last = result.Last
		return { Ok = false, Error = if last and last.Message then last.Message else "Failed" }
	end
	return nil
end)

const waitCommand = Command.new({
	Name = "wait",
	Icon = "clock",
	Aliases = { "sleep" },
	Description = "Waits before continuing (useful in scripts and chains)",
	Group = "Utility",
	Permissions = EVERYONE,
	Args = { { duration = Command.Arg(T.Duration) } },
}):ClientRun(function(ctx, args)
	const deadline = ctx.Shell.Platform.Clock() + args.duration
	while ctx.Shell.Platform.Clock() < deadline do
		ctx:CheckCancelled()
		ctx.Shell.Platform.Wait(math.min(0.1, deadline - ctx.Shell.Platform.Clock()))
	end
	return nil
end)

--// Console

const history = Command.new({
	Name = "history",
	Icon = "clock",
	Description = "Shows your command history, or returns one entry (negative counts from the end)",
	Group = "Utility",
	Permissions = EVERYONE,
	Examples = { "history", "history -1", "run ${history -2}" },
	Args = { { line = Command.Optional(T.Integer) } },
}):ClientRun(function(ctx, args)
	const api = console(ctx)
	if api == nil then
		return needsConsole(ctx)
	end
	const entries = api.GetHistory()
	if args.line then
		const index = if args.line <= 0 then #entries + args.line else args.line
		const entry = entries[index]
		if entry == nil then
			return ctx:Error(`No history entry {args.line}`)
		end
		return ctx:Value(T.String, entry, entry)
	end
	const lines: { string } = {}
	for index = math.max(1, #entries - HISTORY_PAGE + 1), #entries do
		table.insert(lines, `{index}  {entries[index]}`)
	end
	return ctx:List(lines, `History ({#entries})`)
end)

const clear = Command.new({
	Name = "clear",
	Icon = "trash-can",
	Aliases = { "cls" },
	Description = "Clears the console (Ctrl+L)",
	Group = "Utility",
	Permissions = EVERYONE,
	Args = {},
}):ClientRun(function(ctx)
	const api = console(ctx)
	if api == nil then
		return needsConsole(ctx)
	end
	api.Clear()
	return ""
end)

const hide = Command.new({
	Name = "hide",
	Icon = "eye-slash",
	Description = "Hides the console",
	Group = "Utility",
	Permissions = EVERYONE,
	Args = {},
}):ClientRun(function(ctx)
	const api = console(ctx)
	if api then
		api.Hide()
	end
	return ""
end)

const palette = Command.new({
	Name = "palette",
	Icon = "grid",
	Description = "Opens the command palette (Ctrl+K)",
	Group = "Utility",
	Permissions = EVERYONE,
	Args = {},
}):ClientRun(function(ctx)
	const api = console(ctx)
	if api == nil then
		return needsConsole(ctx)
	end
	api.OpenPalette()
	return ""
end)

const theme = Command.new({
	Name = "theme",
	Icon = "paint-brush",
	Description = "Opens the theme picker, or switches theme",
	Group = "Utility",
	Permissions = EVERYONE,
	Examples = { "theme", "theme Graphite", "theme Light" },
	Args = { { name = Command.Optional(ThemeName) } },
}):ClientRun(function(ctx, args)
	const api = console(ctx)
	if api == nil then
		return needsConsole(ctx)
	end
	if args.name then
		if api.SetTheme(args.name) then
			return ctx:Success(`Theme set to {api.GetTheme()}`)
		end
		return ctx:Error(`Unknown theme '{args.name}'`)
	end
	if ctx.Options.IsHuman then
		api.OpenThemes()
		return nil
	end
	const current = api.GetTheme()
	const lines: { string } = {}
	for _, name in api.GetThemes() do
		table.insert(lines, if name == current then name .. "  (current)" else name)
	end
	return ctx:List(lines, "Themes")
end)

const config = Command.new({
	Name = "config",
	Icon = "gear",
	Aliases = { "settings" },
	Description = "Shows or changes console settings",
	Group = "Utility",
	Permissions = EVERYONE,
	Examples = { "config", "config density compact", "config reduceMotion true" },
	Args = {
		{ key = Command.Optional(SettingKey) },
		{
			-- Typed by the setting itself, so values complete (`config dock ` offers top, bottom, float).
			value = Command.Dynamic(function(request: Types.DynamicArgRequest): Types.Type<unknown>?
				const key = request.Previous.key
				const shell = ShellDirectory.Get(request.Shell)
				const api = if shell then shell.Registry:GetEnv(Keys.Console) else nil
				return if api and type(key) == "string" then api.SettingType(key) else nil
			end, { Description = "The new value" }),
		},
	},
}):ClientRun(function(ctx, args)
	const api = console(ctx)
	if api == nil then
		return needsConsole(ctx)
	end
	const key = args.key
	const value = args.value
	if key and value ~= nil then
		const text = if type(value) == "string" then value else tostring(value)
		const ok, err = api.SetSetting(key, text)
		if ok then
			return ctx:Success(`{key} = {text}`)
		end
		return ctx:Error(err or "Invalid value")
	end
	const rows: { { string } } = {}
	for _, setting in api.GetSettings() do
		if key == nil or setting.Key == key then
			table.insert(rows, { setting.Key, setting.Value, setting.Description })
		end
	end
	return ctx:Table({ Title = "Settings", Columns = { "Key", "Value", "Description" }, Rows = rows })
end)

const exportLog = Command.new({
	Name = "export-log",
	Icon = "arrow-large-down",
	Description = "Exports the console log as text you can copy",
	Group = "Utility",
	Permissions = EVERYONE,
	Args = {},
}):ClientRun(function(ctx)
	const api = console(ctx)
	if api == nil then
		return needsConsole(ctx)
	end
	const text = api.ExportLog()
	return ctx:Value(T.String, text, `{#text} characters (select and copy with Ctrl+C)`)
end)

--// Aliases, variables and binds

const alias = Command.new({
	Name = "alias",
	Icon = "chain-link",
	Description = "Defines a command alias/macro; $1..$9 and $@ are replaced by its words",
	Group = "Utility",
	Permissions = EVERYONE,
	Examples = { 'alias gg = "announce GG $1"', 'alias heal-all "heal *"' },
	Args = {
		{ name = Command.Arg(T.String, { Description = "The alias name" }) },
		{ body = Command.Rest(T.String, { Description = "The command line it runs" }) },
	},
}):ClientRun(function(ctx, args)
	const words = table.clone(args.body)
	if words[1] == "=" then
		table.remove(words, 1)
	end
	const body = joinWords(words)
	if body == "" then
		return ctx:Error("The alias body is empty")
	end
	if not args.name:match("^[%w_][%w_%-%.!%?]*$") then
		return ctx:Error(`'{args.name}' is not a valid alias name`)
	end
	const existing = ctx.Shell.Registry:GetCommand(args.name)
	if existing and not existing._isAlias then
		return ctx:Error(`'{args.name}' is already a command`)
	end
	const parsed = Parser.Parse(body)
	for _, diagnostic in parsed.Diagnostics do
		return ctx:Error(`The alias body has a syntax error: {diagnostic.Message}`)
	end
	const evaluation = ctx.Shell.Dispatcher:Evaluate({ Text = body, Executor = ctx.Executor })
	for _, item in evaluation.Diagnostics do
		if item.Severity == "error" and item.Message:find("Unknown command", 1, true) then
			return ctx:Error(`The alias body is invalid: {item.Message}`)
		end
	end
	ctx.Shell.Registry:RegisterCommand(Command.Alias(args.name, body))
	const api = console(ctx)
	if api then
		api.SaveAlias(args.name, body)
	end
	return ctx:Success(`Alias {args.name} → {body}`)
end)

const unalias = Command.new({
	Name = "unalias",
	Icon = "chain-link",
	Description = "Removes an alias",
	Group = "Utility",
	Permissions = EVERYONE,
	Args = { { name = Command.Arg(T.Command) } },
}):ClientRun(
	function(ctx, args)
		-- `command` values are recursive tables, which the ArgsOf type function reports as unknown; narrow by lookup.
		const target = Command.Lookup(args.name)
		if target == nil then
			return ctx:Error("Unknown command")
		end
		if not target._isAlias then
			return ctx:Error(`'{target.Name}' is not an alias`)
		end
		ctx.Shell.Registry:UnregisterCommand(target.Name)
		const api = console(ctx)
		if api then
			api.RemoveAlias(target.Name)
		end
		return ctx:Success(`Removed alias {target.Name}`)
	end
)

const aliases = Command.new({
	Name = "aliases",
	Icon = "chain-link",
	Description = "Lists your aliases",
	Group = "Utility",
	Permissions = EVERYONE,
	Args = {},
}):ClientRun(function(ctx)
	const entries: { { Key: string, Value: string } } = {}
	for _, command in ctx.Shell.Registry:GetCommands() do
		if command._isAlias and command._aliasBody then
			table.insert(entries, { Key = command.Name, Value = command._aliasBody })
		end
	end
	if #entries == 0 then
		return ctx:Info("No aliases yet. Create one with: alias name = \"command $1\"")
	end
	return ctx:KeyValue(entries, "Aliases")
end)

const set = Command.new({
	Name = "set",
	Icon = "tag",
	Description = "Sets a variable ($name)",
	Group = "Utility",
	Permissions = EVERYONE,
	Examples = { "set target Bob", "kick $target" },
	Args = { { name = Command.Arg(T.StoredKey) }, { value = Command.Rest(T.String) } },
}):ClientRun(function(ctx, args)
	const value = if ctx.Piped and #args.value == 0 then ctx.Piped.Display else joinWords(args.value)
	ctx.Shell:GetSession(ctx.Executor).Variables[args.name] = value
	const api = console(ctx)
	if api then
		api.SaveVariables()
	end
	return ctx:Success(`${args.name} = {value}`)
end)

const get = Command.new({
	Name = "get",
	Icon = "tag",
	Description = "Gets a variable",
	Group = "Utility",
	Permissions = EVERYONE,
	Returns = T.String,
	Args = { { name = Command.Arg(T.StoredKey) } },
}):ClientRun(function(ctx, args)
	const value = ctx.Shell:GetSession(ctx.Executor).Variables[args.name]
	if value == nil then
		return ctx:Error(`${args.name} is not set`)
	end
	return ctx:Value(T.String, value, value)
end)

const unset = Command.new({
	Name = "unset",
	Icon = "tag",
	Description = "Removes a variable",
	Group = "Utility",
	Permissions = EVERYONE,
	Args = { { name = Command.Arg(T.StoredKey) } },
}):ClientRun(function(ctx, args)
	ctx.Shell:GetSession(ctx.Executor).Variables[args.name] = nil
	const api = console(ctx)
	if api then
		api.SaveVariables()
	end
	return ctx:Success(`Removed ${args.name}`)
end)

const vars = Command.new({
	Name = "vars",
	Icon = "tag",
	Description = "Lists your variables",
	Group = "Utility",
	Permissions = EVERYONE,
	Args = {},
}):ClientRun(function(ctx)
	const entries: { { Key: string, Value: string } } = {}
	for name, value in ctx.Shell:GetSession(ctx.Executor).Variables do
		table.insert(entries, { Key = "$" .. name, Value = value })
	end
	table.sort(entries, function(a: { Key: string, Value: string }, b: { Key: string, Value: string }): boolean
		return a.Key < b.Key
	end)
	if #entries == 0 then
		return ctx:Info("No variables. Set one with: set name value")
	end
	return ctx:KeyValue(entries, "Variables")
end)

const bind = Command.new({
	Name = "bind",
	Icon = "keyboard",
	Description = "Binds a key (with modifiers) to a command line",
	Group = "Utility",
	Permissions = EVERYONE,
	Examples = { "bind F5 respawn .", "bind Ctrl+Shift+H heal ." },
	Args = { { key = Command.Arg(T.Keybind) }, { script = Command.Rest(T.String) } },
}):ClientRun(function(ctx, args)
	const api = console(ctx)
	if api == nil then
		return needsConsole(ctx)
	end
	const ok, err = api.Bind(args.key.Text, joinWords(args.script))
	if not ok then
		return ctx:Error(err or "Could not bind")
	end
	return ctx:Success(`{args.key.Text} → {joinWords(args.script)}`)
end)

const unbind = Command.new({
	Name = "unbind",
	Icon = "keyboard",
	Description = "Removes a key binding",
	Group = "Utility",
	Permissions = EVERYONE,
	Args = { { key = Command.Arg(T.Keybind) } },
}):ClientRun(function(ctx, args)
	const api = console(ctx)
	if api == nil then
		return needsConsole(ctx)
	end
	if api.Unbind(args.key.Text) then
		return ctx:Success(`Unbound {args.key.Text}`)
	end
	return ctx:Error(`{args.key.Text} is not bound`)
end)

const binds = Command.new({
	Name = "binds",
	Icon = "keyboard",
	Description = "Lists your key bindings",
	Group = "Utility",
	Permissions = EVERYONE,
	Args = {},
}):ClientRun(function(ctx)
	const api = console(ctx)
	if api == nil then
		return needsConsole(ctx)
	end
	const entries: { { Key: string, Value: string } } = {}
	for _, entry in api.GetBinds() do
		table.insert(entries, { Key = entry.Key, Value = entry.Command })
	end
	if #entries == 0 then
		return ctx:Info("No bindings. Create one with: bind F5 command")
	end
	return ctx:KeyValue(entries, "Bindings")
end)

--// Undo / redo

const function undoFrom(ctx: Context, redo: boolean): Types.Output
	const session = ctx.Shell:GetSession(ctx.Executor)
	const source = if redo then session.Redo else session.Undo
	const target = if redo then session.Undo else session.Redo
	const action = table.remove(source)
	if action == nil then
		-- Nothing on this side: the server may have something (returning nil falls back to `Run`).
		return nil
	end
	const step = if redo then action.Redo else action.Undo
	if step == nil then
		return ctx:Error(`'{action.Description}' cannot be redone`)
	end
	local failure: string? = nil
	const ok = xpcall(step, function(message: unknown)
		failure = tostring(message)
	end)
	if not ok then
		return ctx:Error(`{if redo then "Redo" else "Undo"} failed: {failure or "error"}`)
	end
	table.insert(target, action)
	return ctx:Success(`{if redo then "Redid" else "Undid"}: {action.Description}`)
end

const undo = Command.new({
	Name = "undo",
	Icon = "arrow-large-left",
	Description = "Undoes your last undoable command",
	Group = "Utility",
	Permissions = EVERYONE,
	Args = {},
}):ClientRun(function(ctx)
	return undoFrom(ctx, false)
end):Run(function(ctx)
	return undoFrom(ctx, false) or ctx:Info("Nothing to undo")
end)

const redo = Command.new({
	Name = "redo",
	Icon = "arrow-large-right",
	Description = "Redoes your last undone command",
	Group = "Utility",
	Permissions = EVERYONE,
	Args = {},
}):ClientRun(function(ctx)
	return undoFrom(ctx, true)
end):Run(function(ctx)
	return undoFrom(ctx, true) or ctx:Info("Nothing to redo")
end)

--// Info

const resolve = Command.new({
	Name = "resolve",
	Icon = "magnifying-glass-plus",
	Description = "Shows what a value (wildcards included) resolves to for a type",
	Group = "Utility",
	Permissions = EVERYONE,
	Examples = { "resolve players *-Bob", "resolve color3 hsv(200,80,100)" },
	Args = {
		{ type = Command.Arg(T.TypeName) },
		{
			value = Command.Dynamic(function(request: Types.DynamicArgRequest): Types.Type<unknown>?
				return TypeBuilder.Lookup(request.Previous.type)
			end, { Description = "A value of that type" }),
		},
	},
}):ClientRun(function(ctx, args)
	const value = args.value
	const valueType = TypeBuilder.Lookup(args.type)
	const typeName = if valueType then valueType.Name else "values"
	if type(value) == "table" then
		const items: { string } = {}
		for _, item in pairs(value) do
			table.insert(items, Util.FormatValue(item))
		end
		return ctx:List(items, `{#items} {typeName}`)
	end
	return ctx:Info(Util.FormatValue(value))
end)

const version = Command.new({
	Name = "version",
	Icon = "circle-info",
	Description = "Shows the RoShell version",
	Group = "Utility",
	Permissions = EVERYONE,
	Args = {},
}):ClientRun(function(ctx)
	return ctx:Info(`{Constants.Name} v{Constants.Version} (protocol {Constants.ProtocolVersion})`)
end)

const uptime = Command.new({
	Name = "uptime",
	Icon = "clock",
	Description = "How long this server has been running",
	Group = "Utility",
	Permissions = EVERYONE,
	Returns = T.Duration,
	Args = {},
}):Run(function(ctx)
	const seconds = workspace.DistributedGameTime
	return ctx:Value(T.Duration, seconds, Util.FormatDuration(seconds))
end)

return {
	echo,
	mathCommand,
	random,
	replace,
	len,
	run,
	runif,
	waitCommand,
	history,
	clear,
	hide,
	palette,
	theme,
	config,
	exportLog,
	alias,
	unalias,
	aliases,
	set,
	get,
	unset,
	vars,
	bind,
	unbind,
	binds,
	undo,
	redo,
	resolve,
	version,
	uptime,
} :: { Types.Command }
