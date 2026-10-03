--!strict
--[[
	Completion engine: (text, cursor) -> suggestions, replace span, signature hint, diagnostics and a resolution
	preview. Works with the cursor anywhere in the text, inside quotes, inside `${ ... }`, and after pipes/chains.

	Suggestion `Text` from types is the raw value; this module turns it into source text (quoting/escaping as the
	surrounding syntax requires) and computes the span it replaces. The UI derives ghost text and Tab's common
	prefix from the result.
]]

--// Imports
const Command = require("./Command")
const Dispatcher = require("./Dispatcher")
const Fuzzy = require("./Fuzzy")
const Parser = require("./Parser")
const Resolver = require("./Resolver")
const Types = require("./Types")
const Util = require("./Util")

--// Types
type Span = Types.Span

export type CompletionContext = "Command" | "Subcommand" | "Argument" | "Flag" | "FlagValue" | "Operator" | "Variable" | "None"

export type SignaturePart = {
	Text: string,
	Kind: "command" | "required" | "optional" | "flag" | "rest",
	ArgName: string?,
	Active: boolean,
}

export type SignatureHint = {
	Command: string,
	Description: string,
	Parts: { SignaturePart },
	--- Description of the active argument (or the command when none is active).
	ActiveDescription: string?,
	ActiveType: string?,
}

export type ResolutionPreview = {
	Text: string,
	Count: number?,
	Items: { string },
	Ok: boolean,
}

export type CompletionResult = {
	Context: CompletionContext,
	--- Active argument (index into the command's Args).
	ActiveArg: number?,
	Replace: Span,
	--- Text currently typed in the replaced span up to the cursor (the "query").
	Partial: string,
	Suggestions: { Types.Suggestion },
	Signature: SignatureHint?,
	Diagnostics: { read Types.Diagnostic },
	Preview: ResolutionPreview?,
	--- True when the cursor is inside an embedded command.
	Embedded: boolean,
}

export type QueryOptions = {
	Shell: Types.Shell,
	Text: string,
	--- Byte position of the caret (1-based; #Text + 1 is the end).
	Cursor: number,
	Executor: Player?,
	Limit: number?,
	--- Extra score for a suggestion (frecency, history). Receives the suggestion kind and its raw text.
	Boost: ((kind: string, text: string) -> number)?,
	--- Restricts command suggestions (e.g. to commands the player may run).
	CanSee: ((command: Types.Command) -> boolean)?,
}

type Location = {
	Node: Parser.CommandNode?,
	--- Index of the word containing the cursor, if any.
	WordIndex: number?,
	--- Index the next word would take (when the cursor is in whitespace).
	InsertIndex: number,
	PipelinePosition: number,
	Embedded: boolean,
}

--// Constants
const OPERATOR_START = "^[%*%.%?~%%#@!]"
const SPECIAL_VARIABLES = {
	{ Name = "$", Description = "Result of the last command" },
	{ Name = "@", Description = "All alias parameters" },
	{ Name = "1", Description = "First alias parameter" },
}

--// Helpers

const function identity(text: string): string
	return text
end

const function commandName(command: Types.Command): string
	return command.Name
end

type FlagItem = { Text: string, Arg: Types.BoundArg?, Description: string? }

const function flagText(flag: FlagItem): string
	return flag.Text
end

type VariableItem = { Text: string, Detail: string?, Description: string? }

const function variableText(item: VariableItem): string
	return item.Text
end

const function makeLocation(
	node: Parser.CommandNode?,
	wordIndex: number?,
	insertIndex: number,
	position: number,
	embedded: boolean
): Location
	return {
		Node = node,
		WordIndex = wordIndex,
		InsertIndex = insertIndex,
		PipelinePosition = position,
		Embedded = embedded,
	}
end

--- Finds the command node and word under the cursor, descending into embeds.
const function locate(script: Parser.Script, cursor: number, embedded: boolean): Location
	local best = makeLocation(nil, nil, 1, 1, embedded)
	for _, chain in script.Statements do
		for _, pipeline in chain.Pipelines do
			for position, node in pipeline.Commands do
				const words = node.Words
				-- Embeds inside words take precedence when the cursor is inside them.
				for _, word in words do
					for _, part in word.Parts do
						if part.Kind == "Embed"
							and cursor > part.Span.Start + 1
							and (cursor < part.Span.End or not part.Terminated) then
							return locate(part.Script, cursor, true)
						end
					end
				end
				if #words == 0 then
					if cursor >= node.Span.Start then
						best = makeLocation(node, nil, 1, position, embedded)
					end
					continue
				end
				if cursor < words[1].Span.Start then
					continue
				end
				local wordIndex: number? = nil
				local insertIndex = #words + 1
				for index, word in words do
					if cursor >= word.Span.Start and cursor <= word.Span.End then
						wordIndex = index
						break
					elseif cursor < word.Span.Start then
						insertIndex = index
						break
					end
				end
				best = makeLocation(node, wordIndex, if wordIndex then wordIndex else insertIndex, position, embedded)
			end
		end
	end
	return best
end

--- Converts a raw value into source text for the given quoting context.
const function toSource(raw: string, openQuote: string?, listable: boolean): string
	if openQuote == '"' then
		return (raw:gsub("[\\\"$]", "\\%0"))
	elseif openQuote == "'" then
		return (raw:gsub("[\\']", "\\%0"))
	elseif openQuote == '"""' then
		return raw
	end
	if listable then
		return Dispatcher.EscapeBare(raw)
	end
	return Util.Quote(raw)
end

const function signatureOf(command: Types.Command, activeName: string?): SignatureHint
	const parts: { SignaturePart } = {
		{ Text = Command.FullName(command), Kind = "command", Active = activeName == nil },
	}
	local activeDescription: string? = command.Description
	local activeType: string? = nil
	for _, arg in command.Args do
		if arg.Options.Hidden then
			continue
		end
		const typeName = arg.Type.Name
		local text: string
		local kind: "required" | "optional" | "flag" | "rest"
		if arg.Kind == "flag" then
			text = `[--{arg.Name}]`
			kind = "flag"
		elseif not arg.Positional then
			text = `[--{arg.Name} <{typeName}>]`
			kind = "flag"
		elseif arg.Kind == "required" then
			text = `<{arg.Name}: {typeName}>`
			kind = "required"
		elseif arg.Kind == "rest" then
			text = `<...{arg.Name}: {typeName}>`
			kind = "rest"
		elseif arg.Kind == "default" then
			text = `[{arg.Name}: {typeName} = {arg.DefaultDisplay or "?"}]`
			kind = "optional"
		else
			text = `[{arg.Name}: {typeName}]`
			kind = "optional"
		end
		const active = arg.Name == activeName
		if active then
			activeDescription = arg.Options.Description or arg.Type.Description
			activeType = typeName
		end
		table.insert(parts, { Text = text, Kind = kind, ArgName = arg.Name, Active = active })
	end
	return {
		Command = Command.FullName(command),
		Description = command.Description,
		Parts = parts,
		ActiveDescription = activeDescription,
		ActiveType = activeType,
	}
end

const function previewOf(resolved: Types.ResolvedArg): ResolutionPreview?
	if not resolved.Present or resolved.Deferred then
		return nil
	end
	if not resolved.Ok then
		return { Text = resolved.Error or "Invalid", Items = {}, Ok = false }
	end
	const value = resolved.Value
	if type(value) == "table" and resolved.Type and resolved.Type.Listable then
		const items: { string } = {}
		local count = 0
		for _, item in pairs(value) do
			count += 1
			table.insert(items, Util.FormatValue(item))
		end
		const noun = resolved.Type.Name
		if count == 1 then
			return { Text = items[1], Count = 1, Items = items, Ok = true }
		end
		return { Text = `{count} {noun}`, Count = count, Items = items, Ok = true }
	end
	const display = resolved.Display or Util.FormatValue(value)
	return { Text = display, Items = { display }, Ok = true }
end

const function rank(suggestions: { Types.Suggestion }, boost: ((kind: string, text: string) -> number)?, limit: number)
	if boost then
		for _, suggestion in suggestions do
			suggestion.Score += boost(suggestion.Kind, suggestion.Text)
		end
	end
	table.sort(suggestions, function(a: Types.Suggestion, b: Types.Suggestion): boolean
		if a.Score ~= b.Score then
			return a.Score > b.Score
		end
		return a.Display < b.Display
	end)
	while #suggestions > limit do
		table.remove(suggestions)
	end
end

--// Completion
const Completion = {}

--- Computes completions at the cursor. Never errors, never yields.
function Completion.Query(options: QueryOptions): CompletionResult
	const shell = options.Shell
	const text = options.Text
	const cursor = Util.Clamp(options.Cursor, 1, #text + 1)
	const limit = options.Limit or 50
	const parsed = Parser.Parse(text)
	const location = locate(parsed.Script, cursor, false)
	const evaluation = shell.Dispatcher:Evaluate({ Text = text, Executor = options.Executor })
	const result: CompletionResult = {
		Context = "None",
		ActiveArg = nil,
		Replace = { Start = cursor, End = cursor },
		Partial = "",
		Suggestions = {},
		Signature = nil,
		Diagnostics = evaluation.Diagnostics,
		Preview = nil,
		Embedded = location.Embedded,
	}

	const node = location.Node
	const wordIndex = location.WordIndex
	const word: Parser.Word? = if node and wordIndex then node.Words[wordIndex] else nil

	-- Command names.
	if node == nil or location.InsertIndex == 1 then
		const span: Span = if word then word.Span else { Start = cursor, End = cursor }
		const partial = if word then text:sub(word.Span.Start, cursor - 1) else ""
		result.Context = "Command"
		result.Replace = span
		result.Partial = partial
		const query = Fuzzy.PrepareQuery(partial)
		for _, command in shell.Registry:GetCommands() do
			if command.Hidden or (options.CanSee and not options.CanSee(command)) then
				continue
			end
			local best: Types.FuzzyMatch? = Fuzzy.Match(query, Fuzzy.PrepareCached(command.Name))
			local via: string? = nil
			for _, alias in command.Aliases do
				const match = Fuzzy.Match(query, Fuzzy.PrepareCached(alias))
				if match and (best == nil or match.Score > best.Score + 1) then
					best = match
					via = alias
				end
			end
			if best then
				table.insert(result.Suggestions, {
					Text = via or command.Name,
					Display = via or command.Name,
					Detail = if via then `alias of {command.Name}` else command.Group,
					Description = command.Description,
					Kind = if via then "alias" else "command",
					Score = best.Score,
					MatchRanges = best.Ranges,
					Deprecated = command.Deprecated ~= nil,
					Icon = command.Icon or "command",
				})
			end
		end
		rank(result.Suggestions, options.Boost, limit)
		return result
	end

	-- Resolve the command for argument context.
	const resolution = Resolver.Resolve(node, {
		Shell = shell,
		Executor = options.Executor,
		Final = false,
		Provider = nil,
		PipeExpected = location.PipelinePosition > 1,
	})
	const command = resolution.Command
	if command == nil then
		return result
	end

	const insertIndex = location.InsertIndex
	const binding = if wordIndex then resolution.Bindings[wordIndex] else nil
	const span: Span = if word then { Start = word.Span.Start, End = word.Span.End }
		else { Start = cursor, End = cursor }
	local partialStart = span.Start
	local openQuote: string? = nil
	if word and word.OpenQuote then
		openQuote = word.OpenQuote.Quote
		partialStart = word.OpenQuote.Span.End
		span.Start = partialStart
		if word.OpenQuote.Terminated then
			span.End = math.max(partialStart, word.Span.End - #openQuote)
		end
	end
	const partial = text:sub(partialStart, cursor - 1)
	result.Replace = span
	result.Partial = partial

	-- Subcommands right after the command name.
	if #command.Subcommands > 0
		and insertIndex == resolution.FirstArgWord
		and (binding == nil or binding.Role ~= "subcommand") then
		result.Context = "Subcommand"
		const names: { Types.Command } = {}
		for _, sub in command.Subcommands do
			if not sub.Hidden then
				table.insert(names, sub)
			end
		end
		for _, ranked in Fuzzy.Filter(partial, names, commandName, limit) do
			table.insert(result.Suggestions, {
				Text = ranked.Item.Name,
				Display = ranked.Item.Name,
				Detail = "subcommand",
				Description = ranked.Item.Description,
				Kind = "subcommand",
				Score = ranked.Score,
				MatchRanges = ranked.Ranges,
				Icon = ranked.Item.Icon or "command",
			})
		end
	elseif binding and binding.Role == "subcommand" and word then
		result.Context = "Subcommand"
		const parent = command._parent
		if parent then
			const siblings: { Types.Command } = {}
			for _, sibling in parent.Subcommands do
				table.insert(siblings, sibling)
			end
			for _, ranked in Fuzzy.Filter(partial, siblings, commandName, limit) do
				table.insert(result.Suggestions, {
					Text = ranked.Item.Name,
					Display = ranked.Item.Name,
					Kind = "subcommand",
					Score = ranked.Score,
					MatchRanges = ranked.Ranges,
					Description = ranked.Item.Description,
					Icon = ranked.Item.Icon or "command",
				})
			end
		end
	end

	-- Determine the active argument.
	local activeArg: Types.BoundArg? = nil
	local valueOffset = 0
	if binding
		and binding.Arg
		and (binding.Role == "positional" or binding.Role == "named" or binding.Role == "flagValue") then
		activeArg = binding.Arg
		valueOffset = binding.ValueOffset or 0
	elseif binding and binding.Role == "flag" and binding.Arg and binding.ValueOffset then
		activeArg = binding.Arg
		valueOffset = binding.ValueOffset
	elseif wordIndex == nil or (binding and binding.Role == "extra") then
		-- A new word: the previous word may be a flag waiting for its value.
		const previous = resolution.Bindings[insertIndex - 1]
		if previous
			and previous.Role == "flag"
			and previous.Arg
			and previous.Arg.Kind ~= "flag"
			and previous.ValueOffset == nil then
			activeArg = previous.Arg
			result.Context = "FlagValue"
		else
			const used: { [string]: boolean } = {}
			for index, bound in resolution.Bindings do
				if bound.Arg and index < insertIndex then
					used[bound.Arg.Name] = true
				end
			end
			for _, arg in command.Args do
				if arg.Positional
					and not used[arg.Name]
					and not (arg.Name == command.Pipe and location.PipelinePosition > 1) then
					activeArg = arg
					break
				end
				if arg.Kind == "rest" and arg.Positional then
					activeArg = arg
					break
				end
			end
		end
	end

	-- Flags.
	const trimmedPartial = partial:sub(valueOffset + 1)
	if (word == nil or not word.Quoted) and partial:sub(1, 1) == "-" and (binding == nil or binding.ValueOffset == nil) then
		result.Context = "Flag"
		activeArg = nil
		const used: { [string]: boolean } = {}
		for _, bound in resolution.Bindings do
			if bound.Arg and bound ~= binding then
				used[bound.Arg.Name] = true
			end
		end
		const flags: { FlagItem } = {}
		for _, arg in command.Args do
			if not used[arg.Name] and not arg.Options.Hidden then
				table.insert(flags, { Text = "--" .. arg.Name, Arg = arg, Description = arg.Options.Description })
				if arg.Options.Short then
					table.insert(flags, {
						Text = "-" .. arg.Options.Short,
						Arg = arg,
						Description = arg.Options.Description,
					})
				end
			end
		end
		if command.SupportsDryRun then
			table.insert(flags, { Text = "--dry", Arg = nil, Description = "Preview without running" })
		end
		if command.Destructive or command.Args[1] then
			table.insert(flags, { Text = "--yes", Arg = nil, Description = "Skip confirmations" })
		end
		for _, ranked in Fuzzy.Filter(partial, flags, flagText, limit) do
			const flag = ranked.Item
			const arg = flag.Arg
			table.insert(result.Suggestions, {
				Text = flag.Text,
				Display = flag.Text,
				Detail = if arg then (if arg.Kind == "flag" then "flag" else `<{arg.Type.Name}>`) else "global",
				Description = flag.Description,
				Kind = "flag",
				Score = ranked.Score,
				MatchRanges = ranked.Ranges,
				Icon = "flag",
				Partial = arg ~= nil and arg.Kind ~= "flag",
			})
		end
		result.Signature = signatureOf(command, nil)
		rank(result.Suggestions, options.Boost, limit)
		return result
	end

	-- Variables.
	if word and #word.Parts > 0 then
		const lastPart = word.Parts[#word.Parts]
		if lastPart.Kind == "Variable" and cursor == lastPart.Span.End then
			result.Context = "Variable"
			result.Replace = { Start = lastPart.Span.Start, End = lastPart.Span.End }
			result.Partial = text:sub(lastPart.Span.Start, cursor - 1)
			const items: { VariableItem } = {}
			for name, value in shell:GetSession(options.Executor).Variables do
				table.insert(items, { Text = "$" .. name, Detail = Util.Truncate(value, 24), Description = "Variable" })
			end
			for _, definition in shell.Registry:GetFunctions() do
				table.insert(items, {
					Text = "$" .. definition.Name,
					Detail = "function",
					Description = definition.Description,
				})
			end
			for _, special in SPECIAL_VARIABLES do
				table.insert(items, {
					Text = "$" .. special.Name,
					Detail = "special",
					Description = special.Description,
				})
			end
			for _, ranked in Fuzzy.Filter(result.Partial, items, variableText, limit) do
				table.insert(result.Suggestions, {
					Text = ranked.Item.Text,
					Display = ranked.Item.Text,
					Detail = ranked.Item.Detail,
					Description = ranked.Item.Description,
					Kind = "variable",
					Score = ranked.Score,
					MatchRanges = ranked.Ranges,
					Icon = "variable",
				})
			end
			rank(result.Suggestions, options.Boost, limit)
			return result
		end
	end

	-- Argument values.
	if activeArg then
		if result.Context ~= "FlagValue" then
			result.Context = if trimmedPartial:match(OPERATOR_START) then "Operator" else "Argument"
		end
		for index, arg in command.Args do
			if arg == activeArg then
				result.ActiveArg = index
			end
		end
		local argType = activeArg.Type
		for _, resolved in resolution.Args do
			if resolved.Arg == activeArg then
				if resolved.Type then
					argType = resolved.Type
				end
				if word then
					result.Preview = previewOf(resolved)
				end
			end
		end
		if valueOffset > 0 and word then
			result.Replace = { Start = word.Span.Start + valueOffset, End = span.End }
		end
		const ok, suggestions = pcall(argType.Complete, {
			Text = trimmedPartial,
			Quoted = openQuote ~= nil,
			Executor = options.Executor,
			Shell = shell.Handle,
			Platform = shell.Platform,
			Limit = limit,
			ArgName = activeArg.Name,
		})
		if ok then
			for _, suggestion in suggestions do
				if not suggestion.Kind:match("^operator") or openQuote == nil then
					if suggestion.Kind ~= "operator" then
						suggestion.Text = toSource(suggestion.Text, openQuote, argType.Listable)
					end
					table.insert(result.Suggestions, suggestion)
				end
			end
		end
		result.Signature = signatureOf(command, activeArg.Name)
	elseif result.Signature == nil then
		result.Signature = signatureOf(command, nil)
	end

	rank(result.Suggestions, options.Boost, limit)
	return result
end

--- Longest common prefix of suggestion texts that extend `partial` (for Tab's first press).
function Completion.CommonPrefix(suggestions: { Types.Suggestion }, partial: string): string?
	local prefix: string? = nil
	const loweredPartial = partial:lower()
	for _, suggestion in suggestions do
		const candidate = suggestion.Text
		if candidate:lower():sub(1, #loweredPartial) ~= loweredPartial then
			return nil
		end
		if prefix == nil then
			prefix = candidate
		else
			local length = 0
			const current: string = prefix
			while length < #current
				and length < #candidate
				and current:sub(length + 1, length + 1):lower() == candidate:sub(length + 1, length + 1):lower() do
				length += 1
			end
			prefix = current:sub(1, length)
		end
	end
	if prefix and #prefix > #partial then
		return prefix
	end
	return nil
end

--- Ghost text: the rest of the top suggestion when it extends what was typed (case-insensitively).
function Completion.Ghost(result: CompletionResult): string?
	const top = result.Suggestions[1]
	if top == nil then
		return nil
	end
	const partial = result.Partial
	if #top.Text > #partial and top.Text:lower():sub(1, #partial) == partial:lower() then
		return top.Text:sub(#partial + 1)
	end
	return nil
end

Completion.Identity = identity

return table.freeze(Completion)
