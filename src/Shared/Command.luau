--!strict
--[[
	Typed command definitions.

		return RoShell.Command({
			Name = "give",
			Aliases = { "grant" },
			Description = "Give items to players",
			Group = "Admin",
			Args = {
				{ targets = RoShell.Arg(RoShell.Types.Players, { Description = "Who receives the item" }) },
				{ item = RoShell.Arg(ItemType) },
				{ amount = RoShell.Default(Count, 1) },
				{ silent = RoShell.Flag({ Short = "s" }) },
			},
		}):Run(function(ctx, args)
			-- args: { targets: { Player }, item: ItemDef, amount: number, silent: boolean }
		end)

	`Args` is an ordered list of single-key tables so that both the order (positional binding) and the names
	(as literal property keys) survive into the type system; the `ArgsOf` type function turns it into the
	`args` record. Handlers are attached with `:Run()` / `:ClientRun()` because Luau cannot contextually type a
	lambda whose parameter type is computed from a generic in the same call (see DESIGN_NOTES.md).
]]

--// Imports
const TypeBuilder = require("./TypeBuilder")
const TypeFunctions = require("./TypeFunctions")
const Types = require("./Types")
const Unsafe = require("./Unsafe")
const Util = require("./Util")

--// Types
type Type<T> = Types.Type<T>
type ArgSpecOf<K, Ty> = Types.ArgSpecOf<K, Ty>
type ParseRequest = Types.ParseRequest

--- Options of a typed argument (adds `Validate` with the argument's value type).
export type ArgOptionsOf<V> = {
	Description: string?,
	Short: string?,
	Named: boolean?,
	Hidden: boolean?,
	Examples: { string }?,
	RequireConfirmAbove: number?,
	AllowEmpty: boolean?,
	Pipe: boolean?,
	--- Extra validation run after the type parsed the value. Return `false, "message"` to reject it.
	Validate: ((value: V, request: ParseRequest) -> (boolean, string?))?,
}

export type CommandDefinition<A> = {
	Name: string,
	--- Ordered list of `{ name = RoShell.Arg(...) }` entries. Use `{}` for a command without arguments.
	Args: A,
	Aliases: { string }?,
	Description: string?,
	--- Long help text shown by `help <command>`.
	Details: string?,
	Group: string?,
	Examples: { string | Types.Example }?,
	Hidden: boolean?,
	--- `true`, a replacement command name, or `{ Message, Replacement }`.
	Deprecated: (boolean | string | Types.DeprecationInfo)?,
	Subcommands: { Types.Command }?,
	Permissions: Types.Permission?,
	--- Seconds between two runs by the same executor.
	Cooldown: number?,
	RateLimit: Types.RateLimitOptions?,
	--- Seconds before the command is cancelled (0 disables).
	Timeout: number?,
	--- Always asks for confirmation unless `--yes` is given.
	Destructive: boolean?,
	--- Accepts the global `--dry` flag and shows `:Preview()` output instead of running.
	SupportsDryRun: boolean?,
	--- Name of the argument that receives piped input (alternatively mark the argument with `Pipe = true`).
	Pipe: string?,
	--- Type of the value this command returns, enabling pipe type checks.
	Returns: Type<unknown>?,
	--- Command lines run on the client when the command is registered (e.g. to define aliases).
	AutoExec: { string }?,
	Hooks: Types.CommandHooks?,
}

type ErasedSpec = {
	Kind: Types.ArgKind,
	Type: Type<unknown>,
	Options: Types.ArgOptions,
	DefaultValue: ((request: ParseRequest) -> unknown)?,
	DefaultDisplay: string?,
	Validate: ((value: unknown, request: ParseRequest) -> (boolean, string?))?,
	Resolve: ((request: Types.DynamicArgRequest) -> Type<unknown>?)?,
}

--// Constants
const NAME_PATTERN = "^[%w_%?=!][%w_%-%.:!%?=^]*$"
const SHORT_PATTERN = "^%a$"
const BOOLEAN = TypeBuilder.Boolean("flag")
const DYNAMIC_PLACEHOLDER = TypeBuilder.String({ Name = "value", Description = "Depends on the previous arguments" })
const ALIAS_ARGUMENT = TypeBuilder.String({ Name = "word", Description = "A word passed to the alias" })

--// Globals
-- Every argument spec and command created here, so values seen as `unknown` (module returns, `Args` entries)
-- can be looked up as their precise erased records without casts.
const knownSpecs: { [unknown]: ErasedSpec } = setmetatable({}, { __mode = "k" })
const knownCommands: { [unknown]: Types.Command } = setmetatable({}, { __mode = "k" })
local lastCommandId = 0

--// Helpers

const function copyOptions(options: Types.ArgOptions?): Types.ArgOptions
	if options == nil then
		return table.freeze({})
	end
	if options.Short then
		assert(options.Short:match(SHORT_PATTERN), `RoShell: Short flag '{options.Short}' must be a single letter`)
	end
	return table.freeze({
		Description = options.Description,
		Short = options.Short,
		Named = options.Named,
		Hidden = options.Hidden,
		Examples = options.Examples,
		RequireConfirmAbove = options.RequireConfirmAbove,
		AllowEmpty = options.AllowEmpty,
		Pipe = options.Pipe,
	})
end

const function lookupType(valueType: unknown, context: string): Type<unknown>
	const found = TypeBuilder.Lookup(valueType)
	assert(found, `RoShell: {context} expects a RoShell type (RoShell.Type.* or RoShell.Types.*)`)
	return found
end

--- Records the erased view of a spec (looked up when the command binds its arguments).
const function registerSpec<S>(spec: S, record: ErasedSpec): S
	knownSpecs[spec] = record
	return spec
end

const function normalizeDeprecation(value: (boolean | string | Types.DeprecationInfo)?): Types.DeprecationInfo?
	if value == nil or value == false then
		return nil
	elseif value == true then
		return table.freeze({})
	elseif type(value) == "string" then
		return table.freeze({ Replacement = value })
	elseif type(value) == "table" then
		return table.freeze({ Message = value.Message, Replacement = value.Replacement })
	end
	return nil
end

const function normalizeExamples(examples: { string | Types.Example }?): { Types.Example }
	const normalized: { Types.Example } = {}
	for _, example in examples or {} do
		if type(example) == "string" then
			table.insert(normalized, { Text = example })
		else
			table.insert(normalized, { Text = example.Text, Description = example.Description })
		end
	end
	return table.freeze(normalized)
end

const function checkName(name: string, what: string)
	assert(type(name) == "string" and name:match(NAME_PATTERN), `RoShell: invalid {what} '{tostring(name)}'`)
end

--- Builds the bound (erased) argument list from the `Args` schema.
const function bindArgs(commandName: string, rawArgs: unknown): { Types.BoundArg }
	assert(type(rawArgs) == "table", `RoShell: command '{commandName}' needs Args (use Args = \{} for none)`)
	const entries: { { Position: number, Entry: unknown } } = {}
	for position, entry in pairs(rawArgs) do
		assert(type(position) == "number", `RoShell: command '{commandName}' Args must be a list`)
		table.insert(entries, { Position = position, Entry = entry })
	end
	table.sort(entries, function(a: { Position: number, Entry: unknown }, b: { Position: number, Entry: unknown }): boolean
		return a.Position < b.Position
	end)

	const bound: { Types.BoundArg } = {}
	const names: { [string]: true } = {}
	const shorts: { [string]: string } = {}
	local sawOptionalPositional: string? = nil
	local sawRest: string? = nil
	for index, item in entries do
		const entry = item.Entry
		assert(
			type(entry) == "table",
			`RoShell: '{commandName}' Args entry #{index} must be \{ name = RoShell.Arg(...) }`
		)
		local name: string? = nil
		local specValue: unknown = nil
		local keys = 0
		for key, value in pairs(entry) do
			keys += 1
			if type(key) == "string" then
				name = key
				specValue = value
			end
		end
		assert(keys == 1 and name, `RoShell: '{commandName}' Args entry #{index} must have exactly one key`)
		const argName = name :: string
		checkName(argName, `argument name in '{commandName}'`)
		assert(names[argName] == nil, `RoShell: '{commandName}' has two arguments named '{argName}'`)
		names[argName] = true
		const spec = knownSpecs[specValue]
		assert(
			spec,
			`RoShell: '{commandName}' argument '{argName}' must be created with RoShell.Arg/Optional/Default/Rest/Flag/Dynamic`
		)

		const options = spec.Options
		if options.Short then
			assert(shorts[options.Short] == nil, `RoShell: '{commandName}' short flag -{options.Short} is used twice`)
			shorts[options.Short] = argName
		end
		const positional = spec.Kind ~= "flag" and options.Named ~= true
		const optional = spec.Kind ~= "required" and spec.Kind ~= "rest"
		if positional then
			assert(
				sawRest == nil,
				`RoShell: '{commandName}' argument '{argName}' comes after the rest argument '{sawRest}'`
			)
			if not optional and spec.Kind ~= "rest" then
				assert(
					sawOptionalPositional == nil,
					`RoShell: '{commandName}' required argument '{argName}' cannot follow optional argument '{sawOptionalPositional}'`
				)
			elseif optional then
				sawOptionalPositional = sawOptionalPositional or argName
			end
			if spec.Kind == "rest" then
				sawRest = argName
			end
		end
		table.insert(
			bound,
			table.freeze({
				Name = argName,
				Kind = spec.Kind,
				Type = spec.Type,
				Options = options,
				DefaultValue = spec.DefaultValue,
				DefaultDisplay = spec.DefaultDisplay,
				Validate = spec.Validate,
				Resolve = spec.Resolve,
				Index = index,
				Positional = positional,
				Optional = optional or spec.Kind == "rest",
			})
		)
	end
	return table.freeze(bound)
end

--// Command module
const Command = {}

--- A required argument.
function Command.Arg<Ty>(valueType: Ty, options: ArgOptionsOf<TypeFunctions.ValueOf<Ty>>?): ArgSpecOf<"required", Ty>
	-- The validator receives values produced by this argument's own type (see Unsafe.luau).
	local validate: ((value: unknown, request: ParseRequest) -> (boolean, string?))? = nil
	const check = if options then options.Validate else nil
	if check then
		validate = function(value: unknown, request: ParseRequest): (boolean, string?)
			return check(Unsafe.Assume(value) :: TypeFunctions.ValueOf<Ty>, request)
		end
	end
	const record: ErasedSpec = {
		Kind = "required",
		Type = lookupType(valueType, "RoShell.Arg"),
		Options = copyOptions(options),
		Validate = validate,
	}
	const spec: ArgSpecOf<"required", Ty> = {
		Kind = "required",
		Type = valueType,
		Options = record.Options,
		DefaultValue = record.DefaultValue,
		DefaultDisplay = record.DefaultDisplay,
		Validate = record.Validate,
		Resolve = record.Resolve,
	}
	table.freeze(spec)
	return registerSpec(spec, record)
end

--- An optional argument (`nil` when omitted).
function Command.Optional<Ty>(valueType: Ty, options: ArgOptionsOf<TypeFunctions.ValueOf<Ty>>?): ArgSpecOf<"optional", Ty>
	-- The validator receives values produced by this argument's own type (see Unsafe.luau).
	local validate: ((value: unknown, request: ParseRequest) -> (boolean, string?))? = nil
	const check = if options then options.Validate else nil
	if check then
		validate = function(value: unknown, request: ParseRequest): (boolean, string?)
			return check(Unsafe.Assume(value) :: TypeFunctions.ValueOf<Ty>, request)
		end
	end
	const record: ErasedSpec = {
		Kind = "optional",
		Type = lookupType(valueType, "RoShell.Optional"),
		Options = copyOptions(options),
		Validate = validate,
	}
	const spec: ArgSpecOf<"optional", Ty> = {
		Kind = "optional",
		Type = valueType,
		Options = record.Options,
		DefaultValue = record.DefaultValue,
		DefaultDisplay = record.DefaultDisplay,
		Validate = record.Validate,
		Resolve = record.Resolve,
	}
	table.freeze(spec)
	return registerSpec(spec, record)
end

--- An argument with a default (never `nil` in `Run`). The default is either a value of the argument's type or
--- the text a player would type, parsed by the type for each run: `Default(Mode, "easy")`,
--- `Default(Types.Duration, "5m")`, `Default(Types.Players, "me")` (the executor).
---
--- (Text defaults also sidestep a solver limitation: a string literal passed directly where a computed value type
--- is expected is widened to `string`, so `Default(Mode, "easy")` would otherwise be rejected.)
function Command.Default<Ty>(
	valueType: Ty,
	value: TypeFunctions.ValueOf<Ty> | string,
	options: ArgOptionsOf<TypeFunctions.ValueOf<Ty>>?
): ArgSpecOf<"default", Ty>
	-- The validator receives values produced by this argument's own type (see Unsafe.luau).
	local validate: ((value: unknown, request: ParseRequest) -> (boolean, string?))? = nil
	const check = if options then options.Validate else nil
	if check then
		validate = function(value: unknown, request: ParseRequest): (boolean, string?)
			return check(Unsafe.Assume(value) :: TypeFunctions.ValueOf<Ty>, request)
		end
	end
	const erased = lookupType(valueType, "RoShell.Default")
	local compute: (request: ParseRequest) -> unknown
	if type(value) == "string" then
		const text = value
		compute = function(request: ParseRequest): unknown
			const parsed = erased.Parse({
				Text = text,
				Quoted = false,
				Span = request.Span,
				Executor = request.Executor,
				Shell = request.Shell,
				Platform = request.Platform,
				Final = request.Final,
				ArgName = request.ArgName,
			})
			if parsed.Ok then
				return parsed.Value
			end
			error(parsed.Error, 0)
		end
	else
		compute = function(): unknown
			return value
		end
	end
	const record: ErasedSpec = {
		Kind = "default",
		Type = erased,
		Options = copyOptions(options),
		DefaultValue = compute,
		DefaultDisplay = if type(value) == "string" then value else Util.FormatValue(value),
		Validate = validate,
	}
	const spec: ArgSpecOf<"default", Ty> = {
		Kind = "default",
		Type = valueType,
		Options = record.Options,
		DefaultValue = record.DefaultValue,
		DefaultDisplay = record.DefaultDisplay,
		Validate = record.Validate,
		Resolve = record.Resolve,
	}
	table.freeze(spec)
	return registerSpec(spec, record)
end

--- An argument whose default is computed for each run (e.g. the executor). `display` is shown in signatures.
function Command.DefaultFn<Ty>(
	valueType: Ty,
	compute: (request: ParseRequest) -> TypeFunctions.ValueOf<Ty>,
	display: string?,
	options: ArgOptionsOf<TypeFunctions.ValueOf<Ty>>?
): ArgSpecOf<"default", Ty>
	-- The validator receives values produced by this argument's own type (see Unsafe.luau).
	local validate: ((value: unknown, request: ParseRequest) -> (boolean, string?))? = nil
	const check = if options then options.Validate else nil
	if check then
		validate = function(value: unknown, request: ParseRequest): (boolean, string?)
			return check(Unsafe.Assume(value) :: TypeFunctions.ValueOf<Ty>, request)
		end
	end
	const record: ErasedSpec = {
		Kind = "default",
		Type = lookupType(valueType, "RoShell.DefaultFn"),
		Options = copyOptions(options),
		DefaultValue = function(request: ParseRequest): unknown
			return compute(request)
		end,
		DefaultDisplay = display or "auto",
		Validate = validate,
	}
	const spec: ArgSpecOf<"default", Ty> = {
		Kind = "default",
		Type = valueType,
		Options = record.Options,
		DefaultValue = record.DefaultValue,
		DefaultDisplay = record.DefaultDisplay,
		Validate = record.Validate,
		Resolve = record.Resolve,
	}
	table.freeze(spec)
	return registerSpec(spec, record)
end

--- A variadic argument collecting every remaining positional word into a list (must be the last positional).
function Command.Rest<Ty>(valueType: Ty, options: ArgOptionsOf<TypeFunctions.ValueOf<Ty>>?): ArgSpecOf<"rest", Ty>
	-- The validator receives values produced by this argument's own type (see Unsafe.luau).
	local validate: ((value: unknown, request: ParseRequest) -> (boolean, string?))? = nil
	const check = if options then options.Validate else nil
	if check then
		validate = function(value: unknown, request: ParseRequest): (boolean, string?)
			return check(Unsafe.Assume(value) :: TypeFunctions.ValueOf<Ty>, request)
		end
	end
	const record: ErasedSpec = {
		Kind = "rest",
		Type = lookupType(valueType, "RoShell.Rest"),
		Options = copyOptions(options),
		Validate = validate,
	}
	const spec: ArgSpecOf<"rest", Ty> = {
		Kind = "rest",
		Type = valueType,
		Options = record.Options,
		DefaultValue = record.DefaultValue,
		DefaultDisplay = record.DefaultDisplay,
		Validate = record.Validate,
		Resolve = record.Resolve,
	}
	table.freeze(spec)
	return registerSpec(spec, record)
end

--- A boolean switch (`--silent`, `-s`). False unless given.
function Command.Flag(options: ArgOptionsOf<boolean>?): ArgSpecOf<"flag", Type<boolean>>
	const record: ErasedSpec = {
		Kind = "flag",
		Type = BOOLEAN,
		Options = copyOptions(options),
		DefaultValue = function(): unknown
			return false
		end,
		DefaultDisplay = "false",
	}
	const spec: ArgSpecOf<"flag", Type<boolean>> = {
		Kind = "flag",
		Type = BOOLEAN,
		Options = record.Options,
		DefaultValue = record.DefaultValue,
		DefaultDisplay = record.DefaultDisplay,
		Validate = record.Validate,
		Resolve = record.Resolve,
	}
	table.freeze(spec)
	return registerSpec(spec, record)
end

--- An argument whose type depends on earlier arguments (e.g. `set <property> <value>`). Its value is `unknown`.
function Command.Dynamic(resolve: (request: Types.DynamicArgRequest) -> Type<unknown>?, options: ArgOptionsOf<unknown>?): ArgSpecOf<"dynamic", Type<string>>
	const record: ErasedSpec = {
		Kind = "dynamic",
		Type = DYNAMIC_PLACEHOLDER,
		Options = copyOptions(options),
		Resolve = resolve,
	}
	const spec: ArgSpecOf<"dynamic", Type<string>> = {
		Kind = "dynamic",
		Type = DYNAMIC_PLACEHOLDER,
		Options = record.Options,
		DefaultValue = record.DefaultValue,
		DefaultDisplay = record.DefaultDisplay,
		Validate = record.Validate,
		Resolve = record.Resolve,
	}
	table.freeze(spec)
	return registerSpec(spec, record)
end

--- Defines a command. Attach handlers with `:Run()` (server) and/or `:ClientRun()` (client).
function Command.new<A>(definition: CommandDefinition<A>): Types.CommandBuilder<TypeFunctions.ArgsOf<A>>
	checkName(definition.Name, "command name")
	const aliases: { string } = {}
	for _, alias in definition.Aliases or {} do
		checkName(alias, `alias of '{definition.Name}'`)
		table.insert(aliases, alias)
	end
	const args = bindArgs(definition.Name, definition.Args)

	local pipe = definition.Pipe
	for _, arg in args do
		if arg.Options.Pipe then
			assert(pipe == nil or pipe == arg.Name, `RoShell: '{definition.Name}' has two pipe arguments`)
			pipe = arg.Name
		end
	end
	if pipe then
		local found = false
		for _, arg in args do
			found = found or arg.Name == pipe
		end
		assert(found, `RoShell: '{definition.Name}' Pipe '{pipe}' is not an argument`)
	end

	const subcommands: { Types.Command } = {}
	for _, subcommand in definition.Subcommands or {} do
		table.insert(subcommands, subcommand)
	end
	const autoExec: { string } = {}
	for _, line in definition.AutoExec or {} do
		table.insert(autoExec, line)
	end
	table.freeze(autoExec)

	lastCommandId += 1
	type V = TypeFunctions.ArgsOf<A>
	-- Handler setters store erased wrappers. `Unsafe.Assume(args) :: V` is the schema boundary described in
	-- Unsafe.luau: `args` is built by the resolver from exactly this command's `Args`.
	const command: Types.CommandBuilder<V> = {
		Name = definition.Name,
		Aliases = table.freeze(aliases),
		Description = definition.Description or "",
		Details = definition.Details,
		Group = definition.Group,
		Examples = normalizeExamples(definition.Examples),
		Hidden = definition.Hidden == true,
		Deprecated = normalizeDeprecation(definition.Deprecated),
		Args = args,
		Subcommands = table.freeze(subcommands),
		Permissions = definition.Permissions,
		Cooldown = definition.Cooldown,
		RateLimit = definition.RateLimit,
		Timeout = definition.Timeout,
		Destructive = definition.Destructive == true,
		SupportsDryRun = definition.SupportsDryRun == true,
		Pipe = pipe,
		Returns = definition.Returns,
		AutoExec = autoExec,
		Hooks = definition.Hooks,
		_parent = nil :: Types.Command?,
		_run = nil :: Types.ErasedHandler?,
		_clientRun = nil :: Types.ErasedHandler?,
		_validate = nil :: Types.ErasedValidate?,
		_preview = nil :: Types.ErasedPreview?,
		_data = nil :: Types.ErasedData?,
		_isDefault = false,
		_isAlias = false,
		_aliasBody = nil :: string?,
		_id = lastCommandId,

		Run = function(self: Types.CommandBuilder<V>, handler: Types.Handler<V>): Types.CommandBuilder<V>
			self._run = function(ctx: Types.Context, values: Types.ArgValues): Types.Output
				return handler(ctx, Unsafe.Assume(values) :: V)
			end
			return self
		end,
		ClientRun = function(self: Types.CommandBuilder<V>, handler: Types.Handler<V>): Types.CommandBuilder<V>
			self._clientRun = function(ctx: Types.Context, values: Types.ArgValues): Types.Output
				return handler(ctx, Unsafe.Assume(values) :: V)
			end
			return self
		end,
		Validate = function(
			self: Types.CommandBuilder<V>,
			validator: (ctx: Types.Context, args: V) -> (boolean, string?)
		): Types.CommandBuilder<V>
			self._validate = function(ctx: Types.Context, values: Types.ArgValues): (boolean, string?)
				return validator(ctx, Unsafe.Assume(values) :: V)
			end
			return self
		end,
		Preview = function(self: Types.CommandBuilder<V>, preview: (ctx: Types.Context, args: V) -> { string }): Types.CommandBuilder<V>
			self._preview = function(ctx: Types.Context, values: Types.ArgValues): { string }
				return preview(ctx, Unsafe.Assume(values) :: V)
			end
			return self
		end,
		Data = function(self: Types.CommandBuilder<V>, collector: (ctx: Types.Context, args: V) -> unknown): Types.CommandBuilder<V>
			self._data = function(ctx: Types.Context, values: Types.ArgValues): unknown
				return collector(ctx, Unsafe.Assume(values) :: V)
			end
			return self
		end,
	}
	for _, subcommand in subcommands do
		subcommand._parent = command
	end
	knownCommands[command] = command
	return command
end

--- Creates an alias/macro command: running `name a b` runs `body` with `$1`, `$2` (and `$@`) bound to the words.
function Command.Alias(name: string, body: string, description: string?): Types.Command
	const command = Command.new({
		Name = name,
		Description = description or body,
		Group = "Aliases",
		Args = {
			{ args = Command.Rest(ALIAS_ARGUMENT, { Description = "Values for $1, $2, ... in the alias body" }) },
		},
	})
	command._isAlias = true
	command._aliasBody = body
	return command
end

--- Returns the command for a value that is a RoShell command (e.g. a module's return value), or nil.
function Command.Lookup(value: unknown): Types.Command?
	return knownCommands[value]
end

--- Creates a typed environment key for `Registry:AddEnv` / `ctx:GetEnv`. The key keeps the values (per owner).
function Command.EnvKey<T>(name: string): Types.EnvKey<T>
	const values: { [unknown]: T } = setmetatable({}, { __mode = "k" })
	const key: Types.EnvKey<T> = {
		Name = name,
		_get = function(owner: unknown): T?
			return values[owner]
		end,
		_set = function(owner: unknown, value: T?)
			if value == nil then
				values[owner] = nil
			else
				values[owner] = value
			end
		end,
	}
	return table.freeze(key)
end

--- True when the command (or its parent) has an implementation for this side.
function Command.HasImplementation(command: Types.Command, isClient: boolean): boolean
	return command._run ~= nil or (isClient and command._clientRun ~= nil)
end

--- Full name including parents (`team add`).
function Command.FullName(command: Types.Command): string
	const parent = command._parent
	if parent then
		return Command.FullName(parent) .. " " .. command.Name
	end
	return command.Name
end

--- A one-line signature such as `give <targets: players> <item: item> [amount: integer = 1] [--silent]`.
function Command.Signature(command: Types.Command): string
	const parts: { string } = { Command.FullName(command) }
	for _, arg in command.Args do
		if arg.Options.Hidden then
			continue
		end
		const typeName = arg.Type.Name
		if arg.Kind == "flag" then
			table.insert(parts, `[--{arg.Name}]`)
		elseif not arg.Positional then
			table.insert(parts, `[--{arg.Name} <{typeName}>]`)
		elseif arg.Kind == "required" then
			table.insert(parts, `<{arg.Name}: {typeName}>`)
		elseif arg.Kind == "rest" then
			table.insert(parts, `<...{arg.Name}: {typeName}>`)
		elseif arg.Kind == "default" then
			table.insert(parts, `[{arg.Name}: {typeName} = {arg.DefaultDisplay or "?"}]`)
		else
			table.insert(parts, `[{arg.Name}: {typeName}]`)
		end
	end
	return table.concat(parts, " ")
end

return table.freeze(Command)
