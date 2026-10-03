--!strict
--[[
	`RoShell.Type.*`: constructors for argument types. Every constructor derives parsing, completion, fuzzy
	matching, operators, display text and error messages ("Unknown item 'swrod'. Did you mean 'sword'?").

	Common types are one-liners:
		const Rarity = RoShell.Type.Choice({ Name = "rarity", Choices = { "common", "rare", "epic" } })
		const Count = RoShell.Type.Integer({ Name = "count", Min = 1, Max = 999 })
		const Item = RoShell.Type.Dynamic({ Name = "item", Candidates = function() return listItems() end })

	A fully custom type only needs `Name` and `Parse` (see `Custom`).
]]

--// Imports
const Fuzzy = require("./Fuzzy")
const Selector = require("./Selector")
const TypeFunctions = require("./TypeFunctions")
const Types = require("./Types")
const Unsafe = require("./Unsafe")
const Util = require("./Util")

--// Types
type Type<T> = Types.Type<T>
type ParseRequest = Types.ParseRequest
type CompleteRequest = Types.CompleteRequest
type CandidateRequest = Types.CandidateRequest
type ParseResult<T> = Types.ParseResult<T>
type Suggestion = Types.Suggestion
type Candidate<T> = Types.Candidate<T>

export type CustomDefinition<T> = {
	read Name: string,
	read Description: string?,
	read Examples: { string }?,
	read Parse: (request: ParseRequest) -> ParseResult<T>,
	--- Full control over completion. When omitted, `Suggestions` (static strings) are fuzzy-filtered.
	read Complete: ((request: CompleteRequest) -> { Suggestion })?,
	read Suggestions: { string }?,
	read Default: ((request: ParseRequest) -> T?)?,
	read Expand: ((request: ParseRequest) -> ParseResult<{ read T }>?)?,
	read Color: string?,
	read Icon: string?,
	--- Set when `Parse` may yield; it is then only fully validated right before execution.
	read Yields: boolean?,
}

export type EnumerableDefinition<T> = {
	read Name: string,
	--- Singular/plural nouns for messages. Default to `Name` and `Name .. "s"`.
	read Noun: string?,
	read Plural: string?,
	read Description: string?,
	read Examples: { string }?,
	read Candidates: (request: CandidateRequest) -> { read Candidate<T> },
	read Default: ((request: ParseRequest) -> T?)?,
	read Selectors: { Types.Selector<T> }?,
	read AllowPatterns: boolean?,
	read CaseSensitive: boolean?,
	read Color: string?,
	read Icon: string?,
}

export type DynamicDefinition<T> = {
	read Name: string,
	read Noun: string?,
	read Plural: string?,
	read Description: string?,
	read Examples: { string }?,
	read Candidates: (request: CandidateRequest) -> { read Candidate<T> },
	--- Seconds candidates are cached (per executor). Defaults to 0 (no caching).
	read CacheSeconds: number?,
	read Default: ((request: ParseRequest) -> T?)?,
	read Selectors: { Types.Selector<T> }?,
	read AllowPatterns: boolean?,
	read CaseSensitive: boolean?,
	read Color: string?,
	read Icon: string?,
}

export type DynamicType<T> = Type<T> & {
	--- Drops cached candidates so the next query fetches fresh ones.
	read Invalidate: () -> (),
}

export type ChoiceDefinition<S> = {
	Name: string,
	read Choices: { read S },
	Description: string?,
	Examples: { string }?,
	--- Per-choice descriptions, keyed by the choice text.
	Descriptions: { [string]: string }?,
	--- Extra accepted spellings, keyed by the choice text.
	Aliases: { [string]: { string } }?,
	CaseSensitive: boolean?,
	Color: string?,
	Icon: string?,
}

export type MapEntry<V> = {
	read Key: string,
	read Value: V,
	read Aliases: { string }?,
	read Description: string?,
	--- Short right-aligned text in suggestion lists (defaults to the value for numbers, strings and booleans).
	read Detail: string?,
	read Hidden: boolean?,
}

export type MapDefinition<V> = {
	read Name: string,
	--- Entries in display order. (A list rather than a keyed table: Luau cannot infer `V` from keyed table
	--- literals, and keyed tables lose their order.)
	read Entries: { MapEntry<V> },
	read Description: string?,
	read Examples: { string }?,
	read CaseSensitive: boolean?,
	read Color: string?,
	read Icon: string?,
}

export type NumberDefinition = {
	read Name: string?,
	read Description: string?,
	read Examples: { string }?,
	read Min: number?,
	read Max: number?,
	read Integer: boolean?,
	--- Optional unit suffix accepted after the number (e.g. "%").
	read Suffix: string?,
	read Color: string?,
}

export type StringDefinition = {
	read Name: string?,
	read Description: string?,
	read Examples: { string }?,
	read MinLength: number?,
	read MaxLength: number?,
	--- Luau pattern the whole text must match.
	read Pattern: string?,
	read PatternMessage: string?,
	read Suggestions: { string }?,
	read Color: string?,
}

export type PatternDefinition<T> = {
	read Name: string,
	read Pattern: string,
	--- Converts the matched text into the value.
	read Transform: (text: string, request: ParseRequest) -> T,
	read Message: string?,
	read Description: string?,
	read Examples: { string }?,
	read Suggestions: { string }?,
	read Color: string?,
}

export type ListOptions = {
	read Name: string?,
	read Description: string?,
	read Examples: { string }?,
	--- Remove duplicate values (default true).
	read Unique: boolean?,
}

export type Range = { Min: number, Max: number, Step: number }

export type RangeDefinition = {
	read Name: string?,
	read Description: string?,
	read Min: number?,
	read Max: number?,
	read Integer: boolean?,
}

--// Constants
const MAX_RANGE_ITEMS = 10000
const TRUE_WORDS: { [string]: true } = { ["true"] = true, yes = true, y = true, on = true, ["1"] = true, t = true }
const FALSE_WORDS: { [string]: true } = { ["false"] = true, no = true, n = true, off = true, ["0"] = true, f = true }
const NIL_WORDS: { [string]: true } = { [""] = true, ["nil"] = true, none = true, ["-"] = true }
const NO_OPERATORS: { Types.OperatorInfo } = {}
const LIST_OPERATORS: { Types.OperatorInfo } = {
	{ Symbol = ",", Name = "list", Description = "Several values", Example = "1,2,3", Scalar = false, List = true },
}
const RANGE_OPERATORS: { Types.OperatorInfo } = {
	{
		Symbol = "a..b",
		Name = "range",
		Description = "Every number from a to b",
		Example = "1..10",
		Scalar = false,
		List = true,
	},
	{
		Symbol = "a..b/s",
		Name = "stepped range",
		Description = "From a to b in steps of s",
		Example = "16..32/8",
		Scalar = false,
		List = true,
	},
}

--// Globals
local lastTypeId = 0
-- Every constructed type, so values typed `unknown` (e.g. members of a generic list) can be looked up safely.
const knownTypes: { [unknown]: Type<unknown> } = setmetatable({}, { __mode = "k" })

--// Helpers

const function identity(text: string): string
	return text
end

const function emptyComplete(_request: CompleteRequest): { Suggestion }
	return {}
end

const function nextId(): number
	lastTypeId += 1
	return lastTypeId
end

const function register<T>(typeObject: Type<T>): Type<T>
	knownTypes[typeObject] = typeObject
	return typeObject
end

--- Fuzzy-filters static strings into suggestions.
const function completeStrings(request: CompleteRequest, items: { string }, kind: string, detail: string?): { Suggestion }
	const suggestions: { Suggestion } = {}
	for _, result in Fuzzy.Filter(request.Text, items, identity, request.Limit) do
		table.insert(suggestions, {
			Text = result.Item,
			Display = result.Item,
			Detail = detail,
			Kind = kind,
			Score = result.Score,
			MatchRanges = result.Ranges,
		})
	end
	return suggestions
end

const function fail(request: ParseRequest, message: string, progress: number?): Types.ParseError
	return { Ok = false, Error = message, Span = request.Span, Progress = progress or 0 }
end

--- A request for a slice of the original text (`offset` is the 0-based byte offset of the slice).
const function slice(request: ParseRequest, text: string, offset: number): ParseRequest
	return {
		Text = text,
		Quoted = request.Quoted,
		Span = { Start = request.Span.Start + offset, End = request.Span.Start + offset + #text },
		Executor = request.Executor,
		Shell = request.Shell,
		Platform = request.Platform,
		Final = request.Final,
		ArgName = request.ArgName,
	}
end

const function completeRequestFor(request: CompleteRequest, text: string): CompleteRequest
	return {
		Text = text,
		Quoted = request.Quoted,
		Executor = request.Executor,
		Shell = request.Shell,
		Platform = request.Platform,
		Limit = request.Limit,
		ArgName = request.ArgName,
	}
end

const function formatBound(value: number): string
	return Util.FormatNumber(value)
end

--- Splits a list argument on commas (empty pieces are kept so trailing commas are reported).
const function splitList(text: string): { { Text: string, Offset: number } }
	const pieces: { { Text: string, Offset: number } } = {}
	local start = 1
	while true do
		const comma = text:find(",", start, true)
		if comma == nil then
			table.insert(pieces, { Text = text:sub(start), Offset = start - 1 })
			return pieces
		end
		table.insert(pieces, { Text = text:sub(start, comma - 1), Offset = start - 1 })
		start = comma + 1
	end
end

--- Reads `a..b`, `..b`, `a..`, `a..b/step` or a single number. Open ends take the given bounds.
const function readRange(text: string, lower: number?, upper: number?): (number?, number?, number?)
	const single = tonumber(text)
	if single then
		return single, single, 1
	end
	const fromText, toText, stepText = text:match("^(%-?[%d%.]*)%.%.(%-?[%d%.]*)/?([%d%.]*)$")
	if fromText == nil or toText == nil then
		return nil, nil, nil
	end
	const from = if fromText == "" then lower else tonumber(fromText)
	const to = if toText == "" then upper else tonumber(toText)
	const step = if stepText == nil or stepText == "" then 1 else tonumber(stepText)
	return from, to, step
end

--// TypeBuilder
const TypeBuilder = {}

--- Returns the type object for a value that is a RoShell type (or nil).
function TypeBuilder.Lookup(value: unknown): Type<unknown>?
	return knownTypes[value]
end

--- Builds a request for a slice of an argument (for composite types).
TypeBuilder.Slice = slice

--- A fully custom type: provide `Name` and `Parse` (and optionally completion).
function TypeBuilder.Custom<T>(definition: CustomDefinition<T>): Type<T>
	const suggestions = definition.Suggestions
	const complete = definition.Complete
		or if suggestions then function(request: CompleteRequest): { Suggestion }
				return completeStrings(request, suggestions, definition.Name)
			end
			else emptyComplete
	const built: Type<T> = table.freeze({
		Name = definition.Name,
		Description = definition.Description,
		Examples = definition.Examples,
		Kind = "custom",
		Id = nextId(),
		Parse = definition.Parse,
		Complete = complete,
		Default = definition.Default,
		Expand = definition.Expand,
		Listable = false,
		Operators = NO_OPERATORS,
		Color = definition.Color,
		Icon = definition.Icon,
		Yields = definition.Yields == true,
	})
	return register(built)
end

--- A type whose values come from a list of candidates. Supports the full operator set.
function TypeBuilder.Enumerable<T>(definition: EnumerableDefinition<T>): Type<T>
	const noun = definition.Noun or definition.Name
	const plural = definition.Plural or (noun .. "s")
	const id = nextId()
	const function optionsFor(request: CandidateRequest): Selector.Options<T>
		return {
			Noun = noun,
			Plural = plural,
			Candidates = definition.Candidates(request),
			Default = definition.Default,
			Selectors = definition.Selectors,
			AllowPatterns = definition.AllowPatterns,
			CaseSensitive = definition.CaseSensitive,
			TypeId = id,
		}
	end
	const operators = Selector.OperatorsFor(false, definition.Default ~= nil)
	const built: Type<T> = table.freeze({
		Name = definition.Name,
		Description = definition.Description,
		Examples = definition.Examples,
		Kind = "enumerable",
		Id = id,
		Parse = function(request: ParseRequest): ParseResult<T>
			return Selector.ResolveOne(request, optionsFor(request))
		end,
		Complete = function(request: CompleteRequest): { Suggestion }
			return Selector.Complete(request, optionsFor(request), false)
		end,
		Enumerate = definition.Candidates,
		Default = definition.Default,
		Selectors = definition.Selectors,
		Matching = {
			Plural = plural,
			AllowPatterns = definition.AllowPatterns == true,
			CaseSensitive = definition.CaseSensitive == true,
		},
		Listable = false,
		Operators = operators,
		Color = definition.Color,
		Icon = definition.Icon,
		Yields = false,
	})
	return register(built)
end

--- A fixed set of string choices: `Choice({ Name = "rarity", Choices = { "common", "rare" } })`.
function TypeBuilder.Choice<S>(
	definition: {
		Name: string,
		read Choices: { read S },
		Description: string?,
		Examples: { string }?,
		Descriptions: { [string]: string }?,
		Aliases: { [string]: { string } }?,
		CaseSensitive: boolean?,
		Color: string?,
		Icon: string?,
	}
): Type<S>
	const candidates: { Candidate<S> } = {}
	for _, choice in definition.Choices do
		const key = tostring(choice)
		table.insert(candidates, {
			Key = key,
			Value = choice,
			Description = if definition.Descriptions then definition.Descriptions[key] else nil,
			Aliases = if definition.Aliases then definition.Aliases[key] else nil,
		})
	end
	table.freeze(candidates)
	return TypeBuilder.Enumerable({
		Name = definition.Name,
		Description = definition.Description,
		Examples = definition.Examples,
		Candidates = function(): { read Candidate<S> }
			return candidates
		end,
		CaseSensitive = definition.CaseSensitive,
		Color = definition.Color,
		Icon = definition.Icon,
	})
end

--- Keys mapped to values, with aliases and descriptions:
--- `Map({ Name = "difficulty", Entries = { { Key = "easy", Value = 1, Aliases = { "e" } }, ... } })`.
function TypeBuilder.Map<V>(definition: MapDefinition<V>): Type<V>
	const candidates: { Candidate<V> } = {}
	for _, entry in definition.Entries do
		table.insert(candidates, {
			Key = entry.Key,
			Value = entry.Value,
			Aliases = entry.Aliases,
			Description = entry.Description,
			Hidden = entry.Hidden,
			Detail = entry.Detail
				or (if type(entry.Value) == "table" or type(entry.Value) == "userdata" then nil
					else Util.FormatValue(entry.Value)),
		})
	end
	table.freeze(candidates)
	return TypeBuilder.Enumerable({
		Name = definition.Name,
		Description = definition.Description,
		Examples = definition.Examples,
		Candidates = function(): { read Candidate<V> }
			return candidates
		end,
		CaseSensitive = definition.CaseSensitive,
		Color = definition.Color,
		Icon = definition.Icon,
	})
end

--- Values resolved from a dynamic list, optionally cached for `CacheSeconds` per executor.
function TypeBuilder.Dynamic<T>(definition: DynamicDefinition<T>): DynamicType<T>
	const cacheSeconds = definition.CacheSeconds or 0
	const cache: {
		[string]: { Candidates: { read Candidate<T> }, Expires: number },
	} = {}
	const function candidatesFor(request: CandidateRequest): { read Candidate<T> }
		if cacheSeconds <= 0 then
			return definition.Candidates(request)
		end
		const key = Util.ExecutorKey(request.Executor)
		const now = request.Platform.Clock()
		const cached = cache[key]
		if cached and cached.Expires > now then
			return cached.Candidates
		end
		const fresh = definition.Candidates(request)
		cache[key] = { Candidates = fresh, Expires = now + cacheSeconds }
		return fresh
	end
	const base = TypeBuilder.Enumerable({
		Name = definition.Name,
		Noun = definition.Noun,
		Plural = definition.Plural,
		Description = definition.Description,
		Examples = definition.Examples,
		Candidates = candidatesFor,
		Default = definition.Default,
		Selectors = definition.Selectors,
		AllowPatterns = definition.AllowPatterns,
		CaseSensitive = definition.CaseSensitive,
		Color = definition.Color,
		Icon = definition.Icon,
	})
	const dynamicType: DynamicType<T> = table.freeze({
		Name = base.Name,
		Description = base.Description,
		Examples = base.Examples,
		Kind = "dynamic",
		Id = base.Id,
		Parse = base.Parse,
		Complete = base.Complete,
		Enumerate = base.Enumerate,
		Default = base.Default,
		Selectors = base.Selectors,
		Matching = base.Matching,
		Listable = false,
		Operators = base.Operators,
		Color = base.Color,
		Icon = base.Icon,
		Yields = false,
		Invalidate = function()
			table.clear(cache)
		end,
	})
	register(dynamicType)
	return dynamicType
end

--- Builds an enum type whose items are read on first use (keeps module loading free of engine access).
const function enumType(
	name: string,
	description: string?,
	getEnum: () -> unknown,
	exclude: { string }?,
	color: string?
): Type<EnumItem>
	local candidates: { Candidate<EnumItem> }? = nil
	const excluded: { [string]: true } = {}
	for _, item in exclude or {} do
		excluded[item] = true
	end
	const function load(): { read Candidate<EnumItem> }
		if candidates then
			return candidates
		end
		const enumObject = getEnum()
		assert(typeof(enumObject) == "Enum", "RoShell.Type.FromEnum: Enum must be a Roblox Enum such as Enum.Material")
		const list: { Candidate<EnumItem> } = {}
		for _, item in enumObject:GetEnumItems() do
			if not excluded[item.Name] then
				table.insert(list, { Key = item.Name, Value = item, Detail = tostring(item.Value) })
			end
		end
		table.freeze(list)
		candidates = list
		return list
	end
	return TypeBuilder.Enumerable({
		Name = name,
		Description = description or `A value of the {name} enum`,
		Candidates = load,
		Color = color or "type.enum",
		Icon = "enum",
	})
end

--- The items of a Roblox Enum: `FromEnum({ Name = "material", Enum = Enum.Material })` -> `Type<Enum.Material>`.
function TypeBuilder.FromEnum<E>(
	definition: {
		Name: string,
		Enum: E,
		Description: string?,
		Exclude: { string }?,
		Color: string?,
	}
): Type<TypeFunctions.EnumItemOf<E>>
	const enumObject: unknown = definition.Enum
	const built = enumType(
		definition.Name,
		definition.Description,
		function(): unknown
			return enumObject
		end,
		definition.Exclude,
		definition.Color
	)
	-- Every candidate is an item of `definition.Enum`, which is exactly what EnumItemOf<E> names.
	return Unsafe.Assume(built) :: Type<TypeFunctions.EnumItemOf<E>>
end

--- Like `FromEnum`, but the Enum is fetched lazily on first use: `FromEnumLazy({ Enum = function() return Enum.KeyCode end })`.
function TypeBuilder.FromEnumLazy<E>(
	definition: {
		Name: string,
		Enum: () -> E,
		Description: string?,
		Exclude: { string }?,
		Color: string?,
	}
): Type<TypeFunctions.EnumItemOf<E>>
	const getEnum = definition.Enum
	const built = enumType(
		definition.Name,
		definition.Description,
		function(): unknown
			return getEnum()
		end,
		definition.Exclude,
		definition.Color
	)
	return Unsafe.Assume(built) :: Type<TypeFunctions.EnumItemOf<E>>
end

--- Numbers with optional bounds; in lists also accepts ranges `1..10`, `..5`, `5..` and steps `1..10/2`.
function TypeBuilder.Number(definition: NumberDefinition?): Type<number>
	const options: NumberDefinition = definition or {}
	const integer = options.Integer == true
	const minimum = options.Min
	const maximum = options.Max
	const suffix = options.Suffix
	const noun = if integer then "whole number" else "number"

	const function convert(request: ParseRequest, rawText: string): ParseResult<number>
		local text = Util.Trim(rawText)
		if suffix and Util.EndsWith(text, suffix) then
			text = text:sub(1, #text - #suffix)
		end
		if text == "" then
			return fail(request, `Expected a {noun}`)
		end
		const value = tonumber(text)
		if value == nil or value ~= value then
			return fail(request, `'{rawText}' is not a {noun}`)
		end
		if integer and value ~= math.floor(value) then
			return fail(request, `Expected a whole number, got {rawText}`)
		end
		if minimum and value < minimum then
			return fail(request, `Must be at least {formatBound(minimum)} (got {Util.FormatNumber(value)})`)
		end
		if maximum and value > maximum then
			return fail(request, `Must be at most {formatBound(maximum)} (got {Util.FormatNumber(value)})`)
		end
		return { Ok = true, Value = value, Display = Util.FormatNumber(value) .. (suffix or "") }
	end

	const function expand(request: ParseRequest): ParseResult<{ read number }>?
		const fromText, toText, stepText = request.Text:match("^%s*(%-?[%d%.]*)%.%.(%-?[%d%.]*)/?([%d%.]*)%s*$")
		if fromText == nil or toText == nil then
			return nil
		end
		const from = if fromText == "" then minimum else tonumber(fromText)
		const to = if toText == "" then maximum else tonumber(toText)
		if from == nil or to == nil then
			return fail(request, "Open ranges need a bound: write both ends, like 1..10")
		end
		const step = if stepText == nil or stepText == "" then 1 else tonumber(stepText)
		if step == nil or step <= 0 then
			return fail(request, "Range step must be a positive number")
		end
		const values: { number } = {}
		const direction = if to >= from then 1 else -1
		local current = from
		while (direction > 0 and current <= to + 1e-9) or (direction < 0 and current >= to - 1e-9) do
			const checked = convert(request, tostring(current))
			if not checked.Ok then
				return { Ok = false, Error = checked.Error, Span = request.Span, Progress = 0 }
			end
			table.insert(values, checked.Value)
			if #values > MAX_RANGE_ITEMS then
				return fail(request, `Range is too large (more than {MAX_RANGE_ITEMS} values)`)
			end
			current += step * direction
		end
		return { Ok = true, Value = values, Display = `{Util.FormatNumber(from)}..{Util.FormatNumber(to)}` }
	end

	const constraints: { string } = {}
	if minimum then
		table.insert(constraints, `≥ {formatBound(minimum)}`)
	end
	if maximum then
		table.insert(constraints, `≤ {formatBound(maximum)}`)
	end
	const name = options.Name or (if integer then "integer" else "number")
	const built: Type<number> = table.freeze({
		Name = name,
		Description = options.Description
			or (if #constraints > 0 then `A {noun} {table.concat(constraints, ", ")}` else `A {noun}`),
		Examples = options.Examples,
		Kind = "number",
		Id = nextId(),
		Parse = function(request: ParseRequest): ParseResult<number>
			return convert(request, request.Text)
		end,
		Complete = emptyComplete,
		Expand = expand,
		Listable = false,
		Operators = RANGE_OPERATORS,
		Color = options.Color or "type.number",
		Icon = "number",
		Yields = false,
	})
	return register(built)
end

--- Whole numbers (`Number` with `Integer = true`).
function TypeBuilder.Integer(definition: NumberDefinition?): Type<number>
	const options: NumberDefinition = definition or {}
	return TypeBuilder.Number({
		Name = options.Name or "integer",
		Description = options.Description,
		Examples = options.Examples,
		Min = options.Min,
		Max = options.Max,
		Integer = true,
		Suffix = options.Suffix,
		Color = options.Color,
	})
end

--- Text, with optional length bounds and pattern.
function TypeBuilder.String(definition: StringDefinition?): Type<string>
	const options: StringDefinition = definition or {}
	const suggestions = options.Suggestions
	const built: Type<string> = table.freeze({
		Name = options.Name or "string",
		Description = options.Description or "Any text",
		Examples = options.Examples,
		Kind = "string",
		Id = nextId(),
		Parse = function(request: ParseRequest): ParseResult<string>
			const text = request.Text
			const length = utf8.len(text) or #text
			if options.MinLength and length < options.MinLength then
				return fail(request, `Must be at least {options.MinLength} characters`)
			end
			if options.MaxLength and length > options.MaxLength then
				return fail(request, `Must be at most {options.MaxLength} characters`)
			end
			if options.Pattern and not text:match(options.Pattern) then
				return fail(request, options.PatternMessage or `'{text}' is not in the expected format`)
			end
			return { Ok = true, Value = text, Display = text }
		end,
		Complete = if suggestions then function(request: CompleteRequest): { Suggestion }
				return completeStrings(request, suggestions, "value")
			end
			else emptyComplete,
		Listable = false,
		Operators = NO_OPERATORS,
		Color = options.Color or "type.string",
		Icon = "string",
		Yields = false,
	})
	return register(built)
end

--- true/false (also yes/no, on/off, 1/0).
function TypeBuilder.Boolean(name: string?): Type<boolean>
	const choices = { "true", "false" }
	const built: Type<boolean> = table.freeze({
		Name = name or "boolean",
		Description = "true or false (also yes/no, on/off, 1/0)",
		Kind = "boolean",
		Id = nextId(),
		Parse = function(request: ParseRequest): ParseResult<boolean>
			const lowered = request.Text:lower()
			if TRUE_WORDS[lowered] then
				return { Ok = true, Value = true, Display = "true" }
			elseif FALSE_WORDS[lowered] then
				return { Ok = true, Value = false, Display = "false" }
			end
			return fail(request, `'{request.Text}' is not true or false`)
		end,
		Complete = function(request: CompleteRequest): { Suggestion }
			return completeStrings(request, choices, "value")
		end,
		Listable = false,
		Operators = NO_OPERATORS,
		Color = "type.boolean",
		Icon = "boolean",
		Yields = false,
	})
	return register(built)
end

--- Text matching a Luau pattern, transformed into a value.
function TypeBuilder.Pattern<T>(definition: PatternDefinition<T>): Type<T>
	const suggestions = definition.Suggestions
	const built: Type<T> = table.freeze({
		Name = definition.Name,
		Description = definition.Description,
		Examples = definition.Examples,
		Kind = "pattern",
		Id = nextId(),
		Parse = function(request: ParseRequest): ParseResult<T>
			if not request.Text:match(definition.Pattern) then
				return fail(request, definition.Message or `'{request.Text}' is not a valid {definition.Name}`)
			end
			return { Ok = true, Value = definition.Transform(request.Text, request), Display = request.Text }
		end,
		Complete = if suggestions then function(request: CompleteRequest): { Suggestion }
				return completeStrings(request, suggestions, "value")
			end
			else emptyComplete,
		Listable = false,
		Operators = NO_OPERATORS,
		Color = definition.Color,
		Yields = false,
	})
	return register(built)
end

--- Makes a type optional: empty text, `nil`, `none` and `-` parse to nil.
function TypeBuilder.Optional<T>(base: Type<T>): Type<T?>
	const built: Type<T?> = table.freeze({
		Name = base.Name .. "?",
		Description = base.Description,
		Examples = base.Examples,
		Kind = "optional",
		Id = nextId(),
		Parse = function(request: ParseRequest): ParseResult<T?>
			if not request.Quoted and NIL_WORDS[request.Text:lower()] then
				return { Ok = true, Value = nil, Display = "none" }
			end
			const result = base.Parse(request)
			if result.Ok then
				return { Ok = true, Value = result.Value, Display = result.Display }
			end
			return result
		end,
		Complete = base.Complete,
		Element = base,
		Listable = false,
		Operators = base.Operators,
		Color = base.Color,
		Icon = base.Icon,
		Yields = base.Yields,
	})
	return register(built)
end

--- A list of values: `a,b,c`. Enumerable element types also get wildcards and set arithmetic.
function TypeBuilder.List<T>(base: Type<T>, options: ListOptions?): Type<{ T }>
	const listOptions: ListOptions = options or {}
	const unique = listOptions.Unique ~= false
	const matching = base.Matching
	const plural = listOptions.Name or (if matching then matching.Plural else base.Name .. "s")
	const enumerate = base.Enumerate

	const function selectorOptions(request: CandidateRequest, candidates: { read Candidate<T> }): Selector.Options<T>
		return {
			Noun = base.Name,
			Plural = plural,
			Candidates = candidates,
			Default = base.Default,
			Selectors = base.Selectors,
			AllowPatterns = if matching then matching.AllowPatterns else false,
			CaseSensitive = if matching then matching.CaseSensitive else false,
			TypeId = base.Id,
		}
	end

	const function parse(request: ParseRequest): ParseResult<{ T }>
		if enumerate then
			return Selector.ResolveMany(request, selectorOptions(request, enumerate(request)))
		end
		const values: { T } = {}
		const displays: { string } = {}
		const seen: { [unknown]: true } = {}
		const function add(value: T, display: string?)
			if unique then
				if seen[value] then
					return
				end
				seen[value] = true
			end
			table.insert(values, value)
			table.insert(displays, display or Util.FormatValue(value))
		end
		if request.Quoted then
			const result = base.Parse(request)
			if not result.Ok then
				return result
			end
			add(result.Value, result.Display)
			return { Ok = true, Value = values, Display = table.concat(displays, ", ") }
		end
		for _, piece in splitList(request.Text) do
			const pieceRequest = slice(request, piece.Text, piece.Offset)
			if piece.Text == "" then
				return {
					Ok = false,
					Error = `Expected a {base.Name}{if piece.Offset > 0 then " after ','" else ""}`,
					Span = pieceRequest.Span,
					Progress = piece.Offset,
				}
			end
			const expandPiece = base.Expand
			const expanded = if expandPiece then expandPiece(pieceRequest) else nil
			if expanded then
				if not expanded.Ok then
					return { Ok = false, Error = expanded.Error, Span = pieceRequest.Span, Progress = piece.Offset }
				end
				for _, value in expanded.Value do
					add(value, nil)
				end
			else
				const result = base.Parse(pieceRequest)
				if not result.Ok then
					return {
						Ok = false,
						Error = result.Error,
						Span = result.Span or pieceRequest.Span,
						Progress = piece.Offset + (result.Progress or 0),
					}
				end
				add(result.Value, result.Display)
			end
		end
		return {
			Ok = true,
			Value = values,
			Display = if #displays > 6 then table.concat(displays, ", ", 1, 5) .. ` (+{#displays - 5} more)`
				else table.concat(displays, ", "),
		}
	end

	const function complete(request: CompleteRequest): { Suggestion }
		if enumerate then
			return Selector.Complete(request, selectorOptions(request, enumerate(request)), true)
		end
		const head, segment = Selector.SplitLastSegment(request.Text)
		const commaHead = request.Text:match("^(.*,)") or ""
		const prefix = if #commaHead >= #head then commaHead else head
		const inner = base.Complete(completeRequestFor(request, segment))
		for _, suggestion in inner do
			suggestion.Text = prefix .. suggestion.Text
		end
		return inner
	end

	const operators: { Types.OperatorInfo } = if enumerate then Selector.OperatorsFor(true, base.Default ~= nil)
		else table.clone(LIST_OPERATORS)
	if not enumerate and base.Expand then
		for _, operator in base.Operators do
			table.insert(operators, operator)
		end
	end

	const built: Type<{ T }> = table.freeze({
		Name = plural,
		Description = listOptions.Description or `One or more {plural}`,
		Examples = listOptions.Examples,
		Kind = "list",
		Id = nextId(),
		Parse = parse,
		Complete = complete,
		Listable = true,
		Element = base,
		Operators = operators,
		Color = base.Color,
		Icon = base.Icon,
		Yields = base.Yields,
	})
	return register(built)
end

--- Tries each member in order; the first that parses wins. Errors report the member that got furthest.
function TypeBuilder.Union<M>(definition: { Name: string, Members: M, Description: string? }): Type<TypeFunctions.UnionOf<M>>
	const members: { Type<unknown> } = {}
	const rawMembers: unknown = definition.Members
	if type(rawMembers) == "table" then
		for _, member in pairs(rawMembers) do
			const memberType = TypeBuilder.Lookup(member)
			assert(memberType, "RoShell.Type.Union: every member must be a RoShell type")
			table.insert(members, memberType)
		end
	end
	assert(#members > 0, "RoShell.Type.Union: at least one member is required")
	const names: { string } = {}
	for _, member in members do
		table.insert(names, member.Name)
	end
	const built: Type<TypeFunctions.UnionOf<M>> = table.freeze({
		Name = definition.Name,
		Description = definition.Description or `One of: {table.concat(names, ", ")}`,
		Kind = "union",
		Id = nextId(),
		Parse = function(request: ParseRequest): ParseResult<TypeFunctions.UnionOf<M>>
			local bestError: string? = nil
			local bestProgress = -1
			local bestSpan: Types.Span? = nil
			for _, member in members do
				const result = member.Parse(request)
				if result.Ok then
					return {
						Ok = true,
						Value = Unsafe.Assume(result.Value) :: TypeFunctions.UnionOf<M>,
						Display = result.Display,
					}
				end
				const progress = result.Progress or 0
				if progress > bestProgress then
					bestProgress = progress
					bestError = result.Error
					bestSpan = result.Span
				end
			end
			return {
				Ok = false,
				Error = bestError or `'{request.Text}' is not a valid {definition.Name}`,
				Span = bestSpan or request.Span,
				Progress = bestProgress,
			}
		end,
		Complete = function(request: CompleteRequest): { Suggestion }
			const merged: { Suggestion } = {}
			const seen: { [string]: true } = {}
			for _, member in members do
				for _, suggestion in member.Complete(request) do
					if not seen[suggestion.Text] then
						seen[suggestion.Text] = true
						table.insert(merged, suggestion)
					end
				end
			end
			table.sort(merged, function(a: Suggestion, b: Suggestion): boolean
				return a.Score > b.Score
			end)
			return merged
		end,
		Listable = false,
		Operators = NO_OPERATORS,
		Yields = false,
	})
	return register(built)
end

--- Several values in one argument, separated by whitespace (quote the argument) or `:`.
--- `Tuple({ Name = "stack", Members = { { count = Count }, { item = Item } } })` -> `{ count: number, item: Item }`.
function TypeBuilder.Tuple<M>(
	definition: {
		Name: string,
		Members: M,
		Description: string?,
		Separator: string?,
	}
): Type<TypeFunctions.RecordOf<M>>
	const names: { string } = {}
	const memberTypes: { Type<unknown> } = {}
	const rawMembers: unknown = definition.Members
	const entries: { { Position: number, Entry: unknown } } = {}
	if type(rawMembers) == "table" then
		for position, entry in pairs(rawMembers) do
			if type(position) == "number" then
				table.insert(entries, { Position = position, Entry = entry })
			end
		end
	end
	table.sort(entries, function(a: { Position: number, Entry: unknown }, b: { Position: number, Entry: unknown }): boolean
		return a.Position < b.Position
	end)
	do
		for _, item in entries do
			const entry = item.Entry
			if type(entry) == "table" then
				for key, member in pairs(entry) do
					const memberType = TypeBuilder.Lookup(member)
					assert(
						type(key) == "string" and memberType,
						"RoShell.Type.Tuple: members look like { name = Type }"
					)
					table.insert(names, key)
					table.insert(memberTypes, memberType)
				end
			end
		end
	end
	const separator = definition.Separator
	const labels: { string } = {}
	for index, name in names do
		table.insert(labels, `{name}: {memberTypes[index].Name}`)
	end
	const built: Type<TypeFunctions.RecordOf<M>> = table.freeze({
		Name = definition.Name,
		Description = definition.Description or `({table.concat(labels, ", ")})`,
		Kind = "tuple",
		Id = nextId(),
		Parse = function(request: ParseRequest): ParseResult<TypeFunctions.RecordOf<M>>
			const pieces: { { Text: string, Offset: number } } = {}
			const separatorPattern = separator
			if separatorPattern then
				const normalized = string.gsub(request.Text, separatorPattern, ",")
				for _, piece in splitList(normalized) do
					table.insert(pieces, piece)
				end
			else
				for startByte, word in request.Text:gmatch("()(%S+)") do
					if type(startByte) == "number" and type(word) == "string" then
						table.insert(pieces, { Text = word, Offset = startByte - 1 })
					end
				end
			end
			if #pieces ~= #memberTypes then
				return fail(request, `Expected {#memberTypes} values ({table.concat(labels, ", ")}), got {#pieces}`)
			end
			const record: { [string]: unknown } = {}
			const displays: { string } = {}
			for index, memberType in memberTypes do
				const result = memberType.Parse(slice(request, pieces[index].Text, pieces[index].Offset))
				if not result.Ok then
					return {
						Ok = false,
						Error = `{names[index]}: {result.Error}`,
						Span = result.Span,
						Progress = pieces[index].Offset,
					}
				end
				record[names[index]] = result.Value
				table.insert(displays, result.Display or Util.FormatValue(result.Value))
			end
			return {
				Ok = true,
				Value = Unsafe.Assume(record) :: TypeFunctions.RecordOf<M>,
				Display = table.concat(displays, " "),
			}
		end,
		Complete = emptyComplete,
		Listable = false,
		Operators = NO_OPERATORS,
		Yields = false,
	})
	return register(built)
end

--- Named fields: `x=1,y=2`. `Struct({ Name = "point", Fields = { x = Number, y = Number } })`.
function TypeBuilder.Struct<F>(definition: { Name: string, Fields: F, Description: string? }): Type<TypeFunctions.StructOf<F>>
	const fieldTypes: { [string]: Type<unknown> } = {}
	const rawFields: unknown = definition.Fields
	if type(rawFields) == "table" then
		for key, member in pairs(rawFields) do
			const memberType = TypeBuilder.Lookup(member)
			assert(type(key) == "string" and memberType, "RoShell.Type.Struct: fields look like { name = Type }")
			fieldTypes[key] = memberType
		end
	end
	const fieldNames = Util.SortedKeys(fieldTypes)
	const built: Type<TypeFunctions.StructOf<F>> = table.freeze({
		Name = definition.Name,
		Description = definition.Description or `Fields: {table.concat(fieldNames, ", ")} (write name=value,...)`,
		Kind = "struct",
		Id = nextId(),
		Parse = function(request: ParseRequest): ParseResult<TypeFunctions.StructOf<F>>
			const record: { [string]: unknown } = {}
			const displays: { string } = {}
			for _, piece in splitList(request.Text) do
				const key, value = piece.Text:match("^%s*([%w_]+)%s*=(.*)$")
				if key == nil or value == nil then
					return fail(request, `Expected name=value, got '{piece.Text}'`, piece.Offset)
				end
				const fieldType = fieldTypes[key]
				if fieldType == nil then
					const suggestion = Fuzzy.Suggest(key, fieldNames)
					return fail(
						request,
						`Unknown field '{key}'{if suggestion then `. Did you mean '{suggestion}'?` else ""}`,
						piece.Offset
					)
				end
				const valueOffset = piece.Offset + (piece.Text:find("=", 1, true) or 0)
				const result = fieldType.Parse(slice(request, Util.Trim(value), valueOffset))
				if not result.Ok then
					return { Ok = false, Error = `{key}: {result.Error}`, Span = result.Span, Progress = valueOffset }
				end
				record[key] = result.Value
				table.insert(displays, `{key}={result.Display or Util.FormatValue(result.Value)}`)
			end
			for _, name in fieldNames do
				if record[name] == nil and fieldTypes[name].Kind ~= "optional" then
					return fail(request, `Missing field '{name}'`, #request.Text)
				end
			end
			return {
				Ok = true,
				Value = Unsafe.Assume(record) :: TypeFunctions.StructOf<F>,
				Display = table.concat(displays, ", "),
			}
		end,
		Complete = function(request: CompleteRequest): { Suggestion }
			const head = request.Text:match("^(.*,)") or ""
			const segment = request.Text:sub(#head + 1)
			if segment:find("=", 1, true) then
				return {}
			end
			const suggestions = completeStrings(completeRequestFor(request, segment), fieldNames, "field")
			for _, suggestion in suggestions do
				suggestion.Text = head .. suggestion.Text .. "="
				suggestion.Partial = true
			end
			return suggestions
		end,
		Listable = false,
		Operators = NO_OPERATORS,
		Yields = false,
	})
	return register(built)
end

--- Maps the parsed value of another type: `Transform({ From = Count, To = function(n) return string.rep("!", n) end })`.
function TypeBuilder.Transform<A, B>(
	definition: {
		From: Type<A>,
		To: (value: A, request: ParseRequest) -> B,
		Name: string?,
		Description: string?,
		Display: ((value: B) -> string)?,
	}
): Type<B>
	const base = definition.From
	const built: Type<B> = table.freeze({
		Name = definition.Name or base.Name,
		Description = definition.Description or base.Description,
		Examples = base.Examples,
		Kind = "transform",
		Id = nextId(),
		Parse = function(request: ParseRequest): ParseResult<B>
			const result = base.Parse(request)
			if not result.Ok then
				return result
			end
			const mapped = definition.To(result.Value, request)
			return {
				Ok = true,
				Value = mapped,
				Display = if definition.Display then definition.Display(mapped) else result.Display,
			}
		end,
		Complete = base.Complete,
		Listable = false,
		Operators = base.Operators,
		Color = base.Color,
		Icon = base.Icon,
		Yields = base.Yields,
	})
	return register(built)
end

--- Adds validation to a type; everything else (completion, operators, enumeration) is kept.
function TypeBuilder.Refine<T>(
	base: Type<T>,
	check: (value: T, request: ParseRequest) -> (boolean, string?),
	name: string?
): Type<T>
	const built: Type<T> = table.freeze({
		Name = name or base.Name,
		Description = base.Description,
		Examples = base.Examples,
		Kind = base.Kind,
		Id = if name then nextId() else base.Id,
		Parse = function(request: ParseRequest): ParseResult<T>
			const result = base.Parse(request)
			if not result.Ok then
				return result
			end
			const ok, message = check(result.Value, request)
			if not ok then
				return fail(request, message or `'{request.Text}' is not allowed here`)
			end
			return result
		end,
		Complete = base.Complete,
		Enumerate = base.Enumerate,
		Expand = base.Expand,
		Default = base.Default,
		Selectors = base.Selectors,
		Matching = base.Matching,
		Listable = base.Listable,
		Element = base.Element,
		Operators = base.Operators,
		Color = base.Color,
		Icon = base.Icon,
		Yields = base.Yields,
	})
	return register(built)
end

--- A numeric range value: `1..10`, `..5`, `5..`, `1..10/2`, or a single number.
function TypeBuilder.Range(definition: RangeDefinition?): Type<Range>
	const options: RangeDefinition = definition or {}
	const integer = options.Integer == true
	const built: Type<Range> = table.freeze({
		Name = options.Name or "range",
		Description = options.Description or "A range such as 1..10, ..5, 5.. or 1..10/2",
		Kind = "range",
		Id = nextId(),
		Parse = function(request: ParseRequest): ParseResult<Range>
			const text = Util.Trim(request.Text)
			const first, second, stepSize = readRange(text, options.Min, options.Max)
			if first == nil or second == nil or stepSize == nil or stepSize <= 0 then
				return fail(request, `'{text}' is not a valid range (try 1..10, ..5, 5.. or 1..10/2)`)
			end
			const minimum = math.min(first, second)
			const maximum = math.max(first, second)
			if integer and (minimum ~= math.floor(minimum) or maximum ~= math.floor(maximum)) then
				return fail(request, "Range bounds must be whole numbers")
			end
			if options.Min and minimum < options.Min then
				return fail(request, `Range must start at {formatBound(options.Min)} or more`)
			end
			if options.Max and maximum > options.Max then
				return fail(request, `Range must end at {formatBound(options.Max)} or less`)
			end
			const stepDisplay = if stepSize ~= 1 then "/" .. Util.FormatNumber(stepSize) else ""
			return {
				Ok = true,
				Value = { Min = minimum, Max = maximum, Step = stepSize },
				Display = `{Util.FormatNumber(minimum)}..{Util.FormatNumber(maximum)}{stepDisplay}`,
			}
		end,
		Complete = emptyComplete,
		Listable = false,
		Operators = RANGE_OPERATORS,
		Color = "type.number",
		Icon = "number",
		Yields = false,
	})
	return register(built)
end

return table.freeze(TypeBuilder)
