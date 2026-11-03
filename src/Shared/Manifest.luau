--!strict
--[[
	Command manifests: how a client learns about commands it cannot load itself.

	Commands can live anywhere on the server (ServerStorage, ServerScriptService, a module that requires server
	code). Their code never leaves the server: each player receives a description of the commands they may run
	(names, arguments, help, and the values of custom types as that player could see them), and the client
	registers stand-ins built from it. The console completes, highlights and checks those lines like any other;
	running one sends the line to the server, which re-parses and runs it.

	Built-in types are only named (clients have their own copy). Custom types are rebuilt from what they showed:
	enumerable types keep their values (and every operator: `*`, globs, `~fuzzy`, set arithmetic), free-text types
	keep their suggestions and accept any text. The server checks everything again either way.
--]]

--// Imports
const BuiltInTypes = require("./BuiltInTypes")
const Command = require("./Command")
const Constants = require("./Constants")
const Fuzzy = require("./Fuzzy")
const Net = require("./Net")
const TypeBuilder = require("./TypeBuilder")
const Types = require("./Types")

--// Types
type CommandInfo = Net.CommandInfo
type TypeInfo = Net.TypeInfo
type CandidateInfo = Net.CandidateInfo

--// Constants
const MAX_CANDIDATES = 200
const MAX_DEPTH = 4

--// Globals
const builtIn: { [Types.TypeInfo]: true } = {}
for _, valueType in BuiltInTypes.All do
	builtIn[valueType] = true
end

--// Functions
-- A writable copy of a read-only list.
const function copyList<T>(list: { read T }): { T }
	const copy: { T } = {}
	for _, item in list do
		table.insert(copy, item)
	end
	return copy
end

const function describeCandidates(candidates: { read Types.Candidate<unknown> }): { CandidateInfo }
	const list: { CandidateInfo } = {}
	for _, candidate in candidates do
		if candidate.Hidden then
			continue
		end
		table.insert(list, {
			Key = candidate.Key,
			Description = candidate.Description,
			Detail = candidate.Detail,
			Aliases = if candidate.Aliases then copyList(candidate.Aliases) else nil,
			Icon = candidate.Icon,
		})
		if #list >= MAX_CANDIDATES then
			break
		end
	end
	return list
end

const function describeSuggestions(suggestions: { Types.Suggestion }): { CandidateInfo }?
	if #suggestions == 0 then
		return nil
	end
	const list: { CandidateInfo } = {}
	for _, suggestion in suggestions do
		table.insert(list, { Key = suggestion.Text, Description = suggestion.Description, Detail = suggestion.Detail })
		if #list >= MAX_CANDIDATES then
			break
		end
	end
	return list
end

const function describeType(shell: Types.Shell, player: Player?, valueType: Types.Type<unknown>, depth: number): TypeInfo
	const info: TypeInfo = {
		Name = valueType.Name,
		Kind = valueType.Kind,
		Description = valueType.Description,
		Examples = if valueType.Examples then copyList(valueType.Examples) else nil,
		Listable = valueType.Listable,
		BuiltIn = builtIn[valueType] == true,
		Color = valueType.Color,
		Icon = valueType.Icon,
	}
	if info.BuiltIn then
		return info
	end

	const element = if valueType.Element then TypeBuilder.Lookup(valueType.Element) else nil
	const enumerate = valueType.Enumerate
	if element and depth < MAX_DEPTH and (valueType.Kind == "list" or valueType.Kind == "optional") then
		info.Element = describeType(shell, player, element, depth + 1)
	elseif enumerate then
		const ok, candidates = pcall(enumerate, { Executor = player, Shell = shell.Handle, Platform = shell.Platform })
		info.Candidates = if ok then describeCandidates(candidates) else {}
	else
		const ok, suggestions = pcall(valueType.Complete, {
			Text = "",
			Quoted = false,
			Executor = player,
			Shell = shell.Handle,
			Platform = shell.Platform,
			Limit = MAX_CANDIDATES,
		})
		info.Suggestions = if ok then describeSuggestions(suggestions) else nil
	end
	return info
end

const function describeCommand(shell: Types.Shell, player: Player?, command: Types.Command): CommandInfo
	const args: { Net.ArgInfo } = {}
	for _, arg in command.Args do
		table.insert(args, {
			Name = arg.Name,
			Kind = arg.Kind,
			Type = describeType(shell, player, arg.Type, 1),
			Options = arg.Options,
			DefaultDisplay = arg.DefaultDisplay,
		})
	end
	const subcommands: { CommandInfo } = {}
	for _, subcommand in command.Subcommands do
		table.insert(subcommands, describeCommand(shell, player, subcommand))
	end
	const returns = command.Returns
	return {
		Name = command.Name,
		Aliases = copyList(command.Aliases),
		Description = command.Description,
		Details = command.Details,
		Group = command.Group,
		Icon = command.Icon,
		Examples = copyList(command.Examples),
		Hidden = command.Hidden,
		Deprecated = command.Deprecated,
		Destructive = command.Destructive,
		SupportsDryRun = command.SupportsDryRun,
		Pipe = command.Pipe,
		Returns = if returns then describeType(shell, player, returns, 1) else nil,
		AutoExec = copyList(command.AutoExec),
		Args = args,
		Subcommands = subcommands,
		Runs = command._run ~= nil,
	}
end

--- True when the command (or one of its subcommands) runs on the server.
const function runsOnServer(command: Types.Command): boolean
	if command._run ~= nil then
		return true
	end
	for _, subcommand in command.Subcommands do
		if runsOnServer(subcommand) then
			return true
		end
	end
	return false
end

const function acceptText(request: Types.ParseRequest): Types.ParseResult<string>
	return { Ok = true, Value = request.Text, Display = request.Text }
end

const function candidateKey(candidate: CandidateInfo): string
	return candidate.Key
end

const function buildType(shell: Types.Shell, info: TypeInfo): Types.Type<unknown>
	-- Built-in types are the client's own; so are types the game registered on the client under the same name.
	const registered = shell.Registry:GetType(info.Name)
	if registered and (info.BuiltIn or not builtIn[registered]) then
		return registered
	end

	const element = info.Element
	const candidates = info.Candidates
	if element and info.Kind == "list" then
		return TypeBuilder.List(buildType(shell, element), { Name = info.Name, Description = info.Description })
	elseif element and info.Kind == "optional" then
		return TypeBuilder.Optional(buildType(shell, element))
	elseif candidates then
		const values: { Types.Candidate<string> } = {}
		for _, candidate in candidates do
			table.insert(values, {
				Key = candidate.Key,
				Value = candidate.Key,
				Description = candidate.Description,
				Detail = candidate.Detail,
				Aliases = candidate.Aliases,
				Icon = candidate.Icon,
			})
		end
		table.freeze(values)
		return TypeBuilder.Enumerable({
			Name = info.Name,
			Description = info.Description,
			Examples = info.Examples,
			Candidates = function(): { read Types.Candidate<string> }
				return values
			end,
			Color = info.Color,
			Icon = info.Icon,
		})
	end

	const suggestions = info.Suggestions or {}
	return TypeBuilder.Custom({
		Name = info.Name,
		Description = info.Description,
		Examples = info.Examples,
		Parse = acceptText,
		Complete = function(request: Types.CompleteRequest): { Types.Suggestion }
			const results: { Types.Suggestion } = {}
			for _, result in Fuzzy.Filter(request.Text, suggestions, candidateKey, request.Limit) do
				table.insert(results, {
					Text = result.Item.Key,
					Display = result.Item.Key,
					Detail = result.Item.Detail,
					Description = result.Item.Description,
					Kind = info.Name,
					Score = result.Score,
					MatchRanges = result.Ranges,
				})
			end
			return results
		end,
		Color = info.Color,
		Icon = info.Icon,
	})
end

--// Manifest
const Manifest = {}

--- Describes the commands `player` may run that clients cannot load themselves: everything except the built-in
--- commands and aliases. Commands from replicated folders are described too, so a client that failed to load one
--- (for example because it requires server code) still gets it. Clients skip the ones they already have.
function Manifest.Describe(shell: Types.Shell, player: Player?): { CommandInfo }
	const commands: { CommandInfo } = {}
	for _, command in shell.Registry:GetCommands() do
		if command._isDefault or command._isAlias or command._remote or not runsOnServer(command) then
			continue
		end
		const ok, allowed = pcall(shell.Permissions.CanRun, shell.Permissions, player, command, nil)
		if ok and allowed then
			table.insert(commands, describeCommand(shell, player, command))
		end
	end
	return commands
end

--- Builds the stand-in for a described command (its subcommands included).
function Manifest.Build(shell: Types.Shell, info: CommandInfo): Types.Command
	const args: { Command.RemoteArg } = {}
	for _, arg in info.Args do
		table.insert(args, {
			Name = arg.Name,
			Kind = arg.Kind,
			Type = buildType(shell, arg.Type),
			Options = arg.Options,
			DefaultDisplay = arg.DefaultDisplay,
		})
	end
	const subcommands: { Types.Command } = {}
	for _, subcommand in info.Subcommands do
		table.insert(subcommands, Manifest.Build(shell, subcommand))
	end
	const returns = info.Returns
	return Command.Remote({
		Name = info.Name,
		Aliases = info.Aliases,
		Description = info.Description,
		Details = info.Details,
		Group = info.Group,
		Icon = info.Icon,
		Examples = info.Examples,
		Hidden = info.Hidden,
		Deprecated = info.Deprecated,
		Destructive = info.Destructive,
		SupportsDryRun = info.SupportsDryRun,
		Pipe = info.Pipe,
		Returns = if returns then buildType(shell, returns) else nil,
		AutoExec = info.AutoExec,
		Args = args,
		Subcommands = subcommands,
		Runs = info.Runs,
	})
end

--- Replaces the stand-ins registered from an earlier manifest with the commands of `infos`. Commands the client
--- loaded itself (the built-ins, its own and the replicated folders) are kept. Returns the names registered.
function Manifest.Apply(shell: Types.Shell, infos: { CommandInfo }): { string }
	const registry = shell.Registry
	for _, command in registry:GetCommands() do
		if command._remote then
			registry:UnregisterCommand(command.Name)
		end
	end

	const names: { string } = {}
	for _, info in infos do
		const existing = registry:GetCommand(info.Name)
		if existing ~= nil and not existing._remote then
			continue
		end
		const ok, built = pcall(Manifest.Build, shell, info)
		if ok then
			registry:RegisterCommand(built)
			table.insert(names, info.Name)
		else
			warn(`[{Constants.Name}] Could not use the server's description of '{info.Name}': {built}`)
		end
	end
	return names
end

return table.freeze(Manifest)
