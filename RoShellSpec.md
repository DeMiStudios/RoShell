# Cmdr 2 — Implementation Specification

> **Audience:** Claude Opus 5.5 (implementing agent).
> **Reference implementation to study first:** https://github.com/evaera/cmdr (v1.12.0, MIT). Read its source (`Cmdr/` folder: `Registry`, `Dispatcher`, `Command`, `Argument`, `Util`, `BuiltInTypes`, `BuiltInCommands`, `BuiltInHooks`, `CmdrClient/CmdrInterface`) before writing anything. Do **not** rely on memory of its API; verify against the source.
> **Working name:** `Cmdr2` (placeholder; keep it in one constant so it can be renamed).

---

## 0. How to use this document

1. Read the whole spec before coding.
2. Build in the milestone order in §17. Each milestone must be fully type-checked and tested before starting the next.
3. Where this spec says **MUST**, it is a hard requirement. **SHOULD** is strongly preferred. **MAY** is optional polish.
4. Where a requirement depends on Luau type-system capabilities (generics, type functions, the new type solver), **verify with `luau-analyze --mode strict` that it actually works** and pick the best working approach. If something cannot be expressed, say so in `DESIGN_NOTES.md` and use the documented fallback. Never silence the analyzer with `any` or `:: any` casts to make it pass.
5. Do not ask clarifying questions unless truly blocked. Make a decision, record it in `DESIGN_NOTES.md`, move on.

---

## 1. Vision and goals

Cmdr v1 is a solid, extensible command console, but:

- Defining custom types is **verbose** (hand-written `Transform`/`Validate`/`Autocomplete`/`Parse` tables, string-based registration, helper functions hidden in `Util`).
- Command definitions are **stringly typed** — argument types are strings, and `Run` receives untyped positional arguments.
- The command bar's autocomplete is **prefix-only**, with limited wildcard behavior and little feedback while typing.
- The UI is functional but dated.
- Commands are dynamically replicated to the client by the cloning of modules, but it might be cleaner to just require the command definitions to be in ReplicatedStorage to avoid this behavior. Dynamic requiring and cloning of scripts is awkward and does not play well with the import system or type system.

**Cmdr 2 goals**

| # | Goal |
|---|------|
| G1 | **Fully typed.** `--!strict` everywhere, zero `any` in the public API. Command `Run` functions get typed arguments with autocomplete in Studio's script editor. |
| G2 | **Easy custom types.** Common types are one-liners. A complex type is ≤ 15 lines. The framework derives parse/validate/autocomplete/fuzzy search from a minimal definition. |
| G3 | **Powerful input language.** Wildcards, globs, set arithmetic, ranges, named flags, embedded commands, pipes, chaining, variables, comments. |
| G4 | **Excellent command bar UX.** Tab completion, fuzzy search, ghost text, live validation, signature hints, resolution preview, history search. |
| G5 | **Modern, polished UI.** Design-token based, animated, themeable, mobile/gamepad friendly, accessible. |
| G6 | **Efficient.** Per-keystroke work stays well under 1 ms for typical registries, no per-keystroke garbage in hot paths, virtualized suggestion list. |
| G7 | **Secure by default.** Client and server validate independently, default-deny permissions, rate limits, payload caps. |
| G8 | **Backwards compatible is unimportant.** The design and implementation should be flexible, if supporting backwards compatibility poses constraints or increases complexity, don't do it. |

**Non-goals:** a Studio plugin, a web UI, or a scripting language with control flow. (Keep §14 "Extensions" optional.)

---

## 2. Code conventions (MUST follow everywhere)

Example:
```luau
--!strict
--// Services
const ReplicatedStorage = game:GetService("ReplicatedStorage")

--// Imports
const Signal = require(ReplicatedStorage.Packages.Signal)

--// Types
export type MyType = {
	_id: number,
	Name: string,
}

--// Constants
const MAX_NAME_LENGTH = 63

--// Globals
const objInstanceCache: { [string]: MyType? } = {}
local objInstanceCacheSize = 0

--- Returns an existing MyType by name, or creates one if it doesn't exist.
const function getObjInstanceByName(name: string): MyType
	const inst = objInstanceCache[name]
	if inst ~= nil then
		return inst
	end

	assert(#name <= MAX_NAME_LENGTH, "name too long")

	const newInst: MyType = {
		_id = math.random(1e9 - 1),
		Name = name,
	}
	objInstanceCacheSize += 1
	objInstanceCache[name] = newInst
	return newInst
end

--// My Type Utility
const MyTypeUtil = {}

MyTypeUtil.MaxNameLength = MAX_NAME_LENGTH

function MyTypeUtil.GetOrCreate(name: string): MyType
	return getObjInstanceByName(name)
end

function MyTypeUtil.GetCount(): number
	return objInstanceCacheSize
end

return table.freeze(MyTypeUtil) -- makes all top-level fields read-only both in the type system and at runtime
```

These are the author's house style. Apply them consistently:
- Every file starts with `--!strict`.
- Use `const` for every binding that is never reassigned (locals, functions, tables). Use `local` only when reassigned.
- **camelCase** for local/const functions and variables (`const function parseToken() end`, `const myVaraible = 0`), PascalCase for classes (`const MyClass`), including "static classes" like utility modujles (`const NumberUtil`), and public object fields (methods, properties), camelCase preceeded with underscore for internal methods and fields (`tbl._privateVaraible`, `function tbl:_privateMethod() end`), `SCREAMING_SNAKE_CASE` for global-scoped constants (`const MAX_SIZE = 100`).
- **Class pattern:** `setmetatable` + `table.freeze` on the metatable/class table; instances typed via an exported `type`. No inheritance chains; compose.
- **Section comment headers** to separate and organize the codebase (see Example above).
- No `any`, no `:: any`, no `--!nocheck`, no `--!nonstrict`. `unknown` is allowed only at trust boundaries (network input, user text) and must be narrowed immediately.
- Public modules export their types (`export type`).
- Zero analyzer warnings. Format with StyLua, lint with Selene (configs provided in the repo; keep them). There are some cases of false-positives due to Luau limitations, and mis-formats with StyLua when specifying generic arguments.
- No global state. Everything hangs off a `Cmdr` instance, so multiple instances can coexist (needed for testing).

---

## 3. Architecture and layout

```
Cmdr2/
├─ init.luau                      -- Public entry: Cmdr.Server / Cmdr.Client
├─ Shared/
│  ├─ Types.luau                  -- All exported public types
│  ├─ Registry.luau               -- Commands, types, hooks, groups, env
│  ├─ Command.luau                -- Command definition builder + validation
│  ├─ TypeBuilder.luau            -- Cmdr.Type.* constructors (the easy-type DSL)
│  ├─ BuiltInTypes/               -- One file per built-in type family
│  ├─ Lexer.luau                  -- Text -> tokens (with spans)
│  ├─ Parser.luau                 -- Tokens -> AST (with error recovery)
│  ├─ Resolver.luau               -- AST -> typed values (runs type Parse)
│  ├─ Fuzzy.luau                  -- Fuzzy scorer + highlight ranges
│  ├─ Completion.luau             -- Context-aware completion engine
│  ├─ Dispatcher.luau             -- Evaluate / Run, pipes, chaining, embedding
│  ├─ Context.luau                -- CommandContext (Reply, Prompt, Progress...)
│  ├─ Permissions.luau            -- Groups / roles / predicates
│  ├─ Net.luau                    -- Remote layer, schema, rate limiting
│  ├─ Result.luau                 -- Result<T, E> helpers
│  └─ Util.luau                   -- Small typed helpers
├─ Server/
│  ├─ init.luau
│  ├─ Hooks.luau
│  └─ Audit.luau                  -- Audit log sink interface
├─ Client/
│  ├─ init.luau
│  ├─ Input/                      -- Keyboard, gamepad, touch handling
│  ├─ UI/
│  │  ├─ Theme.luau               -- Design tokens + presets
│  │  ├─ Components/              -- Window, Bar, SuggestionList, LogView, Toast, Chip...
│  │  ├─ Animator.luau            -- Spring/tween helpers
│  │  └─ Virtualizer.luau         -- Virtualized list
│  └─ State.luau                  -- Reactive UI state (single store)
├─ Commands/                      -- Built-in commands (typed)
├─ tests/                         -- Unit + property + benchmark tests
├─ docs/                          -- Moonwave or Markdown docs
└─ DESIGN_NOTES.md
```

Layering rules: `Shared` never requires `Client` or `Server`. UI never touches parsing internals directly; it consumes `Completion` and `Resolver` results through a small typed interface. All rendering is data-driven off `State`.

---

## 4. The type system (the heart of the rewrite)

### 4.1 Problem with v1

Defining one custom type in v1 means a registration function, string name, and a table of 3–5 callbacks that must agree on intermediate representations (`Transform` → text-ish, `Validate` → bool, `Autocomplete` → strings, `Parse` → final value). Most types are just "pick from a list of known things and map the text to a value".

### 4.2 `Cmdr.Type<T>`

```lua
export type Type<T> = {
	Name: string,
	Description: string?,
	Parse: (request: ParseRequest) -> ParseResult<T>,
	Complete: ((request: CompleteRequest) -> {Suggestion})?,
	Default: ((ctx: CommandContext) -> T?)?,
	Listable: boolean,          -- accepts "a,b,c" -> {T}
	Operators: {Operator<T>}?,  -- type-specific operators (e.g. "*" for players)
	Format: ((value: T) -> string)?,   -- value -> display string (for previews/errors)
	Icon: string?,              -- token for UI badge
	Color: string?,             -- theme token name for UI badge
}
```

`ParseResult<T>` is a discriminated union:

```lua
export type ParseResult<T> =
	{ Ok: true, Value: T }
	| { Ok: false, Error: string, Span: Span? }   -- Span lets the UI underline the bad part
```

Full control (`Parse`/`Complete`) MUST remain available. The easy constructors below build on it.

### 4.3 Easy type constructors (`Cmdr.Type.*`)

Every constructor returns a `Type<T>` with parse, completion, fuzzy matching, formatting, and error messages **derived automatically**.

```lua
-- Enum of string choices -> string literal union
const Rarity = Cmdr.Type.Choice({
	Name = "Rarity", -- may need `:: "Rarity"`, uncertain
	Choices = {"Common", "Rare", "Epic", "Legendary"} :: {"Common"|"Rare"|"Epic"|"Legendary"},
})

-- Key/label -> value map, with aliases and descriptions
const Difficulty = Cmdr.Type.Map({
	Name = "difficulty",
	Entries = {
		easy   = { Value = 1, Aliases = {"e"}, Description = "Forgiving enemies" },
		normal = { Value = 2 },
		hard   = { Value = 3, Aliases = {"h"} },
	},
})  -- Type<number>

-- Resolve from a dynamic list (inventory items, shop items, levels...)
const ItemType = Cmdr.Type.Dynamic({
	Name = "item",
	Candidates = function(ctx): {Candidate<ItemDef>}
		return GetAllItems()  -- {{ Key = "sword", Value = swordDef, Description = "..." }}
	end,
	CacheSeconds = 5,         -- optional; framework caches + invalidates
})

-- Derive from a Roblox Enum
const MaterialType = Cmdr.Type.FromEnum({ Name = "material", Enum = Enum.Material })

-- Numbers with constraints
const Percent  = Cmdr.Type.Number({ Name = "percent", Min = 0, Max = 100 })
const Count    = Cmdr.Type.Integer({ Name = "count", Min = 1, Max = 999 })

-- String shapes
const Hex      = Cmdr.Type.Pattern({ Name = "hex", Pattern = "^#?%x%x%x%x%x%x$", Transform = ParseHex })

-- Composition
const MaybeInt = Cmdr.Type.Optional(Count)                 -- Type<number?>
const Many     = Cmdr.Type.List(ItemType)                  -- Type<{ItemDef}>
const Either   = Cmdr.Type.Union({ Name = "target", Members = {PlayerType, ItemType} }) -- tagged
const Pair     = Cmdr.Type.Tuple({ Members = {Count, ItemType} })   -- "5 sword" -> {number, ItemDef}
const Record   = Cmdr.Type.Struct({ Fields = { x = Number, y = Number } })  -- "x=1,y=2"
const Mapped   = Cmdr.Type.Transform({ From = Count, To = function(n: number): string return string.rep("!", n) end })
```

**Requirements**

- A custom `Choice` or `Dynamic` type SHOULD be definable in **≤ 6 lines** (as shown above).
- A fully custom type with its own `Parse` and `Complete` SHOULD be ≤ 15 lines.
- Registration is **by value, not by string**: types are first-class values you pass into command args. A string-name registry remains for the command bar (type names shown in help/errors) if needed.
- Types are composable and must preserve `T` through every combinator (`Optional`, `List`, `Union`, `Transform`).
- Union parsing is deterministic: try members in declared order, collect all errors, report the best (furthest-progress) one.
- Every built-in constructor generates **helpful error messages with suggestions** ("Unknown item 'swrod'. Did you mean 'sword'?" — use the fuzzy engine).

### 4.4 Built-in types (parity with v1 + more)

Parity (MUST): `string`, `number`, `integer`, `boolean`, `player`, `players`, `playerId`, `team`, `teams`, `teamPlayers`, `command`, `commands`, `duration`, `color3`, `brickColor`, `vector3`, `vector2`, `storedKey`, `userId`, plus plural/listable variants and `url`.

New (SHOULD): `duration` (`1h30m`, `90s`, `2d`), `percent`, `range` (`1..10`), `regex`, `instance` (path-based: `workspace.Map.Door` and `workspace["New Map"].Door`, with completion walking children), `instancePath`, `class` (ClassName filter), `material`, `keycode`, `timestamp`/`datetime` (`in 5m`, `tomorrow`), `colorHex`, `json`, `enum:<Name>` (generic), `asset` (rbxassetid), `remote`, `tag` (CollectionService), `attribute`.

### 4.5 Fully typed commands

```lua
const Give = Cmdr.Command({
	Name = "give",
	Aliases = {"grant"},
	Description = "Give items to players",
	Group = "Admin",
	Args = {
		Cmdr.Arg({ Name = "targets", Type = Cmdr.Types.Players,  Description = "Who receives the item" }),
		Cmdr.Arg({ Name = "item",    Type = ItemType }),
		Cmdr.Arg({ Name = "amount",  Type = Count, Default = 1 }),   -- default => non-optional in Run's type
	},
	Run = function(ctx, args)
		-- args: { targets: {Player}, item: ItemDef, amount: number }
		for _, player in args.targets do
			Inventory.Give({ Player = player, Item = args.item, Amount = args.amount })
		end
		return ctx:Success("Gave %d× %s to %d players":format(args.amount, args.item.Name, #args.targets))
	end,
})
```

**Typing requirement (G1):** `args` MUST have a precise record type inferred from `Args`. Preferred strategy, in order:

1. **Type functions** (new Luau solver): compute `args` record from the `Args` tuple.
2. **Generic builder chain** if type functions are unavailable or unreliable:
   ```lua
   Cmdr.Command("give")
       :Arg("targets", Types.Players)
       :Arg("item", ItemType)
       :Arg("amount", Count, { Default = 1 })
       :Run(function(ctx, args) ... end)
   ```
   where each `:Arg` returns a builder whose generic parameter accumulates the record (`Builder<{targets: {Player}}>` → `Builder<{targets: {Player}, item: ItemDef}>`). Cap the supported arity (e.g. 12) with overloads if needed.
3. **Explicit generic** `Cmdr.Command<{targets: {Player}, item: ItemDef, amount: number}>({...})` with arg names/types cross-checked at definition time.

Pick the one that works under `luau-analyze --mode strict` with the best ergonomics and document it. A wrong/untyped `args` is a failure of the primary goal.

**Argument features (MUST):**
- Positional **and named** arguments: `give Bob sword 5` ≡ `give targets=Bob item=sword amount=5` ≡ `give Bob --amount 5 --item sword`.
- `Optional`, `Default` (static or `(ctx) -> T`), `Description`, `Examples`, `Hidden`.
- **Variadic/rest** arguments (`...items`).
- **Flags/switches**: `--silent`, `-s` (boolean), `--reason "text"`. Short flag clustering (`-sf`).
- **Dynamic args**: an argument whose type depends on previous values (e.g. `set <property> <value>` where `value` type depends on `property`). Provide `ArgFn: (ctx, previous) -> Arg`.
- **Subcommands**: `Cmdr.Command` can have `Subcommands`, each with own args; completion handles `team add|remove|list`.
- **Validation hooks** per-arg (`Validate: (value, ctx) -> Result`).
- **Cross-arg validation** (`Validate` at command level).

**Command features (MUST):**
`Name`, `Aliases`, `Description`, `Details` (long help), `Group`, `Examples`, `Hidden`, `Deprecated` (with replacement), `Run` (server), `ClientRun` (client), `Data` (client→server payload collector, async), `AutoExec`, `Hooks` (`BeforeRun`/`AfterRun`/`OnError`), `Permissions`, `Cooldown`, `RateLimit`, `Timeout`, `Async` (long-running with cancellation/progress), `Undo`.

`Run` return type is typed: `string | Result<unknown, string> | CommandReply | nil`. Return values participate in piping (§6).

### 4.6 Context (`CommandContext`)

Typed API: `ctx.Executor`, `ctx.Command`, `ctx.RawText`, `ctx.Args` (typed), `ctx.IsClient`, `ctx:Reply(text, kind)`, `ctx:Success/Info/Warn/Error`, `ctx:Table(rows)`, `ctx:Prompt({...})` (confirm / choice / text input, rendered natively by the UI, awaits response), `ctx:Progress({ Label, Fraction })`, `ctx:Cancelled()`, `ctx:GetStore(name)`, `ctx:GetData()`, `ctx:Broadcast(...)`, `ctx:Log(...)`, `ctx:Undoable({ Do, Undo })`. Everything fully typed; no stringly-keyed bags.

---

## 5. Input language

### 5.1 Grammar (formalize in `docs/GRAMMAR.md` and implement in `Lexer`/`Parser`)

- Tokens separated by whitespace; **quotes** `"..."` and `'...'`, with escapes (`\"`, `\\`, `\n`, `\u{...}`), plus raw triple-quote `"""..."""`.
- Comments: `# until end of line` (when not inside quotes) — for scripts and macros.
- **Chaining:** `a && b` (run b if a succeeds), `a || b` (run b if a fails), `a ; b` (always). *Note: v1 used `||` for piping; but compat isn't important.*
- **Piping:** `a | b` passes `a`'s result into `b`'s designated pipe argument (§6).
- **Embedded commands:** `${cmd args}` evaluated first, result substituted (nestable). Determine if v1's `${{ cmd }}` behavior is preferred if it simplifies parsing.
- **Variables:** `$name` (stored value), `$$` (last result), `$1..$9` (macro/alias parameters), `$@` (all params), `$me`, `$here`, `$random(1,10)` (built-in functions, extensible).
- **Multi-line** input and scripts (newline = `;`).
- **Lexer MUST produce spans** for every token (start/end indices) — used for syntax highlighting, error underlines, and completion context.
- **Parser MUST recover from errors**: unterminated quote, unmatched `${`, trailing operator. It returns a best-effort AST plus diagnostics, so the UI can highlight/complete partial input.

### 5.2 Operators and wildcards (for list-ish types like players/teams/items)

All operators work on any type that opts into them via `Type.Operators`. Defaults provided for players, teams, instances, and `Dynamic` types.

| Syntax | Meaning |
|---|---|
| `*` | all |
| `**` | all except executor |
| `.` | executor; also `@me` / `me` |
| `?` | random one (only when alone). `?3` random three |
| `Bo*`, `*ob`, `*o*` | **glob** match (`*` any run, `?` only inside a larger pattern = one char) |
| `[ab]*`, `[a-m]*` | character classes |
| `~bob` | **fuzzy** match (ranked, top-N configurable, default 1 for scalar args, all-above-threshold for listable) |
| `/pattern/` | Luau pattern (opt-in per type) |
| `%Team` | team |
| `!tag`, `#tag` | CollectionService tag / custom attribute selector |
| `@role:Admin` | custom selectors via registry (`Selector` extension point) |
| `A,B,C` | list |
| `A+B`, `A-B`, `A&B` | **set union / difference / intersection** (`*-Bob`, `%Red&%Admins`) |
| `1..10`, `..5`, `5..`, `1..10/2` | numeric ranges (+ step) for numeric types and iteration |
| `!X` | negate: everything except `X` |

Rules:
- Operators are defined declaratively: `{ Symbol, Parse, Resolve, Description, Example }` so the help system and completion can **list them** when the user types `*`/`%`/`@`.
- Resolution is **lazy** and **deterministic** (stable ordering) except where randomness is the point.
- A wildcard that matches nothing returns a clear error (or empty list if the arg declares `AllowEmpty`).
- **Dry-run / preview** (see §7.5): the UI shows what a wildcard resolves to before executing.
- **Safety:** commands can mark args `RequireConfirmAbove = N` — if a wildcard resolves to more than N targets, the framework auto-prompts confirmation.

### 5.3 Named arguments and flags

```
give Bob sword 5
give --targets Bob --item sword --amount 5
give Bob sword -n 5 --silent
tp Bob to=Alice   # key=value form
```
Completion MUST suggest unused flag names after `-`/`--`, and the correct value type after a flag.

---

## 6. Dispatcher: pipes, results, chaining

- `Dispatcher.Evaluate({ Text, Executor, Options })` → `Result<ParsedCommand, ParseDiagnostics>` (no execution; used by live validation).
- `Dispatcher.Run({ Text, Executor, Options })` → async `Result<RunOutput, string>`.
- **Piping:** a command may declare `Pipe = { Arg = "targets" }` to receive piped values, and `Returns = Type<T>` to declare its output type. `players Team=Red | kick` works because `players` returns `{Player}` and `kick` pipes into `targets`. Piping MUST be type-checked at parse time (error if the output type is not assignable to the pipe arg type).
- `Run` can return structured values (`{Player}`, table rows, numbers) that the UI renders as tables/chips, not just strings.
- **Cancellation tokens** on async commands; `ESC` or `Ctrl+C` in the UI cancels the running command.
- **Timeouts** per command and globally; errors are caught (`pcall`/`xpcall` with traceback) and surfaced without killing the dispatcher.
- Execution is **non-yielding to the UI**: long commands must not freeze input.

---

## 7. Command bar UX (frontend input behavior)

This is a headline feature. Implement in `Completion.luau` (logic) and `Client/UI` (rendering).

### 7.1 Completion engine

`Completion.Query({ Text, Cursor, Executor, Options })` → `CompletionResult`:

```lua
export type CompletionResult = {
	Context: "Command" | "Subcommand" | "Argument" | "Flag" | "FlagValue" | "Operator" | "Variable" | "Embedded",
	ActiveArg: number?,
	Replace: Span,                 -- the range that accepting a suggestion replaces
	Suggestions: {Suggestion},
	Signature: SignatureHint?,     -- for the signature bar
	Diagnostics: {Diagnostic},     -- errors/warnings with spans
	Preview: ResolutionPreview?,   -- what the current wildcard/arg resolves to
}

export type Suggestion = {
	Text: string,            -- inserted text (quoted/escaped automatically as needed)
	Display: string,         -- label shown
	Detail: string?,         -- right-aligned secondary text (type, description)
	Kind: string,            -- "command" | "alias" | "player" | "item" | "operator" | "flag" | "history" ...
	Score: number,
	MatchRanges: {Span},     -- for highlight rendering
	Icon: string?,
	Deprecated: boolean?,
	Insert: { Text: string, Cursor: number }?,  -- snippet-style insertion
}
```

- Works with **cursor in the middle** of the text, not just at the end.
- Works inside quotes, inside `${ }`, after pipes/chains.
- Completion for each type pulls from `Type.Complete`; `Dynamic`/`Choice` get it for free.
- Async candidates: completion MUST NOT block. Candidate providers can be async with a per-query budget (default 8 ms); results stream in and the list updates. Stale queries are cancelled by sequence number.
- **Frecency + history ranking**: previously chosen suggestions for this command/arg rank higher (persisted via an optional storage adapter).

### 7.2 Fuzzy search (`Fuzzy.luau`)

- fzf/fzy-style subsequence scoring, with bonuses for: consecutive matches, word boundaries (`_`, `-`, space, camelCase transitions), prefix matches, case-exact matches, and shorter candidates; penalties for gaps.
- Returns **match positions** for highlight.
- Multi-term queries (`red sw` matches "Red Sword") — space-separated terms all must match, in any order.
- Smart case (case-insensitive unless the query contains uppercase).
- Handles Unicode safely (use `utf8` library; don't break on multibyte).
- **Performance:** precompute lowercase/boundary data per candidate once, cache on the candidate record. Target: 10 000 candidates scored in < 4 ms, with early-out when a match is impossible. Use a pre-filter bitmask of character presence.
- Top-K selection with a heap or partial sort — never fully sort 10 000 items for 8 visible rows.
- Pure module with property tests (score monotonicity, match ranges valid, idempotence).

### 7.3 Tab, arrows, and keys

| Key | Behavior |
|---|---|
| `Tab` | Accept highlighted suggestion (or the top one if none highlighted). If multiple suggestions share a longer common prefix, first complete to that common prefix; a second `Tab` cycles. |
| `Shift+Tab` | Cycle backwards |
| `→` / `End` (at end of text) | Accept **ghost text** (inline faded completion of the top suggestion) |
| `↑` / `↓` | Move through suggestion list when open; otherwise history navigation |
| `Ctrl+Space` | Force-open suggestions |
| `Esc` | Close suggestions → clear input → close console (progressive) |
| `Enter` | Run. If suggestion list is open **and** highlighted by explicit navigation, accept first, then (on second Enter) run |
| `Ctrl+R` | Reverse fuzzy history search overlay |
| `Ctrl+L` | Clear log |
| `Ctrl+W` / `Alt+Backspace` | Delete previous word |
| `Ctrl+←/→` | Word jump |
| `Ctrl+Z` / `Ctrl+Shift+Z` | Undo/redo **input text** |
| `Ctrl+C` while running | Cancel command |
| `Ctrl+K` | Open command palette (searchable list of every command) |
| `F1` or `?` on empty | Contextual help for the active command/arg |

All bindings are remappable through the typed `Options.Keymap` table. Roblox text input constraints (`TextBox` swallows some keys) MUST be handled and documented; `Tab` must not insert a tab character or shift focus.

### 7.4 Live feedback while typing

- **Syntax highlighting** in the bar (RichText overlay or a mirrored `TextLabel` behind a transparent `TextBox`): command name, argument values colored by type, operators, flags, strings, variables, errors.
- **Inline validation:** invalid tokens get an error underline/color; hovering/selecting shows the message. The Enter key is visually "armed" (accent) when valid and "disabled" when invalid.
- **Signature hint bar** above/below the input: `give  <targets: players>  <item: item>  [amount: count = 1]` with the **active argument highlighted** and its description shown.
- **Resolution preview chip:** while typing `*-Bob` or `~sw`, show `→ 7 players` or `→ Sword of Embers (+2 more)`, expandable to the full list.
- **Ghost text** of the top suggestion, inline.
- Bracket/quote auto-pairing (opt-in) and auto-close of `${`.
- **Paste handling**: multi-line paste runs as a script after confirmation.
- Debounce visual updates to one per frame; compute completion on every change but coalesce.

### 7.5 Dry run & confirmation

- `--dry` (global flag, enabled per command via `SupportsDryRun`) shows what *would* happen. Commands implement `Preview(ctx, args) -> {PreviewLine}`.
- Destructive commands (`Destructive = true`) always prompt confirm unless `--yes`.

---

## 8. Permissions and security

- **Default deny.** A command with no `Permissions`/`Group` mapping is not runnable by non-privileged users. Provide `Cmdr.Permissions.Allow({ ... })`.
- Permission models (composable, typed): `Everyone`, `Users = {userId}`, `Ranks = {groupId, minRank}`, `Gamepass/Badge`, `Role = "Moderator"` (role → permission set), `Predicate = (player, command, args) -> boolean`, `Studio = true`.
- Permission checks run on **server before parsing args** (to avoid leaking autocomplete data) and again **before run**, with parsed args available to predicates.
- **Autocomplete privacy:** completion/candidate data (player names, item names) is only sent to clients allowed to run the command; the server may restrict `Complete` data per-executor.
- **Network layer** (`Net.luau`):
  - Single RemoteFunction + RemoteEvent, versioned handshake, per-player rate limit (token bucket), max payload sizes, max command length, strict schema validation of every field at the boundary (`unknown` → narrowed).
  - Server **never trusts client-parsed values**; it re-parses raw text. (v1 behavior; keep it.)
  - Commands' metadata replicates lazily and only for commands the player may see.
  - Client-only commands (`ClientRun` without `Run`) never touch the network.
- **Audit log:** every server-run command emits `{ Time, Executor, Raw, Command, Args (formatted), Result, Duration }` to a pluggable `AuditSink` interface (default: in-memory ring buffer + `print` in Studio). Provide a DataStore/HTTP sink example.
- **Cooldowns & rate limits** per command, per player, per group.
- No `loadstring`, no use of `getfenv`/`setfenv`; no dynamic `require` of arbitrary IDs.

---

## 9. Additional features (beyond v1)

Group by priority; implement P0 and P1, P2 as time allows.

**P0 — core**
1. Everything in §4–§8.
2. **Rich built-in help**: `help`, `help <command>`, `help <type>`, `help operators`. Shows signature, description, args with types, examples, aliases, group, permissions needed (only if the user can see them), and **suggests similar commands** on unknown command ("Did you mean `give`?").
3. **Command palette** (`Ctrl+K`) with fuzzy search over commands + aliases + descriptions.
4. **History**: persisted, deduped, fuzzy-searchable, per-session and cross-session (via storage adapter; default memory).
5. **Aliases & macros**: `alias hello = "say Hello $1"`, with `$1..$9`, `$@`, persisted per user via storage adapter. Typed validation of alias bodies at creation.
6. **Keybinds**: `bind <key> <command>` with modifiers, gamepad buttons, persisted. `unbind`, `binds`.
7. **Stored values / variables**: `set`, `get`, `unset`, `$name`.
8. **Result rendering**: tables, lists, key/value blocks, progress, links, color chips — not only strings.
9. Hot-reload of commands/types (Studio-friendly; `Registry.Unregister` and re-register).

**P1 — power**
10. **Subcommands** (§4.5) and **flag parsing**.
11. **Undo/redo of commands** (`undo`, `redo`) for commands that implement `Undo` (stack per executor, bounded).
12. **Scheduling & repetition**: `in 5m <cmd>`, `every 30s <cmd>`, `repeat 5 <cmd>`, `schedules`, `cancel <id>` (server-side, permissioned, cleaned up on leave).
13. **Scripts**: multi-line command files (ModuleScript returning strings, or `StringValue`) with `run-script <name>`, comments, variables, `&&`/`||`.
14. **Cross-server broadcast** (`MessagingService`): `Cmdr.Net.Broadcast`, e.g. `announce`, `shutdown-all`, `kick-everywhere`. Typed message schema.
15. **Command middleware** (typed): wrap around execution for logging, metrics, auth, caching.
16. **Typed Settings registry** (`config set <key> <value>`, type-driven from a settings schema; completion for keys and values).
17. **Instance path type** with live completion that walks the DataModel (`workspace.Map.<tab>`), and an `inspect` command for properties/attributes with typed set.
18. **Localization hooks**: all built-in strings routed through `Cmdr.Locale` with overridable tables.
19. **Test harness**: `Cmdr.Test.Run({ Text, As = fakePlayer })` returns result without UI/network — makes user commands unit-testable.
20. **Plugin system**: bundles of commands + types + hooks + theme registered as a unit (`Cmdr.Plugin({ Name, Commands, Types, Hooks, Selectors, Theme })`).

**P2 — nice to have**
21. **Output channels / tabs** in the UI (All, Errors, Admin chat, Audit) with filters and search in log.
22. **Log persistence & export** (copy to clipboard-able text; `export-log`).
23. **Telemetry hooks** (command usage counts, error rates, p95 latency) via a pluggable sink.
24. **Command suggestions based on usage** ("you often run X after Y" chip).
25. **Schema export**: `Cmdr.Docs.Generate()` emits Markdown/JSON reference of all registered commands and types (for a wiki).
26. **Luau type stub generation** for dynamic commands, optional.
27. **Studio command bar integration** *(only if feasible)*: a thin plugin bridging the same registry in edit mode.

---

## 10. UI / visual design spec

Goal: feels like a modern IDE command palette (think Raycast / VS Code palette / Linear's Cmd-K), not a legacy debug console. Everything built from code (no pre-authored Instance trees required), data-driven from `State`, themeable via tokens.

### 10.1 Layout

```
┌───────────────────────────────────────────────────────────────────────┐
│  ◉ Output                                         ⌕  ⚙  ⎘  ✕         │  ← title bar (draggable, optional)
├───────────────────────────────────────────────────────────────────────┤
│  ✓ Gave 5× Sword of Embers to 3 players                       0.8 s  │  ← log rows (virtualized,
│  ℹ Teleported Bob → Alice                                             │     level-colored accent bar,
│  ⚠ Item 'x' is deprecated, use 'y'                                    │     timestamps on hover)
│  ✕ Unknown player 'Bobb'. Did you mean 'Bob'?                         │
│  ▸ players Team=Red                                                   │  ← echo of executed commands
│    ┌ Name ──── Team ──── Rank ┐                                       │  ← structured table output
│    │ Bob       Red      Admin │                                       │
├───────────────────────────────────────────────────────────────────────┤
│ give  <targets: players>  <item: item>  [amount: count = 1]          │  ← signature hint (active arg bold)
│ ┌───────────────────────────────────────────────────────────────────┐ │
│ │ ❯ give *-Bob sw█ordOfEmbers                      → 7 players  ⏎  │ │  ← input w/ syntax highlight,
│ └───────────────────────────────────────────────────────────────────┘ │     ghost text, preview chip
│ ┌ item ─────────────────────────────────────────────────────────────┐ │
│ │ ◆ [Sw]ord of [E]mbers          item · legendary          ↹      │ │  ← suggestion list
│ │ ◆ [S]hado[w] [S]word           item · epic                       │ │     (fuzzy highlights,
│ │ ◆ [Sw]ift [Ex]ecutioner        item · rare                       │ │      kind icon, detail col)
│ └───────────────────────────────────────────────────────────────────┘ │
└───────────────────────────────────────────────────────────────────────┘
```

Modes:
- **Console mode** (default): docked top (full width, 40% height max) *or* floating centered palette.
- **Palette mode** (`Ctrl+K`): centered, compact, only input + results.
- **Mobile mode**: bottom-anchored sheet above the on-screen keyboard; larger touch targets (≥ 44 px), swipe to dismiss, tap-to-accept suggestions, horizontal chip row for quick suggestions.
- **Gamepad mode**: D-pad selects suggestions, face buttons accept/run, on-screen keyboard supported.

### 10.2 Visual language (design tokens, all in `Theme.luau`)

All styling references tokens; no hard-coded colors/sizes in components.

- **Color tokens (semantic):** `bg.window`, `bg.elevated`, `bg.input`, `bg.hover`, `bg.selected`, `border.subtle`, `border.focus`, `text.primary`, `text.secondary`, `text.muted`, `text.inverse`, `accent.primary`, `accent.hover`, `success`, `warning`, `error`, `info`, plus **syntax tokens**: `syntax.command`, `syntax.arg`, `syntax.number`, `syntax.string`, `syntax.operator`, `syntax.flag`, `syntax.variable`, `syntax.error`, plus **type badge colors** (player, item, number, string, bool, instance, ...).
- **Presets (MUST):** `Midnight` (default dark, deep blue-gray), `Graphite` (neutral dark), `Light`, `HighContrast`. **SHOULD**: `Solarized`, `Mocha`. Custom themes via `Cmdr.Theme.Create({ Base = "Midnight", Overrides = {...} })`.
- **Typography tokens:** font family (default: a clean sans for UI, a monospace for the input/log — choose Roblox fonts available as `Font` objects, e.g. a Builder/Gotham-family sans and `RobotoMono`/`Code`), sizes (`xs 11, sm 12, md 14, lg 16`), weights; consistent line height.
- **Spacing scale:** 2/4/8/12/16/24. **Radius scale:** 4/8/12/16 (window 12, input 10, chips pill). **Elevation:** soft drop shadow (use a 9-slice shadow image *or* layered transparent frames, since Roblox lacks native shadows), 1 px subtle `UIStroke` borders.
- **Effects:** optional background **blur** via `BlurEffect` on `Lighting` (restored on close), subtle gradient on the window (`UIGradient`, low contrast), accent glow on focused input.
- **Iconography:** a small icon set (unicode glyphs or an atlas image) for kinds: command, alias, player, item, flag, operator, history, success/warn/error/info. Provide a fallback to glyphs if images fail to load.
- **Density option:** `Comfortable` / `Compact`.

### 10.3 Motion

All animation via `Animator.luau` (springs preferred, `TweenService` as fallback), **respects `Options.ReduceMotion`**.

- Window open/close: slide + fade (≈ 160 ms ease-out), no layout thrash.
- Suggestion list: height springs to content, rows fade/slide in with 12 ms stagger (cap at 6 rows).
- Selection highlight **slides** between rows (single animated highlight element, not per-row tweens).
- Input focus: border color + soft glow transition.
- Validation state: Enter button color crossfade; error shake (small, 2 cycles) on rejected submit.
- Log: new rows slide up and fade in; toast notifications for background events (scheduled command ran, cancel, etc.).
- No animation may block input or exceed 250 ms for UI responses to typing.

### 10.4 Components (each typed, self-contained, pooled)

`Window`, `TitleBar`, `LogView` (virtualized, supports text/table/list/progress/prompt rows), `InputBar` (TextBox + highlight overlay + ghost text + preview chip), `SignatureBar`, `SuggestionList` (virtualized, keyboard + mouse + touch), `Chip`, `Badge`, `Toast`, `Dialog` (for `ctx:Prompt`), `HistorySearch`, `Palette`, `Tooltip`, `Scrollbar` (thin, auto-hide custom scrollbar), `ResizeHandle`.

Rules:
- **Object pooling** for rows; no per-keystroke `Instance.new` in hot paths.
- **Virtualization** for log and suggestions (render only visible rows + overscan).
- RichText escaping for all user-supplied strings (prevent markup injection from player names/messages).
- `AutomaticSize` is avoided in hot lists (manual layout for performance), allowed in small static components.
- Respect `GuiInset`, safe areas (notches), `ScreenGui.ScreenInsets`, and DPI scaling; text sizes use scale tokens, not fixed pixels.

### 10.5 Accessibility and usability

- Contrast ratios ≥ 4.5:1 for text in all built-in themes (verify programmatically in tests).
- Don't rely on color alone for errors (also icon + text).
- All interactions available by keyboard; focus rings visible.
- Resizable and draggable window, position/size persisted via storage adapter.
- Respect user text size option (`Options.TextScale`).
- Click-away behavior and `HideOnLostFocus` (v1 option) retained.

### 10.6 Opening/closing

Activation keys configurable (default `F2`, plus `` ` ``), plus **mash-to-enable** (v1 feature `MashToEnable`) retained, plus a **touch/gamepad button** (small floating, auto-hiding) that opens the console on those platforms. `Cmdr.Client:Show/Hide/Toggle/SetEnabled`. `Cmdr.Client:SetActivationUnlocksMouse` retained.

---

## 11. Efficiency requirements

- **Registry indexing:** commands, aliases, and type names go in a precomputed index (prefix trie + fuzzy-prep records). Registering N commands is O(N); lookup O(len).
- **Incremental pipeline:** Lexer → Parser → Resolver recompute only from the first changed token (cache previous token array and AST by text-prefix).
- **No garbage in the hot path:** reuse tables (arrays cleared with `table.clear`), avoid string concatenation in loops (use `table.concat`), avoid closures per keystroke.
- **Candidate caching:** `Dynamic` types cache with TTL and explicit `Invalidate()`; players list is event-driven (PlayerAdded/Removing), not polled.
- **Frame budget:** completion/render work for one keystroke ≤ 1 ms median on a mid-range device for ≤ 500 commands and ≤ 200 candidates; ≤ 4 ms p99 for 10 000 candidates (§7.2). Provide `tests/benchmarks/` with a harness that reports these numbers.
- **Network:** completion data requested lazily, batched, and cached client-side with versioning; no per-keystroke RemoteFunction calls (use client-side candidate lists where possible, server round-trip only for server-only data, debounced ≥ 120 ms, cancel stale).
- Use `buffer`/`table.create`/`table.freeze` where it measurably helps; justify non-obvious micro-optimizations with a comment and a benchmark.

---

## 12. Compatibility with Cmdr v1

DONT CARE.

---

## 13. Built-in commands (typed, parity + improvements)

Parity (MUST): `help`, `hide`, `bind`, `unbind`, `alias`, `run`, `runif`, `history`, `echo`, `math`, `clear` (`replace`, `get`, `set`, `unset` store ops), `kill`, `kick`, `teleport`, `to`, `bring`, `blink`, `announce`, `uptime`, `version`, `resolve`, `commands` (list), `pipe`/`fn` where meaningful.

New (SHOULD): `palette`, `theme` (list/set/preview), `config`, `schedules`, `undo`, `redo`, `audit`, `inspect`, `tags`, `reload`, `export-log`, `types` (list all types with examples), `operators`.

Each built-in is written with the **new typed API** and is itself the canonical example of idiomatic use.

---

## 14. Extension points (typed)

`Registry.RegisterType`, `RegisterCommand`, `RegisterCommandsIn(folder)` (auto-loads `.luau` modules returning `Command`), `RegisterTypesIn`, `RegisterHooksIn`, `RegisterSelector`, `RegisterFunction` (for `$fn(...)`), `RegisterTheme`, `RegisterOutputRenderer` (custom row type), `RegisterPlugin`, `AddEnv` (typed key/value environment accessible in `ctx`), and storage/audit/telemetry **adapter interfaces** (`StorageAdapter`, `AuditSink`, `TelemetrySink`) with documented default in-memory implementations.

Every extension point has a minimal typed example in `docs/`.

---

## 15. Testing and quality gates

- **Unit tests** (TestEZ or Jest-Lua; pick one, put it in `Wally`/`wally.toml` dev deps): Lexer, Parser (incl. error recovery), Resolver, each built-in type, each operator, set arithmetic, Fuzzy (property tests), Completion (table-driven: `(text, cursor) → expected suggestions/replace span/signature`), Dispatcher (pipes/chains/embedded/cancellation), Permissions, Net schema validation, Theme contrast check.
- **Type tests:** a `tests/types/` folder of files that MUST type-check (positive cases: arg inference works) and a script that confirms specific lines MUST error (negative cases: wrong arg type in `Run`, wrong pipe type). Run via `luau-analyze --mode strict`.
- **Benchmarks:** `tests/benchmarks/` for Fuzzy, Completion, Lexer+Parser incremental, UI list virtualization (where simulable).
- **CI:** GitHub Actions running StyLua check, Selene, `luau-analyze` (strict, zero warnings), tests. Fail on any regression.
- **Definition of done for each milestone:** zero analyzer errors/warnings, tests green, docs updated, example usage in `examples/`.
- Include a **demo place** (`demo.project.json` + `examples/`) showcasing: custom types in ≤ 6 lines, a typed command, wildcards, pipes, the theme switcher, mobile layout.

---

## 16. Documentation deliverables

- `README.md`: pitch, quickstart (server + client in < 15 lines), v1 → v2 migration table.
- `docs/` (Moonwave-compatible doc comments): Guides — *Your first command*, *Custom types in 60 seconds*, *Operators and wildcards*, *Permissions*, *Theming*, *Writing plugins*, *Security model*; API reference generated from doc comments.
- `docs/GRAMMAR.md` (formal input grammar).
- `DESIGN_NOTES.md`: every decision where the spec left latitude or where Luau's type system forced a fallback, with rationale.
- `CHANGELOG.md`.

---

## 17. Milestones (build in this order)

| # | Milestone | Exit criteria |
|---|---|---|
| M0 | **Study + design**: read Cmdr v1 source; write `DESIGN_NOTES.md` with the chosen typing strategy (type functions vs builder vs explicit generic) proven by a small analyzer-checked prototype | Prototype shows `args` fully typed under `--mode strict` |
| M1 | **Core**: `Types`, `Result`, `Registry`, `TypeBuilder` (all easy constructors), `Command`, built-in types | Type tests + unit tests pass |
| M2 | **Language**: `Lexer`, `Parser` (with recovery), `Resolver`, operators/wildcards/set arithmetic, flags/named args | Grammar tests, fuzz tests (random strings never crash the lexer/parser) |
| M3 | **Dispatch + Net + Permissions**: `Dispatcher` (pipes/chains/embedding/cancel), server/client wiring, rate limits, audit | End-to-end test in demo place (Studio) via `Cmdr.Test.Run` and real remotes |
| M4 | **Fuzzy + Completion**: engine, ranking, signature hints, previews, async candidates | Table-driven completion tests + benchmarks meet §11 budgets |
| M5 | **UI**: theme tokens, components, console + palette + mobile + gamepad, animations, virtualization | Visual QA checklist + screenshot set in `docs/`, accessibility contrast tests green |
| M6 | **P0/P1 features** (§9): help, palette, history, alias/macros, binds, undo, schedules, scripts, broadcast, plugins | Each feature has tests + docs |
| M7 | **Hardening + docs + demo + CI** | All quality gates green; README quickstart verified from a clean place |

---

## 18. Acceptance checklist (final review)

- [ ] `luau-analyze --mode strict` clean on the entire tree; **no `any`** in public API (`grep` check in CI).
- [ ] A new `Choice`/`Map`/`Dynamic` custom type is ≤ 6 lines; a fully custom type ≤ 15 lines.
- [ ] `Run` functions receive precisely typed `args`; type-test negatives fail as intended.
- [ ] Tab-completion, ghost text, fuzzy search (with highlight), wildcards (`*`, `**`, globs, `~fuzzy`, `%Team`, set ops, ranges), flags, named args, pipes, chaining, embedded commands all work in the UI and in `Cmdr.Test.Run`.
- [ ] Live validation, signature bar, and resolution preview update as the user types, in the middle of the text and inside quotes/`${}`.
- [ ] Server re-validates everything; default-deny permissions; rate limited; audit log works.
- [ ] UI: 4 theme presets, motion respecting `ReduceMotion`, console/palette/mobile/gamepad modes, virtualized lists, pooled rows, escaped RichText.
- [ ] Performance budgets in §11 verified by benchmark output committed to `docs/BENCHMARKS.md`.
- [ ] Docs, demo place, CI all present.

---

## 19. Appendix — worked examples the implementation must support

**A. Easy custom type + typed command (the "feel" target)**
```lua
--!strict
const Cmdr = require(path.to.Cmdr2)

const Rarity = Cmdr.Type.Choice({
	Name = "rarity",
	Choices = {"common", "rare", "epic", "legendary"},
})

return Cmdr.Command({
	Name = "spawnloot",
	Description = "Spawn loot of a given rarity",
	Group = "Admin",
	Args = {
		Cmdr.Arg({ Name = "rarity", Type = Rarity }),
		Cmdr.Arg({ Name = "count",  Type = Cmdr.Types.Integer, Default = 1 }),
	},
	Run = function(ctx, args)
		SpawnLoot({ Rarity = args.rarity, Count = args.count })   -- rarity: "common"|"rare"|..., count: number
		return ctx:Success("Spawned loot")
	end,
})
```

**B. Input examples that must parse, validate, complete, and resolve**
```
kick *-Bob --reason "AFK"
give ~sw 3 && announce "Loot dropped"
players Team=Red | kick --reason "friendly fire"
tp Bob ${players ? }                 # embedded: random player
heal %Red&%Admins
setspeed Bo* 16..32/8                # glob + stepped range
alias gg = "announce GG $1"
in 5m shutdown --dry
```

**C. Completion table (excerpt of expected tests)**
```
"giv█"                → [give (cmd), grant (alias)]  replace=[0,3]
"give B█"             → [Bob, Bobby, …] ranked fuzzy, with highlights
"give *█"             → operator list: * ** . ? ~ % @ ! …
"give Bob sw█"        → [Sword of Embers, Shadow Sword, …]
"give Bob sword --█"  → [--amount, --silent, --reason]
"kick \"Bo█"          → completion inside quotes, replace span excludes the open quote
"give █ sword" (cursor mid-text) → arg 0 suggestions
```

---

*End of specification.*
