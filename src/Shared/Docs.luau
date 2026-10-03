--!strict
--[[
	Reference generation: a serializable schema of every registered command and type, and a Markdown rendering
	of it for wikis and READMEs.

		print(RoShell.Docs.Markdown(server.Registry))
		HttpService:JSONEncode(RoShell.Docs.Schema(server.Registry))
]]

--// Imports
const Command = require("./Command")
const Constants = require("./Constants")
const Types = require("./Types")

--// Types
export type ArgDoc = {
	Name: string,
	Type: string,
	Kind: Types.ArgKind,
	Optional: boolean,
	Named: boolean,
	Short: string?,
	Description: string?,
	Default: string?,
}

export type CommandDoc = {
	Name: string,
	Aliases: { string },
	Description: string,
	Details: string?,
	Group: string?,
	Signature: string,
	Args: { ArgDoc },
	Examples: { { Text: string, Description: string? } },
	Subcommands: { CommandDoc },
	Destructive: boolean,
	DryRun: boolean,
	Deprecated: string?,
	Returns: string?,
}

export type TypeDoc = {
	Name: string,
	Kind: string,
	Description: string?,
	Examples: { string },
	Listable: boolean,
	Operators: { string },
}

export type FunctionDoc = { Name: string, Description: string? }

export type Schema = {
	Name: string,
	Version: string,
	Commands: { CommandDoc },
	Types: { TypeDoc },
	Functions: { FunctionDoc },
}

export type SchemaOptions = {
	--- Include hidden commands and arguments (default false).
	IncludeHidden: boolean?,
	--- Only commands this predicate accepts (e.g. what a player may see).
	Filter: ((command: Types.Command) -> boolean)?,
}

--// Helpers

-- `table.clone` would keep the read-only type; the schema hands out mutable copies.
-- selene: allow(manual_table_clone)
const function copy(list: { read string }): { string }
	const result: { string } = {}
	for index, item in list do
		result[index] = item
	end
	return result
end

const function argDoc(arg: Types.BoundArg): ArgDoc
	return {
		Name = arg.Name,
		Type = arg.Type.Name,
		Kind = arg.Kind,
		Optional = arg.Optional,
		Named = not arg.Positional,
		Short = arg.Options.Short,
		Description = arg.Options.Description,
		Default = arg.DefaultDisplay,
	}
end

const function commandDoc(command: Types.Command, options: SchemaOptions): CommandDoc
	const args: { ArgDoc } = {}
	for _, arg in command.Args do
		if options.IncludeHidden or not arg.Options.Hidden then
			table.insert(args, argDoc(arg))
		end
	end
	const examples: { { Text: string, Description: string? } } = {}
	for _, example in command.Examples do
		table.insert(examples, { Text = example.Text, Description = example.Description })
	end
	const subcommands: { CommandDoc } = {}
	for _, subcommand in command.Subcommands do
		table.insert(subcommands, commandDoc(subcommand, options))
	end
	const deprecated = command.Deprecated
	return {
		Name = Command.FullName(command),
		Aliases = copy(command.Aliases),
		Description = command.Description,
		Details = command.Details,
		Group = command.Group,
		Signature = Command.Signature(command),
		Args = args,
		Examples = examples,
		Subcommands = subcommands,
		Destructive = command.Destructive,
		DryRun = command.SupportsDryRun,
		Deprecated = if deprecated then deprecated.Message
				or (if deprecated.Replacement then `Use {deprecated.Replacement}` else "Deprecated")
			else nil,
		Returns = if command.Returns then command.Returns.Name else nil,
	}
end

const function escapeCell(text: string): string
	return (text:gsub("|", "\\|"):gsub("\n", " "))
end

--// Docs
const Docs = {}

--- A plain-data description of the registry (safe to JSON-encode).
function Docs.Schema(registry: Types.Registry, options: SchemaOptions?): Schema
	const opts: SchemaOptions = options or {}
	const commands: { CommandDoc } = {}
	for _, command in registry:GetCommands() do
		if command._isAlias or (command.Hidden and not opts.IncludeHidden) then
			continue
		end
		if opts.Filter and not opts.Filter(command) then
			continue
		end
		table.insert(commands, commandDoc(command, opts))
	end
	table.sort(commands, function(a: CommandDoc, b: CommandDoc): boolean
		return a.Name < b.Name
	end)
	const typeDocs: { TypeDoc } = {}
	for _, valueType in registry:GetTypes() do
		const operators: { string } = {}
		for _, operator in valueType.Operators do
			table.insert(operators, operator.Symbol)
		end
		const examples = valueType.Examples
		const doc: TypeDoc = {
			Name = valueType.Name,
			Kind = valueType.Kind,
			Description = valueType.Description,
			Examples = if examples then copy(examples) else {},
			Listable = valueType.Listable,
			Operators = operators,
		}
		table.insert(typeDocs, doc)
	end
	table.sort(typeDocs, function(a: TypeDoc, b: TypeDoc): boolean
		return a.Name < b.Name
	end)
	const functions: { FunctionDoc } = {}
	for _, definition in registry:GetFunctions() do
		table.insert(functions, { Name = definition.Name, Description = definition.Description })
	end
	table.sort(functions, function(a: FunctionDoc, b: FunctionDoc): boolean
		return a.Name < b.Name
	end)
	return {
		Name = Constants.Name,
		Version = Constants.Version,
		Commands = commands,
		Types = typeDocs,
		Functions = functions,
	}
end

--- A Markdown reference: commands grouped by group, then types.
function Docs.Markdown(registry: Types.Registry, options: SchemaOptions?): string
	const schema = Docs.Schema(registry, options)
	const lines: { string } = { `# {schema.Name} command reference`, "", `Generated for version {schema.Version}.`, "" }
	const groups: { [string]: { CommandDoc } } = {}
	const groupNames: { string } = {}
	for _, command in schema.Commands do
		const group = command.Group or "General"
		if groups[group] == nil then
			groups[group] = {}
			table.insert(groupNames, group)
		end
		table.insert(groups[group], command)
	end
	table.sort(groupNames)

	const function writeCommand(command: CommandDoc, depth: number)
		table.insert(lines, `{string.rep("#", depth)} \`{command.Name}\``)
		table.insert(lines, "")
		table.insert(lines, command.Description)
		table.insert(lines, "")
		table.insert(lines, "```")
		table.insert(lines, command.Signature)
		table.insert(lines, "```")
		table.insert(lines, "")
		if command.Details then
			table.insert(lines, command.Details)
			table.insert(lines, "")
		end
		if command.Deprecated then
			table.insert(lines, `> **Deprecated:** {command.Deprecated}`)
			table.insert(lines, "")
		end
		if #command.Aliases > 0 then
			table.insert(lines, `Aliases: {table.concat(command.Aliases, ", ")}`)
			table.insert(lines, "")
		end
		if #command.Args > 0 then
			table.insert(lines, "| Argument | Type | Required | Description |")
			table.insert(lines, "|---|---|---|---|")
			for _, arg in command.Args do
				const name = if arg.Named then `--{arg.Name}` else arg.Name
				const default = if arg.Default then ` (default: {arg.Default})` else ""
				table.insert(lines, `| \`{name}\` | {arg.Type} | {if arg.Optional then "no" else "yes"} | {escapeCell(
						(arg.Description or "") .. default
					)} |`)
			end
			table.insert(lines, "")
		end
		if #command.Examples > 0 then
			table.insert(lines, "Examples:")
			table.insert(lines, "")
			for _, example in command.Examples do
				table.insert(
					lines,
					`- \`{example.Text}\`{if example.Description then " — " .. example.Description else ""}`
				)
			end
			table.insert(lines, "")
		end
		for _, subcommand in command.Subcommands do
			writeCommand(subcommand, math.min(depth + 1, 6))
		end
	end

	for _, group in groupNames do
		table.insert(lines, `## {group}`)
		table.insert(lines, "")
		for _, command in groups[group] do
			writeCommand(command, 3)
		end
	end

	table.insert(lines, "## Types")
	table.insert(lines, "")
	table.insert(lines, "| Type | Kind | Lists | Description |")
	table.insert(lines, "|---|---|---|---|")
	for _, typeDoc in schema.Types do
		table.insert(lines, `| \`{typeDoc.Name}\` | {typeDoc.Kind} | {if typeDoc.Listable then "yes" else "no"} | {escapeCell(
				typeDoc.Description or ""
			)} |`)
	end
	table.insert(lines, "")

	if #schema.Functions > 0 then
		table.insert(lines, "## Functions")
		table.insert(lines, "")
		table.insert(lines, "| Function | Description |")
		table.insert(lines, "|---|---|")
		for _, definition in schema.Functions do
			table.insert(lines, `| \`${definition.Name}()\` | {escapeCell(definition.Description or "")} |`)
		end
		table.insert(lines, "")
	end
	return table.concat(lines, "\n")
end

return table.freeze(Docs)
