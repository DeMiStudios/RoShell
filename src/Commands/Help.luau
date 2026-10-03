--!strict
--[[
	Discovery commands: help, commands, types, operators.
]]

--// Imports
const BuiltInTypes = require("../Shared/BuiltInTypes")
const Command = require("../Shared/Command")
const Fuzzy = require("../Shared/Fuzzy")
const Permissions = require("../Shared/Permissions")
const Selector = require("../Shared/Selector")
const TypeBuilder = require("../Shared/TypeBuilder")
const Types = require("../Shared/Types")
const Util = require("../Shared/Util")

--// Types
type Context = Types.Context

--// Constants
const EVERYONE = Permissions.Everyone()
const RoShellTypes = BuiltInTypes.Types

const Topic = TypeBuilder.Choice<<"operators" | "types" | "keys">>({
	Name = "topic",
	Choices = { "operators", "types", "keys" },
	Descriptions = {
		operators = "Wildcards, selectors and set arithmetic",
		types = "Every argument type",
		keys = "Keyboard shortcuts",
	},
})
const HelpSubject = TypeBuilder.Union({
	Name = "subject",
	Description = "A command, a type, or a topic (operators, types, keys)",
	Members = { RoShellTypes.Command, Topic, RoShellTypes.TypeName },
})

const KEYS = {
	{ "Tab", "Accept suggestion (first press completes the common prefix)" },
	{ "Shift+Tab", "Previous suggestion" },
	{ "→ / End", "Accept ghost text" },
	{ "↑ / ↓", "Move in suggestions, otherwise history" },
	{ "Ctrl+Space", "Show suggestions" },
	{ "Enter", "Run (accepts a navigated suggestion first)" },
	{ "Esc", "Close suggestions → clear input → close console" },
	{ "Ctrl+R", "Search history" },
	{ "Ctrl+K", "Command palette" },
	{ "Ctrl+L", "Clear the log" },
	{ "Ctrl+W / Alt+Backspace", "Delete previous word" },
	{ "Ctrl+← / →", "Jump by word" },
	{ "Ctrl+Z / Ctrl+Shift+Z", "Undo / redo typing" },
	{ "Ctrl+C", "Cancel the running command" },
	{ "F1 / ? (empty input)", "Help for the current command" },
}

--// Helpers

const function searchText(command: Types.Command): string
	return command.Name .. " " .. command.Description
end

const function visibleCommands(ctx: Context): { Types.Command }
	const list: { Types.Command } = {}
	for _, command in ctx.Shell.Registry:GetCommands() do
		if not command.Hidden and ctx.Shell.Permissions:CanSee(ctx.Executor, command) then
			table.insert(list, command)
		end
	end
	table.sort(list, function(a: Types.Command, b: Types.Command): boolean
		return a.Name < b.Name
	end)
	return list
end

const function helpForCommand(ctx: Context, command: Types.Command): Types.Reply
	const locale = ctx.Shell.Locale
	ctx:Reply(Command.Signature(command), "info")
	if command.Description ~= "" then
		ctx:Reply(command.Description)
	end
	if command.Details then
		ctx:Reply(command.Details, "muted")
	end
	const deprecated = command.Deprecated
	if deprecated then
		ctx:Reply(
			locale:Get("help.deprecated")
				.. (if deprecated.Replacement then ": "
						.. locale:Get("help.useInstead", { replacement = deprecated.Replacement })
					else "")
				.. (if deprecated.Message then " " .. deprecated.Message else ""),
			"warning"
		)
	end
	const facts: { { Key: string, Value: string } } = {}
	if #command.Aliases > 0 then
		table.insert(facts, { Key = locale:Get("help.aliases"), Value = Util.Join(command.Aliases, ", ") })
	end
	if command.Group then
		table.insert(facts, { Key = locale:Get("help.group"), Value = command.Group })
	end
	if command.Permissions and ctx.Shell.Permissions:CanSee(ctx.Executor, command) then
		table.insert(facts, { Key = locale:Get("help.permissions"), Value = command.Permissions.Describe() })
	end
	if command.Cooldown then
		table.insert(facts, { Key = "Cooldown", Value = `{command.Cooldown}s` })
	end
	if #facts > 0 then
		ctx:KeyValue(facts)
	end
	if #command.Args > 0 then
		const rows: { { string } } = {}
		for _, arg in command.Args do
			if not arg.Options.Hidden then
				const shortFlag = if arg.Options.Short then ` (-{arg.Options.Short})` else ""
				const kind = if arg.Kind == "flag" then "flag"
					elseif arg.Kind == "default" then `= {arg.DefaultDisplay or "?"}`
					elseif arg.Kind == "rest" then "…"
					elseif arg.Kind == "optional" then "optional"
					else "required"
				table.insert(rows, {
					arg.Name .. shortFlag,
					arg.Type.Name,
					kind,
					arg.Options.Description or arg.Type.Description or "",
				})
			end
		end
		ctx:Table({ Title = locale:Get("help.arguments"), Columns = { "Name", "Type", "", "Description" }, Rows = rows })
	end
	if #command.Subcommands > 0 then
		const entries: { { Key: string, Value: string } } = {}
		for _, sub in command.Subcommands do
			if not sub.Hidden then
				table.insert(entries, { Key = sub.Name, Value = sub.Description })
			end
		end
		ctx:KeyValue(entries, locale:Get("help.subcommands"))
	end
	if #command.Examples > 0 then
		const lines: { string } = {}
		for _, example in command.Examples do
			table.insert(lines, example.Text .. (if example.Description then "  — " .. example.Description else ""))
		end
		ctx:List(lines, locale:Get("help.examples"))
	end
	return ctx:Value(RoShellTypes.Command, command, command.Name)
end

const function helpForType(ctx: Context, valueType: Types.Type<unknown>): Types.Reply
	ctx:Reply(valueType.Name, "info")
	if valueType.Description then
		ctx:Reply(valueType.Description)
	end
	if valueType.Examples and #valueType.Examples > 0 then
		const examples: { string } = {}
		for _, example in valueType.Examples do
			table.insert(examples, example)
		end
		ctx:List(examples, ctx.Shell.Locale:Get("help.examples"))
	end
	if #valueType.Operators > 0 then
		const rows: { { string } } = {}
		for _, operator in valueType.Operators do
			table.insert(rows, { operator.Symbol, operator.Description, operator.Example })
		end
		ctx:Table({
			Title = ctx.Shell.Locale:Get("help.operators"),
			Columns = { "Syntax", "Meaning", "Example" },
			Rows = rows,
		})
	end
	if valueType.Selectors and #valueType.Selectors > 0 then
		const rows: { { string } } = {}
		for _, selector in valueType.Selectors do
			table.insert(rows, { selector.Prefix .. selector.Name, selector.Description, selector.Example })
		end
		ctx:Table({ Title = "Selectors", Columns = { "Syntax", "Meaning", "Example" }, Rows = rows })
	end
	return ctx:Info(`Type {valueType.Name}`)
end

const function operatorsTable(ctx: Context): Types.Reply
	const rows: { { string } } = {}
	for _, operator in Selector.Operators do
		table.insert(rows, { operator.Symbol, operator.Description, operator.Example })
	end
	ctx:Table({
		Title = ctx.Shell.Locale:Get("help.operators"),
		Columns = { "Syntax", "Meaning", "Example" },
		Rows = rows,
	})
	ctx:Table({
		Title = "Selectors (players)",
		Columns = { "Syntax", "Meaning", "Example" },
		Rows = {
			{ "%Team", "Players on a team", "heal %Red" },
			{ "#Tag", "Players (or characters) with a CollectionService tag", "kill #Zombie" },
			{ "@name:arg", "Selectors registered by the game", "kick @role:Guest" },
		},
	})
	ctx:Table({
		Title = "Input language",
		Columns = { "Syntax", "Meaning" },
		Rows = {
			{ "a && b", "Run b if a succeeded" },
			{ "a || b", "Run b if a failed" },
			{ "a ; b", "Run both (also newlines)" },
			{ "a | b", "Pipe a's value into b" },
			{ "${ cmd }", "Use a command's result as an argument" },
			{ "$name  $$  $1  $@", "Variable, last result, alias parameters" },
			{ "$fn(a, b)", "Call a function (e.g. $random(1, 10))" },
			{ "--flag  -f  --name=v  name=v", "Flags and named arguments" },
			{ '"text"  \'text\'  """raw"""', "Quoting (escapes \\n \\t \\u{…}; single quotes don't interpolate)" },
			{ "# comment", "Comment until the end of the line" },
		},
	})
	return ctx:Info("Operators")
end

const function typesTable(ctx: Context): Types.Reply
	const rows: { { string } } = {}
	for _, valueType in ctx.Shell.Registry:GetTypes() do
		const examples = valueType.Examples
		table.insert(rows, {
			valueType.Name,
			valueType.Description or "",
			if examples and examples[1] then examples[1] else "",
		})
	end
	table.sort(rows, function(a: { string }, b: { string }): boolean
		return a[1] < b[1]
	end)
	ctx:Table({ Title = ctx.Shell.Locale:Get("help.types"), Columns = { "Type", "Accepts", "Example" }, Rows = rows })
	return ctx:Info(`{#rows} types`)
end

--// Commands

const help = Command.new({
	Name = "help",
	Aliases = { "?", "man" },
	Description = "Lists commands, or explains a command, type or topic",
	Group = "Help",
	Permissions = EVERYONE,
	Examples = { "help", "help give", "help players", "help operators" },
	Args = {
		{ subject = Command.Optional(HelpSubject, { Description = "A command, a type, or a topic" }) },
	},
}):ClientRun(function(ctx, args)
	const subject = args.subject
	if subject == nil then
		const groups: { [string]: { { Key: string, Value: string } } } = {}
		const order: { string } = {}
		for _, command in visibleCommands(ctx) do
			const group = command.Group or "Other"
			if groups[group] == nil then
				groups[group] = {}
				table.insert(order, group)
			end
			table.insert(groups[group], { Key = command.Name, Value = command.Description })
		end
		table.sort(order)
		for _, group in order do
			ctx:KeyValue(groups[group], group)
		end
		return ctx:Info(ctx.Shell.Locale:Get("help.tip"))
	end
	const command = Command.Lookup(subject)
	if command then
		return helpForCommand(ctx, command)
	end
	const valueType = TypeBuilder.Lookup(subject)
	if valueType then
		return helpForType(ctx, valueType)
	end
	if subject == "operators" then
		return operatorsTable(ctx)
	elseif subject == "types" then
		return typesTable(ctx)
	end
	const rows: { { string } } = {}
	for _, entry in KEYS do
		table.insert(rows, { entry[1], entry[2] })
	end
	ctx:Table({ Title = "Keyboard shortcuts", Columns = { "Keys", "Action" }, Rows = rows })
	return ctx:Info("Shortcuts can be remapped with the Keymap client option")
end)

const commands = Command.new({
	Name = "commands",
	Aliases = { "cmds" },
	Description = "Lists the commands you can run, optionally filtered",
	Group = "Help",
	Permissions = EVERYONE,
	Args = { { filter = Command.Optional(RoShellTypes.String, { Description = "Fuzzy filter" }) } },
}):ClientRun(function(ctx, args)
	const list = visibleCommands(ctx)
	const filter = args.filter
	const names: { string } = {}
	if filter then
		for _, result in Fuzzy.Filter(filter, list, searchText, 100) do
			table.insert(names, result.Item.Name)
		end
	else
		for _, command in list do
			table.insert(names, command.Name)
		end
	end
	ctx:List(names, `{#names} commands`)
	return ctx:Value(RoShellTypes.Strings, names, `{#names} commands`)
end)

const types = Command.new({
	Name = "types",
	Description = "Lists every argument type with an example",
	Group = "Help",
	Permissions = EVERYONE,
	Args = {},
}):ClientRun(function(ctx)
	return typesTable(ctx)
end)

const operators = Command.new({
	Name = "operators",
	Description = "Explains wildcards, selectors, set arithmetic and the input language",
	Group = "Help",
	Permissions = EVERYONE,
	Args = {},
}):ClientRun(function(ctx)
	return operatorsTable(ctx)
end)

return { help, commands, types, operators } :: { Types.Command }
