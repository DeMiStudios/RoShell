# Design notes

Decisions where the specification left latitude, where Luau's type system or the engine forced a different route,
and where the implementation deliberately deviates. Each entry gives the reason.

## Typing strategy

**Goal:** `Run(ctx, args)` receives a precisely typed `args` with no annotations, under `--!strict` and the new
solver, without `any`.

- **User-defined type functions compute the types.** `TypeFunctions.ArgsOf<A>` reads the `Args` list type and
  builds the record (`required → T`, `optional → T?`, `rest → { T }`, `flag → boolean`, `dynamic → unknown`).
  `ValueOf<Ty>` reads `T` out of a `Type<T>` (through the return type of `Parse`), `StructOf`, `RecordOf` and
  `UnionOf` do the same for composite types. Alternatives considered: explicit generics on every command
  (verbose, easy to get wrong) and a builder with one generic per argument (type explosion, worse errors).
- **`Args` is a list of single-key tables:** `{ { target = RoShell.Arg(Player) }, … }`. The specification sketches
  `Arg({ Name = "target", Type = … })`, but a `Name = "target"` field is inferred as `string`, not the singleton
  `"target"`, so the record keys could not be computed. A table key *is* part of the type. A list (not a keyed
  table) keeps declaration order, which positional binding needs.
- **The handler is attached with a method: `RoShell.Command({ … }):Run(fn)`.** With `Run` inside the definition
  literal, the solver has to type the handler's parameters while still inferring `A` from the same literal and
  gives up (`args` becomes `unknown`). Inferring `A` from `Command(definition)` first and then checking
  `:Run(handler: Handler<ArgsOf<A>>)` gives the handler a fully known context. `ClientRun`, `Validate`, `Preview`
  and `Data` follow the same pattern.
- **Argument constructors are generic over the type *object*:** `Arg<Ty>(valueType: Ty, …)` with
  `ValueOf<Ty>` for options, rather than `Arg<T>(valueType: Type<T>)`. A `Type<T>` parameter does not drive
  inference when the argument is an intersection (`DynamicType<T> = Type<T> & { Invalidate }`) and loses literal
  unions in some positions; keeping the exact object type and reading `T` with a type function always works.
- **`Type.Choice` takes the union explicitly:** `Choice<<"easy" | "hard">>({ Choices = { "easy", "hard" } })`.
  Luau infers `{ string }` for an array of string literals; without the explicit instantiation the choice type
  would be `string`.
- **`Type.Map` takes a list of entries with a `Key`**, not a keyed table: Luau cannot infer `V` from the values of
  a table literal with string keys, and keyed tables lose their order.
- **Containers carrying a type parameter are read-only** (`read` properties, `{ read T }` arrays). This makes them
  covariant, so `Type<number>` flows into `Type<unknown>` (the registry, `TypeInfo`) without casts.
- **Requests carry a `ShellHandle`, not the `Shell`.** `Type<T>` methods take a request; if requests referenced
  `Shell` (which stores `Type<unknown>`), Luau reports a recursive generic alias with different parameters.
  `ShellDirectory` maps handles back to shells.
- **One documented unsafe boundary.** Values assembled at runtime from a schema whose static type a type function
  computes from the same schema (the `args` record, tuple and struct values) are given their type in
  `Shared/Unsafe.luau` (`FromSchema`, `FromMember`, `Assume`). The invariant (each value was produced by its own
  entry's `Parse` or typed default) is covered by the type tests and the resolver/dispatcher specs. Nothing else
  casts.
- **Identity registries instead of casts.** `unknown` values that are actually ours (a type object loaded from a
  module, a command, a hooks table, a reply) are recognized through weak tables filled by their constructors
  (`TypeBuilder.Lookup`, `Command.Lookup`, `Registry.Hooks`, `Context` replies), which return them with their
  real type.
- **`ctx:Value` is generic over the type object** (`Value<Ty>(valueType: Ty, value: ValueOf<Ty>)`). The first
  version, `Value<T>(Type<T>, T)`, accepted `ctx:Value(Count, "three")`: because `Type<T>` is covariant, `T` was
  inferred as `number | string`. A negative type test now pins this.
- **Defaults may be text.** `Default(Mode, "easy")` failed to type-check: a string literal passed where the
  parameter type is a type-function result is widened to `string` before the check. Accepting the argument's
  *text form* (parsed by the type each run) fixes it and adds a useful feature: `Default(Types.Players, "me")`,
  `Default(Types.Duration, "5m")`.
- **Interfaces are declared as `read` method fields with `self` typed as the interface** (`Types.luau`); classes
  are `setmetatable` objects. Where intersections made `self` contravariance fail (the client transport, memory
  storage, the console API), objects are closure-based records instead.
- **`dynamic` arguments are `unknown`.** Their type is chosen at run time from earlier arguments; the handler
  narrows.

## Tooling

- **Formatter: Larvae, not StyLua.** StyLua 2.5.2 cannot parse explicit generic instantiation (`f<<T>>()`), which
  the typing strategy depends on. Larvae 0.9.0 parses everything in the tree. Quirks found and worked around:
  `typeof({} :: T)` inside a type alias loses the spaces around `::` (cosmetic); the parser rejects nested
  read-only table types in arrays (`{ read { read X: T } }`), so such types are named first; its "hug last
  argument" style formats long first arguments as `:Run(\n function(...)`, which is accepted as is.
- **Type checking uses `luau-lsp analyze`** (new solver, Roblox definitions, Rojo sourcemap) rather than
  `luau-analyze`, which knows neither Roblox types nor instance-path requires.
- **luau-lsp 1.70.1 crashes** on an explicit instantiation whose argument is a type-function application
  (`FromSchema<<StructOf<F>>>(…)`) and on annotating a local with `EnumItemOf<E>`. Those sites use
  `Unsafe.Assume(value) :: T` instead.
- **Tests use a small custom runner** (`tests/Runner.luau`, describe/it/expect) instead of TestEZ or Jest-Lua, and
  there is no Wally dev dependency. The same specs must run headlessly in CI under the standalone Luau runtime
  (which supports `const`; Lune at the time did not) and in Studio; both frameworks assume the Roblox
  environment.
- **Headless by construction.** Shared modules never touch the engine when they load; everything engine-related
  goes through a `PlatformInfo` (`Platform.Roblox()` or `Platform.Headless()` with a virtual clock and cooperative
  scheduler). UI modules that read `Enum` at load are only required on clients.
- **Doc comments use `---`** (shown by luau-lsp on hover) rather than Moonwave blocks; the reference is generated
  from the live registry by `RoShell.Docs` (`docs/Reference.md`).

## Engine findings

- **Never park an engine callback with `coroutine.yield`/`coroutine.resume`.** The dispatcher originally waited
  for a command's worker thread that way. When the waiting thread was an `OnServerInvoke` callback, its return
  value went back to the `coroutine.resume` call instead of the engine, and the client's `InvokeServer` never
  returned — but only for commands that yield (a countdown, a prompt). `Platform.Gate()` now parks threads with a
  `BindableEvent` wait (an engine yield); the regression is covered by an engine-only spec that runs a yielding
  command inside a `BindableFunction` callback.
- **RemoteEvent and RemoteFunction messages are not ordered relative to each other.** Output blocks stream over
  the event while the result returns over the function, so the result could arrive first and its blocks were
  dropped. Results now carry the number of blocks sent, and the client waits (bounded) until it has them all.
- **Enter types a carriage return.** On a real keyboard, Return's character can land in the input right after the
  console recaptures focus (or at the caret just before focus is lost). Line breaks are therefore never kept in the
  single-line input: a change that only adds breaks is dropped silently, and only pasted text with two or more
  non-empty lines is offered as a script (`Client/UI/InputText.luau`, unit tested). History keeps a script as the
  equivalent single line (`Lexer.ToLine`: breaks become `;`, comments go, strings get escapes; fuzzed against the
  parser), so Up never brings line breaks back into the input.
- **Property-changed signals are deferred.** The input bar compares against the last known text instead of using
  suppression flags, reads the `TextBox` directly when Enter is pressed, checks focus with `TextBox:IsFocused()`
  rather than event-maintained flags, and retries focus capture for a few frames (a capture in the same frame as
  an Enter-triggered focus loss can be undone).
- **Capturing focus again right after Enter may not fire `Focused`.** The box ends up focused with no event, so the
  caret and focus ring follow `TextBox:IsFocused()` each frame instead of the events alone.
- **Font coverage.** `❯ ✕ ⌕ ⎘ ↺ ⚑ ∗ ↵ ◷` do not exist in Roblox's fonts and `⚙ ↪ ✔` fall back to fixed-color emoji.
  Every icon glyph was checked in Studio (`Ui.luau` lists the set). Box-drawing characters come from a fallback
  font wider than a RobotoMono cell, so table headers are underlined instead of ruled.
- **A transparent `TextBox` hides its caret and selection.** The input draws both (spring-animated caret, soft
  blink), with monospace measurement for ASCII and measured widths otherwise.

## Language

- **`#` is a comment only at the start of a word followed by whitespace**, so `#Tag` remains available as the tag
  selector (`freeze #Boss`).
- **`!a` is the complement and `-` the difference** (`kick *-Bob`, `kill !%Red`); `&` binds tighter than `+`, `-`
  and `,`. A word that exactly names a candidate is always literal, so names containing operator characters work.
- **`~fuzzy` picks the best match for a single-value argument** and every strong match (≥ 60 % of the best score)
  for a list. Treating a tie in a single-value argument as an error made `give ~sw` unusable.
- **Optional arguments are skipped by type.** With fewer words than positional arguments, an optional argument
  whose type rejects the word, when the next argument's type accepts it, keeps its default. This makes
  `give [targets = me] <item> [amount]` work as `give ~sword 3` while `give Bobb sword` still reports
  "Unknown player 'Bobb'". Optional arguments may therefore precede required ones.
- **An embed is one argument.** `${…}` output is never split into several words; when the embed is the whole word
  its typed value flows into the argument directly.
- **`$1`…`$9` and `$@` exist only while an alias runs**; elsewhere they are literal text, which is what lets
  `alias gg = "announce GG $1"` store its body unexpanded.
- **Cmdr's `Format` hook is replaced by `ParseResult.Display`**, the human-readable rendering returned with the
  value and reused by previews, echoes and the audit log.
- **Aliases complete under their own name.** Appendix C lists `grant` among the completions of `giv`; `grant`
  does not match `giv`, and listing every alias of every matching command would crowd the list, so `gra` finds
  `grant` (detail: "alias of give") instead.

## Completion and console behavior

- **Completion is synchronous and client-side.** Candidates come from the client's registry and from type
  providers, with caching (`Dynamic.CacheSeconds`, prepared-string caches). The specification describes async
  providers with an 8 ms budget and server round trips for server-only data; the benchmarks show 10 000
  candidates complete in under 1 ms, so the async machinery was not built. Types needing server data should
  expose it through replicated state. This is the main deviation from §7.1.
- **Parsing is memoized, not incremental.** The parser keeps the last input (the caret moves far more often than
  the text changes). A 2.3 KB script parses in under 1 ms, so token-level incremental reparsing (§11) was not
  needed. Similarly, lookups use hash maps plus cached fuzzy records rather than a prefix trie.
- **Tab** first completes the longest common prefix when it adds something, then cycles through the list it was
  cycling (the list stays on screen while cycling). **Enter** accepts a suggestion only if one was picked with the
  keyboard; hovering never commits. The **first Enter on an invalid line shakes** the input; a second Enter sends
  it anyway (the server decides). **Esc** is progressive: close suggestions → clear → close the console.
- **The word being typed is not flagged** while it still has completions; errors appear once the word is
  finished.
- **Return values are shown only when the command printed nothing**, and plain strings print as plain lines.
- **The log bakes theme colors into RichText**, so it keeps each row's source and re-formats every row when the
  theme changes. It stays pinned to the bottom unless the player scrolls; scrolls RoShell makes itself
  (including animated ones) never unpin it.

## UI construction

- **Everything is built from code**, themed by tokens and laid out manually in hot paths. Themes are defined as hex
  strings so the 4.5:1 contrast audit runs headlessly; they resolve to `Color3` palettes at runtime.
- **Shadows are layered transparent frames** (no asset dependency). The window is a `CanvasGroup` so it can fade as
  one; other surfaces are plain frames.
- **The console docks to the top by default**, like Cmdr: centered below Roblox's top bar (the GUI ignores the
  inset, so the window steps below it), width-capped, and only as tall as its output needs, up to 40% of the
  screen (more while a prompt dialog is shown inside it). Floating and bottom docks remain available.
- **Touch devices** keep the console docked, with larger targets and suggestion chips. **Gamepad** support is limited to
  the touch/gamepad button, D-pad navigation of suggestions and R1/L1 to accept; the on-screen keyboard handles
  text.

## Not implemented (P2 and beyond)

- Output channels/tabs and in-log search (§9.21), usage-based suggestion chips (§9.24), Luau type stub generation
  (§9.26), and Studio command bar integration (§9.27).
- A cross-server `shutdown-all`: `announce --global` uses MessagingService, but `shutdown` acts on the current
  server.
- Cmdr v1 compatibility (§12 says it is not required); the README has a migration table instead.
