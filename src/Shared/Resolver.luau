--!strict
--[[
	Resolver: binds one command node of the AST to a registered command and turns its words into typed values.

	- The first word names the command (aliases and subcommands are followed).
	- Words are classified as flags (`--name`, `--name=value`, `-abc` clusters, `-n value`), named arguments
	  (`name=value`), the end-of-options marker `--`, global flags (`--dry`, `--yes`) and positionals.
	- Positionals bind to positional arguments in order; a rest argument collects the remainder; excess words are
	  merged into a trailing string argument (so `announce hello world` works without quotes).
	- Piped input binds to the command's pipe argument (type-checked); variables and embedded commands are
	  substituted through a `Provider` (absent during live validation, where they are reported as deferred).
	- Every problem becomes a diagnostic with a span; resolution never errors.
]]

--// Imports
const Fuzzy = require("./Fuzzy")
const Parser = require("./Parser")
const Types = require("./Types")
const Util = require("./Util")

--// Types
type Span = Types.Span

export type Substitution = {
	Text: string,
	--- True when the text cannot be known yet (embedded command or reference during live validation).
	Deferred: boolean,
	--- Structured value, when the whole word is one variable/embed that produced a typed value.
	Value: unknown,
	Type: Types.Type<unknown>?,
	Error: string?,
	--- Server-held reference for the value (lets a client forward it without sending the value).
	Ref: string?,
}

export type Provider = {
	Variable: (part: Parser.VariablePart) -> Substitution,
	Embed: (part: Parser.EmbedPart) -> Substitution,
}

export type WordRole = "command" | "subcommand" | "positional" | "named" | "flag" | "flagValue" | "global" | "separator" | "extra" | "unknown"

export type WordBinding = {
	Word: Parser.Word,
	Index: number,
	Role: WordRole,
	Arg: Types.BoundArg?,
	--- For `--name=value` and `name=value`: byte offset (from the word start) where the value begins.
	ValueOffset: number?,
}

export type ResolveOptions = {
	Shell: Types.Shell,
	Executor: Player?,
	--- True right before execution (defaults computed, expensive validation allowed).
	Final: boolean,
	--- Substitutes variables and embeds. Without one, they are deferred.
	Provider: Provider?,
	Piped: Types.PipedInput?,
	--- True when this command receives piped input whose value is not known yet (live validation).
	PipeExpected: boolean?,
}

export type Resolution = {
	Node: Parser.CommandNode,
	Command: Types.Command?,
	Name: string,
	NameSpan: Span,
	Bindings: { WordBinding },
	Args: { Types.ResolvedArg },
	Values: Types.ArgValues,
	Diagnostics: { Types.Diagnostic },
	Ok: boolean,
	Dry: boolean,
	Yes: boolean,
	--- Index of the first word after the command and subcommand names.
	FirstArgWord: number,
}

type Bound = {
	Arg: Types.BoundArg,
	Words: { Parser.Word },
	--- Offset into the first word's first text part where the value starts (named/inline forms).
	ValueOffset: number?,
	FlagTrue: boolean,
	Piped: Types.PipedInput?,
	PipeDeferred: boolean,
	Span: Span,
}

--// Constants
const SHORT_CLUSTER_PATTERN = "^%-(%a+)$"
const NAMED_PATTERN = "^([%a_][%w_%-]*)=(.*)$"

--// Helpers

const function diagnostic(
	list: { Types.Diagnostic },
	message: string,
	span: Span,
	severity: Types.Severity?,
	code: string?
)
	list[#list + 1] = { Severity = severity or "error", Message = message, Span = span, Code = code or "resolve" }
end

--- Literal unquoted text of a word, or nil when it has quotes, variables or embeds.
const function literal(word: Parser.Word): string?
	if word.Static and not word.Quoted then
		for _, part in word.Parts do
			if part.Kind == "Text" and part.Quoted then
				return nil
			end
		end
		return word.Value
	end
	return nil
end

--- The leading unquoted text of a word (for `name=value` detection), or nil.
const function leadingText(word: Parser.Word): string?
	const first = word.Parts[1]
	if first and first.Kind == "Text" and not first.Quoted then
		return first.Value
	end
	return nil
end

--- Substitutes a word (starting `offset` bytes into its first text part) into text and, when the word is a single
--- variable/embed, a structured value.
const function substitute(word: Parser.Word, offset: number, provider: Provider?): Substitution
	const parts = word.Parts
	if #parts == 1 and offset == 0 then
		const only = parts[1]
		if only.Kind ~= "Text" then
			if provider == nil then
				return { Text = word.Value, Deferred = true, Value = nil }
			end
			return if only.Kind == "Variable" then provider.Variable(only) else provider.Embed(only)
		end
	end
	const pieces: { string } = {}
	for index, part in parts do
		if part.Kind == "Text" then
			table.insert(pieces, if index == 1 then part.Value:sub(offset + 1) else part.Value)
		else
			if provider == nil then
				return { Text = word.Value, Deferred = true, Value = nil }
			end
			const result = if part.Kind == "Variable" then provider.Variable(part) else provider.Embed(part)
			if result.Deferred or result.Error then
				return { Text = word.Value, Deferred = result.Deferred, Value = nil, Error = result.Error }
			end
			table.insert(pieces, result.Text)
		end
	end
	return { Text = table.concat(pieces), Deferred = false, Value = nil }
end

--- True when a value of type `from` can be used directly for an argument of type `to`.
const function assignable(from: Types.TypeInfo, to: Types.TypeInfo): boolean
	if from.Id == to.Id then
		return true
	end
	const element = to.Element
	return to.Kind == "optional" and element ~= nil and element.Id == from.Id
end

const function makeRequest(options: ResolveOptions, text: string, quoted: boolean, span: Span, argName: string?): Types.ParseRequest
	return {
		Text = text,
		Quoted = quoted,
		Span = span,
		Executor = options.Executor,
		Shell = options.Shell.Handle,
		Platform = options.Shell.Platform,
		Final = options.Final,
		ArgName = argName,
	}
end

--- Finds a (sub)command by name or alias among `commands`.
const function findSubcommand(commands: { read Types.Command }, name: string): Types.Command?
	const lowered = name:lower()
	for _, command in commands do
		if command.Name:lower() == lowered then
			return command
		end
		for _, alias in command.Aliases do
			if alias:lower() == lowered then
				return command
			end
		end
	end
	return nil
end

const function hasHandler(command: Types.Command): boolean
	return command._run ~= nil or command._clientRun ~= nil or command._isAlias
end

const function subcommandNames(command: Types.Command): { string }
	const names: { string } = {}
	for _, sub in command.Subcommands do
		if not sub.Hidden then
			table.insert(names, sub.Name)
		end
	end
	return names
end

--// Resolver
const Resolver = {}

Resolver.Assignable = assignable
Resolver.Substitute = substitute

--- Resolves a command node. Never errors.
function Resolver.Resolve(node: Parser.CommandNode, options: ResolveOptions): Resolution
	const shell = options.Shell
	const locale = shell.Locale
	const diagnostics: { Types.Diagnostic } = {}
	const bindings: { WordBinding } = {}
	const values: Types.ArgValues = {}
	const resolvedArgs: { Types.ResolvedArg } = {}
	const words = node.Words
	const endSpan: Span = { Start = node.Span.End, End = node.Span.End }

	const resolution: Resolution = {
		Node = node,
		Command = nil,
		Name = "",
		NameSpan = node.Span,
		Bindings = bindings,
		Args = resolvedArgs,
		Values = values,
		Diagnostics = diagnostics,
		Ok = false,
		Dry = false,
		Yes = false,
		FirstArgWord = 2,
	}

	if #words == 0 then
		diagnostic(diagnostics, locale:Get("resolve.emptyCommand"), node.Span)
		return resolution
	end

	-- Command name.
	const nameWord = words[1]
	resolution.NameSpan = nameWord.Span
	bindings[1] = { Word = nameWord, Index = 1, Role = "command" }
	const name = literal(nameWord)
	if name == nil then
		resolution.Name = nameWord.Value
		diagnostic(diagnostics, locale:Get("resolve.dynamicCommandName"), nameWord.Span)
		return resolution
	end
	resolution.Name = name
	local command = shell.Registry:GetCommand(name)
	if command == nil then
		const suggestion = Fuzzy.Suggest(name, shell.Registry:GetCommandNames(true))
		diagnostic(
			diagnostics,
			if suggestion then locale:Get("resolve.unknownCommandSuggestion", { name = name, suggestion = suggestion })
				else locale:Get("resolve.unknownCommand", { name = name }),
			nameWord.Span
		)
		for index = 2, #words do
			bindings[index] = { Word = words[index], Index = index, Role = "unknown" }
		end
		return resolution
	end

	-- Subcommands.
	local index = 2
	while #command.Subcommands > 0 and index <= #words do
		const text = literal(words[index])
		const sub = if text then findSubcommand(command.Subcommands, text) else nil
		if sub == nil then
			if not hasHandler(command) and #command.Args == 0 then
				const options = subcommandNames(command)
				const suggestion = if text then Fuzzy.Suggest(text, options) else nil
				diagnostic(
					diagnostics,
					if suggestion then `Unknown subcommand '{words[index].Value}'. Did you mean '{suggestion}'?`
						else `Unknown subcommand '{words[index].Value}' (expected {table.concat(options, " | ")})`,
					words[index].Span
				)
			end
			break
		end
		command = sub
		bindings[index] = { Word = words[index], Index = index, Role = "subcommand" }
		index += 1
	end
	const target: Types.Command = command
	resolution.Command = target
	resolution.FirstArgWord = index
	if #target.Subcommands > 0 and not hasHandler(target) and #target.Args == 0 and index > #words then
		diagnostic(diagnostics, `Expected a subcommand: {table.concat(subcommandNames(target), " | ")}`, endSpan)
	end

	-- Argument lookup tables.
	const argsByName: { [string]: Types.BoundArg } = {}
	const argsByShort: { [string]: Types.BoundArg } = {}
	const argNames: { string } = {}
	for _, arg in target.Args do
		argsByName[arg.Name:lower()] = arg
		table.insert(argNames, arg.Name)
		if arg.Options.Short then
			argsByShort[arg.Options.Short] = arg
		end
	end

	const bound: { [string]: Bound } = {}
	const positionalWords: { { Word: Parser.Word, Index: number } } = {}

	const function bindNamed(
		arg: Types.BoundArg,
		word: Parser.Word,
		wordIndex: number,
		role: WordRole,
		valueOffset: number?
	): boolean
		if bound[arg.Name] then
			diagnostic(diagnostics, locale:Get("resolve.duplicateArgument", { name = arg.Name }), word.Span)
			return false
		end
		bound[arg.Name] = {
			Arg = arg,
			Words = { word },
			ValueOffset = valueOffset,
			FlagTrue = false,
			PipeDeferred = false,
			Span = word.Span,
		}
		bindings[wordIndex] = { Word = word, Index = wordIndex, Role = role, Arg = arg, ValueOffset = valueOffset }
		return true
	end

	-- Classify words.
	local endOfOptions = false
	while index <= #words do
		const word = words[index]
		const text = literal(word)
		const leading = leadingText(word)

		if not endOfOptions and text == "--" then
			endOfOptions = true
			bindings[index] = { Word = word, Index = index, Role = "separator" }
			index += 1
			continue
		end

		if not endOfOptions and leading and leading:sub(1, 2) == "--" and #leading > 2 then
			const body = leading:sub(3)
			const key, inlineValue = body:match("^([^=]+)=(.*)$")
			const flagName = (key or body):lower()
			const arg = argsByName[flagName]
			if arg == nil and inlineValue == nil and text and (flagName == "dry" or flagName == "yes") then
				if flagName == "dry" then
					resolution.Dry = true
				else
					resolution.Yes = true
				end
				bindings[index] = { Word = word, Index = index, Role = "global" }
				index += 1
				continue
			end
			if arg == nil then
				const suggestion = Fuzzy.Suggest(key or body, argNames)
				diagnostic(
					diagnostics,
					if suggestion then locale:Get("resolve.unknownFlagSuggestion", {
							flag = "--" .. (key or body),
							suggestion = suggestion,
						})
						else locale:Get("resolve.unknownFlag", { flag = "--" .. (key or body) }),
					word.Span
				)
				bindings[index] = { Word = word, Index = index, Role = "unknown" }
				index += 1
				continue
			end
			if inlineValue ~= nil and key ~= nil then
				bindNamed(arg, word, index, "flag", 2 + #key + 1)
				index += 1
			elseif arg.Kind == "flag" then
				if bindNamed(arg, word, index, "flag", nil) then
					bound[arg.Name].FlagTrue = true
				end
				index += 1
			else
				bindings[index] = { Word = word, Index = index, Role = "flag", Arg = arg }
				const valueWord = words[index + 1]
				if valueWord == nil then
					diagnostic(
						diagnostics,
						locale:Get("resolve.flagNeedsValue", { name = arg.Name, type = arg.Type.Name }),
						word.Span
					)
					index += 1
				else
					if bound[arg.Name] then
						diagnostic(diagnostics, locale:Get("resolve.duplicateArgument", { name = arg.Name }), word.Span)
					else
						bound[arg.Name] = {
							Arg = arg,
							Words = { valueWord },
							FlagTrue = false,
							PipeDeferred = false,
							Span = valueWord.Span,
						}
					end
					bindings[index + 1] = { Word = valueWord, Index = index + 1, Role = "flagValue", Arg = arg }
					index += 2
				end
			end
			continue
		end

		const cluster = if not endOfOptions and text then text:match(SHORT_CLUSTER_PATTERN) else nil
		if cluster then
			local consumedNext = false
			bindings[index] = { Word = word, Index = index, Role = "flag" }
			for position = 1, #cluster do
				const short = cluster:sub(position, position)
				const arg = argsByShort[short]
				if arg == nil then
					if short == "y" and argsByShort.y == nil then
						resolution.Yes = true
					else
						diagnostic(diagnostics, locale:Get("resolve.unknownFlag", { flag = "-" .. short }), word.Span)
					end
				elseif arg.Kind == "flag" then
					if bindNamed(arg, word, index, "flag", nil) then
						bound[arg.Name].FlagTrue = true
					end
				elseif position == #cluster and words[index + 1] then
					const valueWord = words[index + 1]
					if bound[arg.Name] == nil then
						bound[arg.Name] = {
							Arg = arg,
							Words = { valueWord },
							FlagTrue = false,
							PipeDeferred = false,
							Span = valueWord.Span,
						}
					else
						diagnostic(diagnostics, locale:Get("resolve.duplicateArgument", { name = arg.Name }), word.Span)
					end
					bindings[index] = { Word = word, Index = index, Role = "flag", Arg = arg }
					bindings[index + 1] = { Word = valueWord, Index = index + 1, Role = "flagValue", Arg = arg }
					consumedNext = true
				else
					diagnostic(
						diagnostics,
						locale:Get("resolve.flagNeedsValue", { name = arg.Name, type = arg.Type.Name }),
						word.Span
					)
				end
			end
			index += if consumedNext then 2 else 1
			continue
		end

		if not endOfOptions and leading then
			const key = leading:match(NAMED_PATTERN)
			const arg = if key then argsByName[key:lower()] else nil
			if key and arg and arg.Kind ~= "flag" then
				bindNamed(arg, word, index, "named", #key + 1)
				index += 1
				continue
			end
		end

		table.insert(positionalWords, { Word = word, Index = index })
		index += 1
	end

	-- Bind positionals.
	local nextWord = 1
	local lastPositional: Types.BoundArg? = nil
	const pipeFilled = options.Piped ~= nil or options.PipeExpected == true

	--- True when a static word parses as `arg`'s type (used to decide whether an optional argument is skipped).
	const function parsesAs(arg: Types.BoundArg, word: Parser.Word): boolean
		if not word.Static or arg.Kind == "dynamic" or arg.Kind == "rest" or arg.Kind == "flag" then
			return false
		end
		const ok, result = pcall(arg.Type.Parse, makeRequest(options, word.Value, word.Quoted, word.Span, arg.Name))
		return ok and result.Ok
	end

	--- Positional arguments from `start` on that still need a word.
	const function openPositionals(start: number): { Types.BoundArg }
		const list: { Types.BoundArg } = {}
		for position = start, #target.Args do
			const candidate = target.Args[position]
			if candidate.Positional and not bound[candidate.Name] and not (pipeFilled and candidate.Name == target.Pipe) then
				table.insert(list, candidate)
			end
		end
		return list
	end

	for argIndex, arg in target.Args do
		if not arg.Positional or bound[arg.Name] then
			continue
		end
		-- Type-directed skipping: with fewer words than open positional arguments, an optional argument is left
		-- to its default when the word does not fit it but fits the next one (`give ~sw 3` gives to yourself).
		if (arg.Kind == "optional" or arg.Kind == "default") and nextWord <= #positionalWords then
			const open = openPositionals(argIndex)
			const remainingWords = #positionalWords - nextWord + 1
			const following = open[2]
			if remainingWords < #open and following and following.Kind ~= "rest" then
				const word = positionalWords[nextWord].Word
				if not parsesAs(arg, word) and parsesAs(following, word) then
					continue
				end
			end
		end
		if arg.Kind == "rest" then
			const restWords: { Parser.Word } = {}
			while nextWord <= #positionalWords do
				const item = positionalWords[nextWord]
				table.insert(restWords, item.Word)
				bindings[item.Index] = { Word = item.Word, Index = item.Index, Role = "positional", Arg = arg }
				nextWord += 1
			end
			if #restWords > 0 then
				bound[arg.Name] = {
					Arg = arg,
					Words = restWords,
					FlagTrue = false,
					PipeDeferred = false,
					Span = { Start = restWords[1].Span.Start, End = restWords[#restWords].Span.End },
				}
			end
			lastPositional = nil
			break
		end
		if arg.Name == target.Pipe and (options.Piped or options.PipeExpected) then
			-- The pipe argument is filled by the piped value; don't consume a word for it.
			continue
		end
		if nextWord > #positionalWords then
			break
		end
		const item = positionalWords[nextWord]
		bound[arg.Name] = {
			Arg = arg,
			Words = { item.Word },
			FlagTrue = false,
			PipeDeferred = false,
			Span = item.Word.Span,
		}
		bindings[item.Index] = { Word = item.Word, Index = item.Index, Role = "positional", Arg = arg }
		lastPositional = arg
		nextWord += 1
	end

	-- Excess words: merge into a trailing string argument, else report.
	if nextWord <= #positionalWords then
		local mergeTarget: Bound? = nil
		if lastPositional and lastPositional.Type.Kind == "string" then
			-- Only when it is the last positional argument.
			local isLast = true
			local seen = false
			for _, arg in target.Args do
				if arg == lastPositional then
					seen = true
				elseif seen and arg.Positional then
					isLast = false
				end
			end
			if isLast then
				mergeTarget = bound[lastPositional.Name]
			end
		end
		if mergeTarget then
			while nextWord <= #positionalWords do
				const item = positionalWords[nextWord]
				table.insert(mergeTarget.Words, item.Word)
				bindings[item.Index] = {
					Word = item.Word,
					Index = item.Index,
					Role = "positional",
					Arg = mergeTarget.Arg,
				}
				mergeTarget.Span = { Start = mergeTarget.Span.Start, End = item.Word.Span.End }
				nextWord += 1
			end
		else
			while nextWord <= #positionalWords do
				const item = positionalWords[nextWord]
				bindings[item.Index] = { Word = item.Word, Index = item.Index, Role = "extra" }
				diagnostic(
					diagnostics,
					locale:Get("resolve.tooManyArguments", { text = item.Word.Value }),
					item.Word.Span
				)
				nextWord += 1
			end
		end
	end

	-- Piped input.
	if options.Piped or options.PipeExpected then
		const pipeName = target.Pipe
		const pipeArg = if pipeName then argsByName[pipeName:lower()] else nil
		if pipeArg == nil then
			diagnostic(diagnostics, locale:Get("resolve.noPipeArgument", { command = target.Name }), nameWord.Span)
		elseif bound[pipeArg.Name] == nil then
			bound[pipeArg.Name] = {
				Arg = pipeArg,
				Words = {},
				FlagTrue = false,
				Piped = options.Piped,
				PipeDeferred = options.Piped == nil,
				Span = nameWord.Span,
			}
		end
	end

	-- Evaluate arguments in declaration order.
	const previous: { [string]: unknown } = {}
	for _, arg in target.Args do
		const entry = bound[arg.Name]
		local argType: Types.Type<unknown> = arg.Type

		if arg.Kind == "dynamic" and arg.Resolve then
			const ok, dynamicType = pcall(arg.Resolve, {
				Shell = shell.Handle,
				Platform = shell.Platform,
				Executor = options.Executor,
				Previous = table.freeze(table.clone(previous)),
			})
			if ok and dynamicType then
				argType = dynamicType
			elseif entry then
				diagnostic(diagnostics, locale:Get("resolve.dynamicUnavailable"), entry.Span, "warning")
				table.insert(resolvedArgs, {
					Arg = arg,
					Present = true,
					Ok = false,
					Value = nil,
					Error = locale:Get("resolve.dynamicUnavailable"),
					Span = entry.Span,
					Deferred = true,
					Type = nil,
				})
				continue
			end
		end

		if entry == nil then
			-- Omitted.
			local value: unknown = nil
			if arg.Kind == "required" then
				-- `missing`: the console stays quiet about it while the caret is where the argument goes.
				diagnostic(
					diagnostics,
					locale:Get("resolve.missingArgument", { name = arg.Name, type = argType.Name }),
					endSpan,
					"error",
					"missing"
				)
			elseif arg.Kind == "flag" then
				value = false
			elseif arg.Kind == "rest" then
				value = {}
			elseif arg.Kind == "default" and arg.DefaultValue and options.Final then
				const ok, computed = pcall(arg.DefaultValue, makeRequest(options, "", false, endSpan, arg.Name))
				if ok then
					value = computed
				else
					diagnostic(diagnostics, `Default for '{arg.Name}' failed: {computed}`, endSpan)
				end
			end
			values[arg.Name] = value
			previous[arg.Name] = value
			table.insert(resolvedArgs, {
				Arg = arg,
				Present = false,
				Ok = arg.Kind ~= "required",
				Value = value,
				Display = if arg.Kind == "default" then arg.DefaultDisplay else nil,
				Deferred = false,
				Type = argType,
			})
			continue
		end

		if entry.FlagTrue then
			values[arg.Name] = true
			previous[arg.Name] = true
			table.insert(resolvedArgs, {
				Arg = arg,
				Present = true,
				Ok = true,
				Value = true,
				Display = "true",
				Span = entry.Span,
				Deferred = false,
				Type = argType,
			})
			continue
		end

		if entry.PipeDeferred then
			table.insert(resolvedArgs, {
				Arg = arg,
				Present = true,
				Ok = true,
				Value = nil,
				Span = entry.Span,
				Deferred = true,
				Type = argType,
			})
			continue
		end

		-- Piped value.
		const piped = entry.Piped
		if piped then
			local value: unknown = nil
			local ok = false
			local message: string? = nil
			const pipedType = piped.Type
			if pipedType and assignable(pipedType, argType) then
				value, ok = piped.Value, true
			elseif pipedType and argType.Listable and argType.Element and assignable(pipedType, argType.Element) then
				value, ok = { piped.Value }, true
			elseif pipedType and pipedType.Listable and pipedType.Element and assignable(pipedType.Element, argType) then
				const list = piped.Value
				if type(list) == "table" and #list == 1 then
					for _, item in pairs(list) do
						value = item
					end
					ok = true
				else
					message = `'{target.Name}' expects one {argType.Name}, but {Util.FormatValue(list)} was piped`
				end
			else
				const result = argType.Parse(makeRequest(options, piped.Display, true, entry.Span, arg.Name))
				if result.Ok then
					value, ok = result.Value, true
				else
					message = locale:Get("resolve.pipeMismatch", {
						from = if pipedType then pipedType.Name else `'{piped.Display}'`,
						command = target.Name,
						to = argType.Name,
					})
				end
			end
			if not ok then
				diagnostic(diagnostics, message or "Invalid piped value", entry.Span)
			end
			values[arg.Name] = value
			previous[arg.Name] = value
			table.insert(resolvedArgs, {
				Arg = arg,
				Present = true,
				Ok = ok,
				Value = value,
				Display = piped.Display,
				Error = message,
				Span = entry.Span,
				Deferred = false,
				Type = argType,
			})
			continue
		end

		-- Text value(s).
		const parseOne = function(word: Parser.Word, offset: number): (boolean, unknown, string?, string?, Span, boolean)
			const span: Span = { Start = word.Span.Start + offset, End = word.Span.End }
			const substitution = substitute(word, offset, options.Provider)
			if substitution.Error then
				return false, nil, nil, substitution.Error, span, false
			end
			if substitution.Deferred then
				return true, nil, nil, nil, span, true
			end
			const structuredType = substitution.Type
			if substitution.Value ~= nil and structuredType and assignable(structuredType, argType) then
				return true, substitution.Value, substitution.Text, nil, span, false
			end
			const request = makeRequest(options, substitution.Text, word.Quoted, span, arg.Name)
			if argType.Yields and not options.Final then
				return true, nil, substitution.Text, nil, span, true
			end
			const ok, result = pcall(argType.Parse, request)
			if not ok then
				return false, nil, nil, `{argType.Name} parser errored: {result}`, span, false
			end
			if not result.Ok then
				return false, nil, nil, result.Error, result.Span or span, false
			end
			return true, result.Value, result.Display, nil, span, false
		end

		local value: unknown = nil
		local display: string? = nil
		local message: string? = nil
		local errorSpan: Span = entry.Span
		local ok = true
		local deferred = false
		local textValue: string? = nil

		if arg.Kind == "rest" then
			const list: { unknown } = {}
			const displays: { string } = {}
			for _, word in entry.Words do
				const itemOk, itemValue, itemDisplay, itemError, itemSpan, itemDeferred = parseOne(word, 0)
				if itemDeferred then
					deferred = true
				elseif not itemOk then
					ok, message, errorSpan = false, itemError, itemSpan
					break
				else
					table.insert(list, itemValue)
					table.insert(displays, itemDisplay or Util.FormatValue(itemValue))
				end
			end
			value, display = list, table.concat(displays, " ")
		elseif #entry.Words > 1 then
			-- Merged excess words: join their substituted texts.
			const texts: { string } = {}
			for _, word in entry.Words do
				const substitution = substitute(word, 0, options.Provider)
				if substitution.Deferred then
					deferred = true
				end
				table.insert(texts, substitution.Text)
			end
			textValue = table.concat(texts, " ")
			if not deferred then
				const request = makeRequest(options, textValue, false, entry.Span, arg.Name)
				const result = argType.Parse(request)
				if result.Ok then
					value, display = result.Value, result.Display
				else
					ok, message, errorSpan = false, result.Error, result.Span or entry.Span
				end
			end
		else
			const word = entry.Words[1]
			const itemOk, itemValue, itemDisplay, itemError, itemSpan, itemDeferred = parseOne(
				word,
				entry.ValueOffset or 0
			)
			ok, value, display, message, errorSpan, deferred =
				itemOk,
				itemValue,
				itemDisplay,
				itemError,
				itemSpan,
				itemDeferred
			textValue = substitute(word, entry.ValueOffset or 0, nil).Text
		end

		-- Extra validation and list emptiness.
		if ok and not deferred then
			if type(value) == "table" and argType.Listable and #value == 0 and not arg.Options.AllowEmpty then
				ok = false
				message = locale:Get("resolve.emptyList", { text = textValue or "", plural = argType.Name })
				errorSpan = entry.Span
			elseif arg.Validate then
				const validated, validateMessage = arg.Validate(
					value,
					makeRequest(options, textValue or "", false, entry.Span, arg.Name)
				)
				if not validated then
					ok = false
					message = validateMessage or `Invalid {arg.Name}`
					errorSpan = entry.Span
				end
			end
		end

		if not ok then
			diagnostic(diagnostics, message or `Invalid {arg.Name}`, errorSpan)
		end
		values[arg.Name] = if ok then value else nil
		previous[arg.Name] = values[arg.Name]
		table.insert(resolvedArgs, {
			Arg = arg,
			Present = true,
			Ok = ok,
			Value = value,
			Display = display,
			Error = message,
			Span = entry.Span,
			Text = textValue,
			Deferred = deferred,
			Type = argType,
		})
	end

	local ok = true
	for _, item in diagnostics do
		if item.Severity == "error" then
			ok = false
			break
		end
	end
	resolution.Ok = ok
	return resolution
end

return table.freeze(Resolver)
