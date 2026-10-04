--!strict
--[[
	Every public type in RoShell lives in this module, so modules can describe each other's shapes without
	runtime `require` cycles. Classes elsewhere implement the interface types declared here (methods are
	declared as `read` fields with `self` typed as the interface; see DESIGN_NOTES.md "Interfaces").

	Conventions:
	- Containers that carry a type parameter are read-only (`read` fields, `{ read T }` arrays) so the types
	  are covariant. That is what lets `Type<number>` flow into `Type<unknown>` without casts.
	- Spans are 1-based byte offsets, `Start` inclusive and `End` exclusive (`"giv"` is `{ Start = 1, End = 4 }`).
]]

--// Imports
-- Type functions only (TypeFunctions has no runtime dependencies, so this creates no cycle).
const TypeFunctions = require("./TypeFunctions")

--// Spans and diagnostics

export type Span = { Start: number, End: number }

export type Severity = "error" | "warning" | "info"

export type Diagnostic = {
	Severity: Severity,
	Message: string,
	Span: Span,
	Code: string?,
}

--// Results

export type Ok<T> = { read Ok: true, read Value: T }
export type Err<E> = { read Ok: false, read Error: E }
export type Result<T, E> = Ok<T> | Err<E>

--- Result of parsing argument text. `Display` is an optional human readable rendering of the value (used by
--- previews, echo lines and the audit log). `Progress` is how many bytes of the text were understood before the
--- error, used to pick the most relevant error among union members.
export type ParseResult<T> = ParseSuccess<T> | ParseError

export type ParseSuccess<T> = { read Ok: true, read Value: T, read Display: string? }

--- A failed parse. Not generic, so one error value fits every `ParseResult<T>`.
export type ParseError = {
	read Ok: false,
	read Error: string,
	read Span: Span?,
	read Progress: number?,
}

--// Fuzzy search

--- Precomputed per-candidate search data. Built once by `Fuzzy.Prepare` and cached.
export type FuzzyPrepared = {
	read Text: string,
	--- Codepoints of the text, and their ASCII-lowercased counterparts.
	read Codes: { read number },
	read LowerCodes: { read number },
	--- Byte offset of each codepoint (for highlight spans).
	read Offsets: { read number },
	--- Positional bonus of each codepoint (word boundaries, camelCase transitions...).
	read Bonus: { read number },
	--- Presence bitmask of the lowercased characters (prefilter).
	read Mask: number,
	read Length: number,
}

--- Codepoints of one fuzzy query term.
export type FuzzyTerm = { read number }

--- A prepared fuzzy query: one or more space-separated terms that must all match.
export type FuzzyQuery = {
	read Text: string,
	read Terms: { read FuzzyTerm },
	read LowerTerms: { read FuzzyTerm },
	read Mask: number,
	--- Smart case: true when the query contains an uppercase letter.
	read CaseSensitive: boolean,
	read Empty: boolean,
}

export type FuzzyMatch = {
	Score: number,
	--- Matched character ranges within the candidate text (byte spans).
	Ranges: { Span },
}

--// Completion

export type Suggestion = {
	--- Text inserted when the suggestion is accepted (already quoted/escaped as needed).
	Text: string,
	--- Label shown in the list.
	Display: string,
	--- Secondary text shown right-aligned (type, group, value...).
	Detail: string?,
	--- Longer description shown for the highlighted suggestion.
	Description: string?,
	--- "command" | "alias" | "subcommand" | "argument" | "flag" | "operator" | "variable" | "history" | "value" | ...
	Kind: string,
	Score: number,
	--- Highlight ranges within `Display`.
	MatchRanges: { Span },
	Icon: string?,
	--- Theme token used to tint the icon/chip.
	Color: string?,
	Swatch: Color3?,
	Deprecated: boolean?,
	--- When true, accepting does not finish the argument (no trailing space is inserted).
	Partial: boolean?,
	--- Snippet-style insertion; `Cursor` is relative to the start of `Text`.
	Insert: { Text: string, Cursor: number }?,
}

export type Candidate<T> = {
	read Key: string,
	read Value: T,
	read Aliases: { read string }?,
	read Description: string?,
	read Detail: string?,
	read Icon: string?,
	read Hidden: boolean?,
}

--// Shell handle and platform

--- Opaque identity of a shell, carried by requests. Generic types must not reference the full `Shell` type
--- (Luau forbids recursive generic aliases with different parameters, and `Shell` stores `Type<unknown>`s), so
--- requests carry this handle; `RoShell.GetShell(handle)` returns the full shell.
export type ShellHandle = { read Name: string, read Id: number }

--- Engine services, abstracted so the core runs headless (unit tests, fake players) and deterministically.
--- A one-shot rendezvous: `Wait` yields until `Open` is called (and returns at once if it already was). Unlike a
--- bare `coroutine.yield`/`coroutine.resume` pair it is safe for engine threads: when the waiting thread is a callback
--- such as `OnServerInvoke`, the engine still receives its return values.
export type Gate = { read Wait: () -> (), read Open: () -> () }

export type PlatformInfo = {
	read GetPlayers: () -> { Player },
	read GetTeams: () -> { Team },
	read GetLocalPlayer: () -> Player?,
	read IsStudio: () -> boolean,
	--- Unix time in seconds (with fractions).
	read Now: () -> number,
	--- Monotonic clock in seconds, for durations.
	read Clock: () -> number,
	--- Random integer in [minimum, maximum].
	read Random: (minimum: number, maximum: number) -> number,
	--- Runs `callback` in a new thread right away.
	read Spawn: (callback: () -> ()) -> thread,
	--- Runs `callback` after `seconds`.
	read Delay: (seconds: number, callback: () -> ()) -> thread,
	--- Cancels a thread created by Spawn/Delay.
	read Cancel: (thread: thread) -> (),
	--- Yields the current thread for `seconds`.
	read Wait: (seconds: number) -> (),
	read Gate: () -> Gate,
}

--// Requests passed to types

--- The common part of parse and complete requests (what candidate providers receive).
export type CandidateRequest = {
	read Executor: Player?,
	read Shell: ShellHandle,
	read Platform: PlatformInfo,
}

export type ParseRequest = {
	--- Text to parse: unquoted, unescaped, variables substituted.
	read Text: string,
	--- True when the whole argument was quoted. Operators and wildcards are disabled for quoted text.
	read Quoted: boolean,
	read Span: Span,
	read Executor: Player?,
	read Shell: ShellHandle,
	read Platform: PlatformInfo,
	--- True right before execution. Expensive or yielding validation may only run when this is true.
	read Final: boolean,
	read ArgName: string?,
}

export type CompleteRequest = {
	--- Partial text typed so far for this argument (unquoted).
	read Text: string,
	read Quoted: boolean,
	read Executor: Player?,
	read Shell: ShellHandle,
	read Platform: PlatformInfo,
	read Limit: number,
	read ArgName: string?,
}

--// Operators and selectors

--- Declarative description of an operator, used by help and by the completion operator list.
export type OperatorInfo = {
	read Symbol: string,
	read Name: string,
	read Description: string,
	read Example: string,
	--- Usable for single-value arguments.
	read Scalar: boolean,
	--- Usable for list arguments.
	read List: boolean,
}

--- A prefix selector such as `%Red` (team) or `#Boss` (tag). `Resolve` receives the text after the prefix.
export type Selector<T> = {
	read Prefix: string,
	read Name: string,
	read Description: string,
	read Example: string,
	read Complete: ((request: CompleteRequest) -> { Suggestion })?,
	read Resolve: (request: ParseRequest) -> ParseResult<{ read T }>,
}

--// Types

export type MatchingOptions = {
	read Plural: string,
	read AllowPatterns: boolean,
	read CaseSensitive: boolean,
}

--- Non-generic metadata view of a type (every `Type<T>` is a `TypeInfo`).
export type TypeInfo = {
	read Name: string,
	read Description: string?,
	read Examples: { read string }?,
	read Kind: string,
	read Id: number,
	read Listable: boolean,
	read Element: TypeInfo?,
	read Operators: { read OperatorInfo },
	read Color: string?,
	read Icon: string?,
}

--- A first-class argument type. Build one with `RoShell.Type.*`; every field is derived by the constructors.
export type Type<T> = {
	--- Display name ("players", "item"). Also the key in the registry type index.
	read Name: string,
	read Description: string?,
	read Examples: { read string }?,
	--- Constructor family ("choice", "number", "list", ...).
	read Kind: string,
	--- Unique identity used for pipe assignability checks.
	read Id: number,
	read Parse: (request: ParseRequest) -> ParseResult<T>,
	read Complete: (request: CompleteRequest) -> { Suggestion },
	--- Enumerable types list their universe of values; operators (`*`, globs, `~fuzzy`, set arithmetic) work on these.
	read Enumerate: ((request: CandidateRequest) -> { read Candidate<T> })?,
	--- Expands one list item into several values (numeric ranges such as `1..10/2`). Returns nil when the text is
	--- not an expandable form.
	read Expand: ((request: ParseRequest) -> ParseResult<{ read T }>?)?,
	--- The implicit value of this type for the executor (what `.`/`me` resolves to, e.g. the executing player).
	read Default: ((request: ParseRequest) -> T?)?,
	--- Prefix selectors (e.g. `%Team`) accepted by this type.
	read Selectors: { read Selector<T> }?,
	--- Matching options of enumerable types (used when a list of this type is built).
	read Matching: MatchingOptions?,
	--- True for list types (`Type<{ T }>`), which accept `a,b,c` and set arithmetic.
	read Listable: boolean,
	--- For list/optional wrappers: the wrapped element type.
	read Element: TypeInfo?,
	--- Operators this type accepts, for help and completion.
	read Operators: { read OperatorInfo },
	--- Theme token for the type badge, and an icon name.
	read Color: string?,
	read Icon: string?,
	--- True when parsing may yield (validated only on `Final` requests).
	read Yields: boolean,
}

--// Arguments

export type ArgKind = "required" | "optional" | "default" | "rest" | "flag" | "dynamic"

export type DynamicArgRequest = {
	read Shell: ShellHandle,
	read Platform: PlatformInfo,
	read Executor: Player?,
	--- Values of the previous arguments, keyed by argument name (only successfully parsed ones).
	read Previous: { read [string]: unknown },
}

--- Options accepted by every argument constructor (stored frozen, hence read-only).
export type ArgOptions = {
	read Description: string?,
	--- Single character short flag (`-n`).
	read Short: string?,
	--- Named-only: never bound positionally, only through `--name value` / `name=value`.
	read Named: boolean?,
	read Hidden: boolean?,
	read Examples: { string }?,
	--- For list arguments: prompt for confirmation when more than this many values are targeted.
	read RequireConfirmAbove: number?,
	--- For list arguments: an empty resolution is allowed instead of being an error.
	read AllowEmpty: boolean?,
	--- This argument receives the value piped into the command (`a | b`).
	read Pipe: boolean?,
}

--- An argument specification as returned by `RoShell.Arg` and friends. `K` is the argument kind and `Ty` the
--- exact type of the type object; `ArgsOf` reads both to compute the typed `args` record handed to `Run`.
--- The remaining fields are erased at construction time (while the precise value type is still in scope).
export type ArgSpecOf<K, Ty> = {
	read Kind: K,
	read Type: Ty,
	read Options: ArgOptions,
	--- Produces the default value (default arguments).
	read DefaultValue: ((request: ParseRequest) -> unknown)?,
	--- Display text of the default in signatures ("1", "you").
	read DefaultDisplay: string?,
	--- Extra validation, already wrapped to accept the parsed value.
	read Validate: ((value: unknown, request: ParseRequest) -> (boolean, string?))?,
	--- Dynamic arguments compute their type from earlier argument values.
	read Resolve: ((request: DynamicArgRequest) -> Type<unknown>?)?,
}

--- An argument bound to its command, with its type looked up (the registry's erased view).
export type BoundArg = {
	read Name: string,
	read Kind: ArgKind,
	read Type: Type<unknown>,
	read Options: ArgOptions,
	read DefaultValue: ((request: ParseRequest) -> unknown)?,
	read DefaultDisplay: string?,
	read Validate: ((value: unknown, request: ParseRequest) -> (boolean, string?))?,
	read Resolve: ((request: DynamicArgRequest) -> Type<unknown>?)?,
	--- 1-based index among all arguments of the command.
	read Index: number,
	--- True when the argument can be supplied positionally.
	read Positional: boolean,
	--- True when the argument can be omitted.
	read Optional: boolean,
}

--- Values of a command's arguments keyed by argument name, as stored before being handed to `Run`.
export type ArgValues = { [string]: unknown }

--// Output

export type Level = "plain" | "info" | "success" | "warning" | "error" | "muted" | "echo"

export type TableRow = { read string }
export type KeyValueEntry = { read Key: string, read Value: string }

export type TextBlock = {
	read Kind: "text",
	read Text: string,
	read Level: Level,
	read Rich: boolean?,
}
export type TableBlock = {
	read Kind: "table",
	read Title: string?,
	read Columns: { read string },
	read Rows: { read TableRow },
}
export type ListBlock = {
	read Kind: "list",
	read Title: string?,
	read Items: { read string },
	read Level: Level?,
}
export type KeyValueBlock = {
	read Kind: "keyvalue",
	read Title: string?,
	read Entries: { read KeyValueEntry },
}
export type ColorBlock = {
	read Kind: "color",
	read Color: Color3,
	read Label: string,
}
export type ProgressBlock = {
	read Kind: "progress",
	read Id: string,
	read Label: string,
	read Fraction: number?,
}
export type ValueBlock = {
	read Kind: "value",
	read Display: string,
	read TypeName: string?,
	--- Individual item labels for list values (rendered as chips).
	read Items: { read string }?,
}
export type LinkBlock = { read Kind: "link", read Text: string, read Url: string }
export type CustomBlock = {
	read Kind: "custom",
	read Renderer: string,
	read Data: unknown,
}

export type Block = TextBlock | TableBlock | ListBlock | KeyValueBlock | ColorBlock | ProgressBlock | ValueBlock | LinkBlock | CustomBlock

--- Structured return value of a command. Build one with the `ctx:Success/Info/Warn/Error/Value/Table...` helpers.
export type Reply = {
	read _reply: true,
	read Ok: boolean,
	--- Failure message (only when `Ok` is false).
	read Message: string?,
	--- Structured value for pipes, `$$` and embedded substitution.
	read Value: unknown,
	read ValueType: Type<unknown>?,
	read Display: string?,
	--- Blocks that still need to be shown (blocks emitted through `ctx` helpers are already shown).
	read Blocks: { read Block },
}

--- What a command handler may return.
export type Output = string | Reply | Result<unknown, string> | nil

--- The outcome of one executed command.
export type CommandResult = {
	read Ok: boolean,
	read Command: string?,
	read Message: string?,
	read Value: unknown,
	read ValueType: Type<unknown>?,
	read Display: string?,
	read Blocks: { read Block },
	read Duration: number,
	read Cancelled: boolean,
	--- Server-held reference to `Value` (set when the command ran remotely).
	read Ref: string?,
}

--- The outcome of running a whole input script (chains, pipes, several statements).
export type RunResult = {
	read Ok: boolean,
	read Results: { read CommandResult },
	read Last: CommandResult?,
	read Diagnostics: { read Diagnostic },
	read Cancelled: boolean,
}

--- A value flowing into a command through `|`.
export type PipedInput = {
	read Value: unknown,
	read Type: Type<unknown>?,
	read Display: string,
	--- Server-held reference to `Value`, when it came from a remote command.
	read Ref: string?,
}

--// Prompts

export type PromptKind = "confirm" | "choice" | "text"

export type PromptRequest = {
	Kind: PromptKind,
	Title: string?,
	Message: string,
	Choices: { string }?,
	Default: string?,
	Placeholder: string?,
	Destructive: boolean?,
	--- Seconds before the prompt resolves as cancelled. Defaults to 60.
	Timeout: number?,
}

--- `nil` when cancelled/timed out. Confirm prompts answer `"yes"`/`"no"`.
export type PromptAnswer = string?

--// Cancellation

export type CancelToken = {
	read IsCancelled: (self: CancelToken) -> boolean,
	read Cancel: (self: CancelToken, reason: string?) -> (),
	read OnCancel: (self: CancelToken, callback: (reason: string?) -> ()) -> () -> (),
	read Reason: (self: CancelToken) -> string?,
	_cancelled: boolean,
	_reason: string?,
	_callbacks: { (reason: string?) -> () },
}

--// Environment keys

--- A typed key for `Registry:AddEnv` / `ctx:GetEnv`. Create with `RoShell.EnvKey<T>(name)`. The key stores the
--- values itself (per owner), so reading needs no casts.
export type EnvKey<T> = {
	read Name: string,
	read _get: (owner: unknown) -> T?,
	read _set: (owner: unknown, value: T?) -> (),
}

--// Undo

export type UndoAction = { Description: string, Undo: () -> (), Redo: (() -> ())? }

--// Permissions

export type PermissionRequest = {
	read Player: Player?,
	read Command: Command,
	read Shell: Shell,
	--- Parsed argument values, when checking right before execution.
	read Args: ArgValues?,
}

export type Permission = {
	read Kind: string,
	--- May yield (group ranks, game passes); results are cached by the built-in checks.
	read Check: (request: PermissionRequest) -> boolean,
	read Describe: () -> string,
}

--// Hooks and middleware

--- Return a message to block the command.
export type BeforeRunHook = (ctx: Context) -> string?
export type AfterRunHook = (ctx: Context, result: CommandResult) -> ()
export type ErrorHook = (ctx: Context, message: string) -> ()
export type Middleware = (ctx: Context, nextHandler: () -> CommandResult) -> CommandResult

export type CommandHooks = {
	BeforeRun: BeforeRunHook?,
	AfterRun: AfterRunHook?,
	OnError: ErrorHook?,
}

--// Commands

export type Example = { read Text: string, read Description: string? }

export type DeprecationInfo = { read Message: string?, read Replacement: string? }

export type RateLimitOptions = {
	--- Maximum number of runs in `Per` seconds.
	Count: number,
	Per: number,
	--- "player" (default): per executor. "global": shared by everyone.
	Scope: ("player" | "global")?,
}

--- A command handler with its arguments erased (see Command.luau for where the record is typed).
export type ErasedHandler = (ctx: Context, args: ArgValues) -> Output
export type ErasedPreview = (ctx: Context, args: ArgValues) -> { string }
export type ErasedValidate = (ctx: Context, args: ArgValues) -> (boolean, string?)
export type ErasedData = (ctx: Context, args: ArgValues) -> unknown

--- A registered command. `CommandBuilder<V>` (returned by `RoShell.Command`) is a `Command` with typed setters.
export type Command = {
	read Name: string,
	read Aliases: { read string },
	read Description: string,
	read Details: string?,
	read Group: string?,
	--- Icon key shown next to the command in the console (a Builder Icons name such as `cube`, or a type icon).
	read Icon: string?,
	read Examples: { read Example },
	read Hidden: boolean,
	read Deprecated: DeprecationInfo?,
	--- Arguments in declaration order.
	read Args: { read BoundArg },
	read Subcommands: { read Command },
	read Permissions: Permission?,
	read Cooldown: number?,
	read RateLimit: RateLimitOptions?,
	read Timeout: number?,
	read Destructive: boolean,
	read SupportsDryRun: boolean,
	--- Name of the argument that receives piped input.
	read Pipe: string?,
	--- Type of the value this command returns (enables pipe type checks).
	read Returns: Type<unknown>?,
	read AutoExec: { read string },
	read Hooks: CommandHooks?,
	--- Parent command for subcommands.
	_parent: Command?,
	_run: ErasedHandler?,
	_clientRun: ErasedHandler?,
	_validate: ErasedValidate?,
	_preview: ErasedPreview?,
	_data: ErasedData?,
	_isDefault: boolean,
	--- Set for user aliases/macros (`alias name = "body"`): the body runs with `$1..$9` bound to the words.
	_isAlias: boolean,
	_aliasBody: string?,
	_id: number,
}

--- Typed command handler.
export type Handler<V> = (ctx: Context, args: V) -> Output

--- A command with typed handler setters. `V` is the record of argument values computed from `Args`.
export type CommandBuilder<V> = Command & {
	--- Server implementation.
	read Run: (self: CommandBuilder<V>, handler: Handler<V>) -> CommandBuilder<V>,
	--- Client implementation. If it returns nil and `Run` exists, execution continues on the server.
	read ClientRun: (self: CommandBuilder<V>, handler: Handler<V>) -> CommandBuilder<V>,
	--- Cross-argument validation, run before permissions and execution.
	read Validate: (
		self: CommandBuilder<V>,
		validator: (ctx: Context, args: V) -> (boolean, string?)
	) -> CommandBuilder<V>,
	--- Dry-run preview (`--dry`): lines describing what would happen.
	read Preview: (self: CommandBuilder<V>, preview: (ctx: Context, args: V) -> { string }) -> CommandBuilder<V>,
	--- Client-side data collector; its return value is sent to the server and available as `ctx:GetData()`.
	read Data: (self: CommandBuilder<V>, collector: (ctx: Context, args: V) -> unknown) -> CommandBuilder<V>,
}

--// Context

export type ProgressOptions = { Label: string?, Fraction: number? }

export type TableData = {
	Title: string?,
	Columns: { string },
	Rows: { { string } },
}

export type Store = { [unknown]: unknown }

export type BroadcastOptions = {
	--- "server" (all players in this server, default) or "global" (every server through MessagingService).
	Scope: ("server" | "global")?,
	Level: Level?,
}

export type RunOptions = {
	--- Evaluate a dry run (commands that support it show a preview instead of executing).
	Dry: boolean?,
	--- Skip confirmation prompts (`--yes`).
	Yes: boolean?,
	--- Client payload gathered by the command's `Data` collector.
	Data: unknown,
	--- True when typed by a person in the console (history is recorded, prompts are allowed).
	IsHuman: boolean?,
	--- Positional parameters for macros (`$1..$9`, `$@`).
	Params: { string }?,
	--- Internal: alias/embed nesting depth.
	Depth: number?,
	--- Internal: don't display result values (embedded commands).
	Quiet: boolean?,
}

export type Context = {
	read Shell: Shell,
	read Executor: Player?,
	read Command: Command,
	--- Name the command was invoked with (may be an alias).
	read Alias: string,
	--- Source text of this command invocation.
	read RawText: string,
	read IsClient: boolean,
	read IsServer: boolean,
	read Dry: boolean,
	read Token: CancelToken,
	read Options: RunOptions,
	--- Value piped into this command, if any.
	read Piped: PipedInput?,

	--- Shows a line of output right away.
	read Reply: (self: Context, text: string, level: Level?) -> (),
	--- Shows a success line and returns a successful Reply.
	read Success: (self: Context, text: string) -> Reply,
	read Info: (self: Context, text: string) -> Reply,
	read Warn: (self: Context, text: string) -> Reply,
	--- Shows an error line and returns a failed Reply (fails `&&` chains when returned).
	read Error: (self: Context, text: string) -> Reply,
	read Table: (self: Context, data: TableData) -> Reply,
	read List: (self: Context, items: { string }, title: string?) -> Reply,
	read KeyValue: (self: Context, entries: { { Key: string, Value: string } }, title: string?) -> Reply,
	read Color: (self: Context, color: Color3, label: string?) -> Reply,
	read Link: (self: Context, text: string, url: string) -> Reply,
	read Block: (self: Context, block: Block) -> (),
	--- Returns a typed value (for pipes, `$$` and embedding). Displayed when it is the final result.
	--- The value is checked against the type object's value type (`T` is not widened by the value argument).
	read Value: <Ty>(self: Context, valueType: Ty, value: TypeFunctions.ValueOf<Ty>, display: string?) -> Reply,

	read Prompt: (self: Context, prompt: PromptRequest) -> PromptAnswer,
	read Confirm: (self: Context, message: string, destructive: boolean?) -> boolean,
	read Choose: (self: Context, message: string, choices: { string }) -> string?,
	read Input: (self: Context, message: string, placeholder: string?) -> string?,
	read Progress: (self: Context, options: ProgressOptions) -> (),
	read Cancelled: (self: Context) -> boolean,
	--- Errors with a cancellation marker if the command was cancelled (use inside long loops).
	read CheckCancelled: (self: Context) -> (),

	read GetStore: (self: Context, name: string) -> Store,
	read GetData: (self: Context) -> unknown,
	read GetEnv: <T>(self: Context, key: EnvKey<T>) -> T?,
	--- Shows a message to every player of this server, and with `Scope = "global"` every other server too. Returns
	--- false and why when other servers could not be reached (this server's players still see it).
	read Broadcast: (self: Context, message: string, options: BroadcastOptions?) -> (boolean, string?),
	read Log: (self: Context, message: string) -> (),
	read Undoable: (self: Context, action: UndoAction) -> (),
	--- Runs another command line as the same executor and returns its result.
	read Run: (self: Context, text: string) -> RunResult,
	read SendEvent: (self: Context, player: Player, name: string, payload: unknown) -> (),

	_emit: (block: Block) -> (),
	_prompt: ((prompt: PromptRequest) -> PromptAnswer)?,
	_progressId: string?,
	_data: unknown,
	_logs: { string },
}

--// Storage, audit and telemetry adapters

--- Persistence adapter. Values must be JSON-compatible. Methods may yield.
export type StorageAdapter = {
	read Get: (self: StorageAdapter, scope: string, key: string) -> unknown,
	read Set: (self: StorageAdapter, scope: string, key: string, value: unknown) -> (),
	read Remove: (self: StorageAdapter, scope: string, key: string) -> (),
}

export type AuditEntry = {
	Time: number,
	Executor: string,
	ExecutorId: number?,
	Raw: string,
	Command: string,
	Args: { [string]: string },
	Ok: boolean,
	Result: string?,
	Duration: number,
}

export type AuditSink = {
	read Write: (self: AuditSink, entry: AuditEntry) -> (),
	read Recent: ((self: AuditSink, count: number) -> { AuditEntry })?,
}

export type TelemetryEvent = {
	Command: string,
	Ok: boolean,
	Duration: number,
	Executor: Player?,
}

export type TelemetrySink = {
	read Record: (self: TelemetrySink, event: TelemetryEvent) -> (),
}

--// Locale

export type Locale = {
	read Get: (self: Locale, key: string, params: { [string]: string | number }?) -> string,
	read Set: (self: Locale, overrides: { [string]: string }) -> (),
	_strings: { [string]: string },
}

--// Signals

export type Connection = {
	read Disconnect: (self: Connection) -> (),
	Connected: boolean,
	_disconnect: () -> (),
}

export type Signal<T...> = {
	read Connect: (self: Signal<T...>, callback: (T...) -> ()) -> Connection,
	read Once: (self: Signal<T...>, callback: (T...) -> ()) -> Connection,
	read Fire: (self: Signal<T...>, T...) -> (),
	read Wait: (self: Signal<T...>) -> T...,
	read DisconnectAll: (self: Signal<T...>) -> (),
	_handlers: { (T...) -> () },
	_connections: { Connection },
}

--// Registry

export type FunctionDefinition = {
	Name: string,
	Description: string?,
	--- Arguments are the raw comma separated strings between the parentheses: `$random(1, 10)`.
	Call: (request: FunctionCallRequest) -> string,
}

export type FunctionCallRequest = {
	read Args: { read string },
	read Executor: Player?,
	read Shell: ShellHandle,
	read Platform: PlatformInfo,
}

--// Themes and renderers (consumed by the client UI; declared here so plugins and the registry can carry them)

export type ThemeSyntaxOverrides = {
	Command: string?,
	Argument: string?,
	Number: string?,
	String: string?,
	Operator: string?,
	Flag: string?,
	Variable: string?,
	Comment: string?,
	Error: string?,
}

export type ThemeTypeOverrides = {
	Player: string?,
	Team: string?,
	Number: string?,
	String: string?,
	Boolean: string?,
	Instance: string?,
	Color: string?,
	Enum: string?,
	Command: string?,
	Variable: string?,
	Default: string?,
}

--- `#RRGGBB` colors replacing tokens of the base theme.
export type ThemeOverrides = {
	Window: string?,
	Elevated: string?,
	Input: string?,
	Hover: string?,
	Selected: string?,
	Border: string?,
	BorderFocus: string?,
	Text: string?,
	TextSecondary: string?,
	TextMuted: string?,
	TextInverse: string?,
	Accent: string?,
	AccentHover: string?,
	Success: string?,
	Warning: string?,
	Error: string?,
	Info: string?,
	Shadow: string?,
	Syntax: ThemeSyntaxOverrides?,
	Types: ThemeTypeOverrides?,
}

export type ThemeOptions = {
	Name: string,
	--- One line shown in the theme picker.
	Description: string?,
	--- Preset (or previously created theme) the overrides apply to. Defaults to "Midnight".
	Base: string?,
	Dark: boolean?,
	Overrides: ThemeOverrides?,
}

--- Turns the data of a `custom` output block into a standard block for display (client side).
export type OutputRenderer = (data: unknown) -> Block?

export type Plugin = {
	Name: string,
	Commands: { Command }?,
	Types: { Type<unknown> }?,
	Functions: { FunctionDefinition }?,
	Hooks: CommandHooks?,
	Middleware: { Middleware }?,
	--- Theme definitions are consumed by the client UI (see Client/UI/Theme).
	Themes: { ThemeOptions }?,
	--- Renderers for `custom` output blocks, keyed by renderer name.
	Renderers: { [string]: OutputRenderer }?,
	Setup: ((shell: Shell) -> ())?,
}

export type RegistryChange = "commands" | "types" | "functions" | "all"

export type Registry = {
	--- Fired after anything is registered/unregistered (used for hot reload and cache invalidation).
	read Changed: Signal<RegistryChange>,

	read RegisterType: (self: Registry, valueType: Type<unknown>) -> (),
	read RegisterTypes: (self: Registry, valueTypes: { Type<unknown> }) -> (),
	read GetType: (self: Registry, name: string) -> Type<unknown>?,
	read GetTypes: (self: Registry) -> { Type<unknown> },

	read RegisterCommand: (self: Registry, command: Command) -> (),
	read RegisterCommands: (self: Registry, commands: { Command }) -> (),
	--- Requires every ModuleScript under `container` (recursively) that returns a command, or a list of commands.
	read RegisterCommandsIn: (self: Registry, container: Instance, filter: ((command: Command) -> boolean)?) -> (),
	--- Registers the built-in commands; `filter` is a list of groups or a predicate.
	read RegisterDefaultCommands: (self: Registry, filter: ({ string } | (command: Command) -> boolean)?) -> (),
	read UnregisterCommand: (self: Registry, name: string) -> boolean,
	--- Hot reload: re-requires (fresh copies of) every container given to `RegisterCommandsIn`. Returns the count.
	read ReloadCommands: (self: Registry) -> number,
	read GetCommand: (self: Registry, name: string) -> Command?,
	read GetCommands: (self: Registry) -> { Command },
	read GetCommandNames: (self: Registry, includeAliases: boolean?) -> { string },

	--- Registers global hooks (every field optional). Returns a function that unregisters them.
	read RegisterHooks: (self: Registry, hooks: CommandHooks, priority: number?) -> () -> (),
	read RegisterMiddleware: (self: Registry, middleware: Middleware, priority: number?) -> () -> (),
	--- Registers a `@name:` selector for a type (e.g. `@role:Admin` for players). The selector's values are matched
	--- back to the type's candidates, so only real values of that type are ever produced.
	read RegisterSelector: (self: Registry, valueType: TypeInfo, selector: Selector<unknown>) -> (),
	read GetSelectors: (self: Registry, typeId: number) -> { Selector<unknown> },
	read RegisterFunction: (self: Registry, definition: FunctionDefinition) -> (),
	read GetFunction: (self: Registry, name: string) -> FunctionDefinition?,
	read GetFunctions: (self: Registry) -> { FunctionDefinition },
	read RegisterPlugin: (self: Registry, plugin: Plugin) -> (),
	read AddEnv: <T>(self: Registry, key: EnvKey<T>, value: T) -> (),
	read GetEnv: <T>(self: Registry, key: EnvKey<T>) -> T?,
	read GetStore: (self: Registry, name: string) -> Store,
	--- Monotonic counter bumped on every change; caches compare against it.
	read Version: (self: Registry) -> number,
	--- Load every ModuleScript under `container` that returns a type (or a list/record of types). Returns the count.
	read RegisterTypesIn: (self: Registry, container: Instance) -> number,
	--- Load every ModuleScript under `container` that returns `RoShell.Hooks({ ... })`. Returns the count.
	read RegisterHooksIn: (self: Registry, container: Instance) -> number,
	--- Themes for the console (clients create them when the console starts or the registry changes).
	read RegisterTheme: (self: Registry, options: ThemeOptions) -> (),
	read GetThemes: (self: Registry) -> { ThemeOptions },
	--- Renders `custom` output blocks with this name (`ctx:Block({ Kind = "custom", Renderer = name, Data = ... })`).
	read RegisterOutputRenderer: (self: Registry, name: string, renderer: OutputRenderer) -> (),
	read GetOutputRenderer: (self: Registry, name: string) -> OutputRenderer?,

	_commands: { [string]: Command },
	_commandList: { Command },
	_types: { [string]: Type<unknown> },
	_typeList: { Type<unknown> },
	_functions: { [string]: FunctionDefinition },
	_selectors: { [number]: { Selector<unknown> } },
	_beforeRun: { { Priority: number, Hook: BeforeRunHook } },
	_afterRun: { { Priority: number, Hook: AfterRunHook } },
	_onError: { { Priority: number, Hook: ErrorHook } },
	_middleware: { { Priority: number, Middleware: Middleware } },
	_stores: { [string]: Store },
	_version: number,
	_themes: { ThemeOptions },
	_renderers: { [string]: OutputRenderer },
	_handle: ShellHandle,
	_containers: { { Container: Instance, Filter: ((command: Command) -> boolean)? } },
	--- `RegisterDefaultCommands` was called (servers and clients then skip registering them on `Start`).
	_defaultsRegistered: boolean,
}

--// Shell

export type ShellOptions = {
	--- Instance namespace for remotes and logging. Defaults to "RoShell". Allows several shells side by side.
	Name: string?,
	--- When true (default), every command is allowed in Studio regardless of permissions.
	StudioBypass: boolean?,
	--- Global command timeout in seconds (0 disables). Defaults to 60.
	Timeout: number?,
}

--- A server-held value that a client can reference (`$:id`) without ever sending the value itself.
export type HeldValue = {
	Value: unknown,
	Type: Type<unknown>?,
	Display: string,
	Expires: number,
}

--- Per-executor state.
export type Session = {
	--- Variables set with `set` (`$name`).
	Variables: { [string]: string },
	--- Result of the last top-level command (`$$`).
	Last: CommandResult?,
	Undo: { UndoAction },
	Redo: { UndoAction },
	--- Values held for remote reference (server side).
	Held: { [string]: HeldValue },
	History: { string },
}

export type Shell = {
	read Name: string,
	read Id: number,
	--- The handle carried by requests (`RoShell.GetShell(handle)` maps it back to this shell).
	read Handle: ShellHandle,
	read IsServer: boolean,
	read IsClient: boolean,
	read Registry: Registry,
	read Dispatcher: Dispatcher,
	read Permissions: PermissionManager,
	read Locale: Locale,
	read Platform: PlatformInfo,
	read Options: ShellOptions,
	read Storage: StorageAdapter,
	--- Returns (creating if needed) the state of an executor.
	read GetSession: (self: Shell, executor: Player?) -> Session,
	_sessions: { [string]: Session },
	--- Transport used for server-side execution from a client shell (nil on the server and in tests).
	_transport: Transport?,
	_audit: AuditSink?,
	_telemetry: TelemetrySink?,
	--- Server/all-servers broadcast hook.
	_broadcast: ((message: string, options: BroadcastOptions?, executor: Player?) -> (boolean, string?))?,
	--- Sends a custom event to a player (server) or handles it locally (client).
	_sendEvent: ((player: Player, name: string, payload: unknown) -> ())?,
	_nextRef: number,
}

--// Permission manager

export type PermissionManager = {
	--- Grants a permission to every command of a group.
	read SetGroup: (self: PermissionManager, group: string, permission: Permission) -> (),
	read GetGroup: (self: PermissionManager, group: string) -> Permission?,
	--- Defines a role: a named permission that commands reference with `Permissions.Role("name")`.
	read DefineRole: (self: PermissionManager, role: string, permission: Permission) -> (),
	read GetRole: (self: PermissionManager, role: string) -> Permission?,
	--- Players the rule grants may run every command, whatever the command's own rule (nil removes it).
	read SetAdmins: (self: PermissionManager, permission: Permission?) -> (),
	read CanRun: (self: PermissionManager, player: Player?, command: Command, args: ArgValues?) -> (boolean, string?),
	read CanSee: (self: PermissionManager, player: Player?, command: Command) -> boolean,
	_groups: { [string]: Permission },
	_roles: { [string]: Permission },
	_admins: Permission?,
	_handle: ShellHandle,
	--- Client shells: the commands the server says this player may see (mirrors server permissions).
	_visibility: { [string]: true }?,
}

--// Transport (client -> server execution)

export type RemoteRunRequest = {
	Text: string,
	Options: RunOptions,
	--- Piped input: a reference to a server-held value, or plain text (re-parsed by the server).
	Pipe: { Ref: string?, Text: string? }?,
}

export type Transport = {
	read RunRemote: (self: Transport, request: RemoteRunRequest, token: CancelToken, onBlock: (block: Block) -> (), onPrompt: ((prompt: PromptRequest) -> PromptAnswer)?) -> CommandResult,
}

--// Dispatcher

export type EvaluateRequest = { Text: string, Executor: Player?, Options: RunOptions? }

export type RunRequest = {
	Text: string,
	Executor: Player?,
	Options: RunOptions?,
	Token: CancelToken?,
	--- Input piped into the first command (used by the server when a client pipes a held value).
	Piped: PipedInput?,
	--- Receives every output block as it is produced.
	OnBlock: ((block: Block) -> ())?,
	--- Receives prompts raised by commands (`ctx:Prompt`).
	OnPrompt: ((prompt: PromptRequest) -> PromptAnswer)?,
	--- Called when each command starts (for UI echo/progress).
	OnCommand: ((name: string, text: string) -> ())?,
}

export type Dispatcher = {
	--- Parses and validates without executing. Never yields.
	read Evaluate: (self: Dispatcher, request: EvaluateRequest) -> EvaluateResult,
	--- Executes a full input script. Yields until finished.
	read Run: (self: Dispatcher, request: RunRequest) -> RunResult,
	_cooldowns: { [string]: number },
	_rateBuckets: { [string]: { Tokens: number, Updated: number } },
	_handle: ShellHandle,
}

--// Evaluation output (live validation)

export type ResolvedArg = {
	read Arg: BoundArg,
	read Present: boolean,
	read Ok: boolean,
	read Value: unknown,
	read Display: string?,
	read Error: string?,
	read Span: Span?,
	--- Text supplied for this argument (after unquoting), if any.
	read Text: string?,
	--- True when the value depends on an embedded command or result reference (unknown until run).
	read Deferred: boolean,
	--- The concrete type used (differs from the spec type for dynamic arguments).
	read Type: Type<unknown>?,
}

export type EvaluatedCommand = {
	read Command: Command?,
	read Name: string,
	read Span: Span,
	read NameSpan: Span,
	read Args: { read ResolvedArg },
	read Diagnostics: { read Diagnostic },
	read Ok: boolean,
}

export type EvaluateResult = {
	read Ok: boolean,
	read Commands: { read EvaluatedCommand },
	read Diagnostics: { read Diagnostic },
}

return table.freeze({})
