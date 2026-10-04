# Changelog

All notable changes to RoShell are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Changed

- **The console is a command bar.** A pill docked to the top of the screen (below Roblox's top bar) by default,
  like Cmdr, with a panel that pops out only when there is something to show: while typing, commands on the left
  and the argument being typed with its type, description and candidates on the right; after running a command,
  its output; on demand, the whole log. Prompts, the command palette, history search, settings and the new theme
  picker show in the panel, with the bar's input as the pickers' search field. The panel opens below a top bar,
  above a bottom bar, and on the roomier side of a floating one. Dragging the prompt icon floats the bar; letting go
  near a dock docks it. Glass surfaces without drop shadows. The windowed design is kept on the
  `pin/classic-console` branch.
- Toasts and the touch button sit below Roblox's top bar.
- Settings persist only values that differ from the defaults, so later default changes reach existing players.
- `config` completes and checks values with the setting's own type (`config dock ` offers top, bottom, float).
- `theme` with no argument opens the theme picker; `opacity` defaults to 0.95.
- **Setup is one line per side.** `Start` registers the built-in commands (unless you already did, or pass
  `DefaultCommands = false` or a list of groups), and clients load the command folders the server registered from
  `ReplicatedStorage`, so `RoShell.Client.new():Start()` is the whole client script. The demo uses it.
- **Tab fills in and moves on.** Tab puts in the highlighted suggestion (the top one unless the arrows moved the
  highlight) and goes to the next argument, whose candidates show next; it no longer completes a common prefix or
  cycles. The arrows choose (wrapping around, repeating while held, also in the browse list on an empty line, in
  pickers and in prompts); Shift+Tab moves the highlight back; Tab chooses in pickers. The ghost text previews the
  highlighted suggestion.
- While an argument is typed the left column shows only that command (no recent or related commands).
- The mouse no longer moves the highlight: rows under the pointer get a tint and clicks choose.
- The highlighted candidate's description has a line of its own that keeps its room while the highlight moves.
- Cross-argument validation (`:Validate`) runs before `--dry` previews and confirmations.
- `ctx:Broadcast` returns whether other servers could be reached (and why not).

### Added

- Ten themes: Sakura, Blossom, Ocean, Forest, Ember, Dusk, Arctic, Lavender, Mint and Sand (sixteen in all), with
  descriptions (`Description` in `Theme.Create`), a picker that previews them live, and forgiving names
  (`theme high contrast`, `theme dark`). The contrast audit also checks text on the selection tint.
- Icons from Roblox's Builder Icons font (Unicode fallbacks if it cannot load). Commands take an `Icon`; every
  built-in, demo and example command has one, and operator and selector chips get matching icons.
- `Ctrl+H` and the history button show or hide the whole log (`ToggleLog` in the keymap); a dot on the button marks
  output that arrived while something else was showing.
- `config quoting quotes|backslash`: completions write values with spaces as `"Golden Apple"` (default) or
  `Golden\ Apple`.
- `config font sans|mono` for the bar's input; key hints in the bar (`Tab` to autocomplete, `Enter` to run).
- `OpenThemes` and `DescribeTheme` on the console API; theme names complete with their descriptions.
- `Admins` server option (user ids and/or permission rules) and `Permissions:SetAdmins(rule)`: these players may
  run every command.
- `Commands` and `DefaultCommands` options on `Server.new` and `Client.new`.
- `examples/00-MinimalSetup.luau`, and docs for flags and options (`--flag`, `-f`, `-abc`, `--name value`,
  `--name=value`, `--`) and for storage (in memory by default; a DataStore adapter keeps players' console data
  between sessions).
- Demo: `give` takes several players, several items and one amount for all of them or one per item
  (`give me,Bob ~embers,~healing 1,5`), checked before anything happens; `giveitem` keeps the one-item form.

### Fixed

- Completing the next item of a list escaped the items before it again (`Golden\ Apple,Dra` + Tab gave
  `Golden\\\ Apple,Dragon\ Scale`). Completion now reads what was typed like the parser does (quotes and escapes
  resolved), keeps earlier items exactly as written and only writes the new one. Typing `Dragon\ Sc` also
  matches "Dragon Scale" now, and items already in the list are not offered again.
- List items resolved in the type's order instead of the order typed, so `give me ~apple,~dragon 1,5` could pair
  the amounts with the wrong items.
- The caret could not reach the end of long highlighted lines (`bring . && bring . && …`): colored text drew a
  little wider than the text being edited, more with every colored word, so typing and pasting landed short of
  the glyphs. The colored text now uses the input's own layout.
- Scrolling the candidates quickly made them jump: the highlight followed the pointer, which changed the details
  above the list, resized the panel and scrolled the list back to the highlight.
- `announce --global` showed nothing in places that were never published (MessagingService never answers there)
  and relied on the sending server hearing its own message. Announcements now show in the sending server at once
  (never twice), and `announce` says when other servers could not be reached.
- The first arrow press after the suggestions appeared only "claimed" the highlighted row instead of moving.
- A missing argument the caret is heading towards no longer shows as an error until Enter is refused (and then
  says why).
- Picker search ranks names and aliases above descriptions (`tp` finds `teleport` first).
- The palette, history and log shortcuts work while the console is open but unfocused.

- Pressing Enter could open "Run pasted script? The pasted text has 1 lines": the Enter key's carriage return
  was treated as a multi-line paste (and, if it landed before the submit, the command could run twice). Line
  breaks are now dropped unless the pasted text has two or more non-empty lines.
- Enter or Y/N while a prompt dialog was open could also submit the line being typed.
- Undocking the console by dragging could snap it to a previously saved position.
- Running a second command while one was still running lost track of the first (status and Ctrl+C).
- Saved history kept the oldest 256 entries instead of the most recent ones; the last 200 are now saved.
- Key binds using Cmd on macOS did not fire.
- Tab cycling restored the wrong caret position, and the activation key's character could be removed from the
  wrong place in the input.
- Pressing Up after running a pasted script brought its line breaks back into the input and asked "Run pasted
  script?" again. History now keeps a script as the equivalent one-line command (`echo a; echo b`).
- After Enter, the input could keep focus without showing its caret or focus ring.
- Completion offered `.` (you) for values that have no "you", such as `config dock .`.
- A completion containing a carriage return could be taken for a multi-line paste.
- A line continuation inside quotes no longer changes a word: `"$x\` + newline + `"` passes `$x`'s typed value
  like `"$x"` does.

## [0.1.0] - 2026-10-03

First release: a ground-up remake of Cmdr.

### Added

- **Typed commands.** `RoShell.Command({ Name, Args = { { name = RoShell.Arg(T) }, … } }):Run(fn)` with `args`
  inferred by Luau type functions; `Optional`, `Default` (values or text parsed per run), `DefaultFn`, `Rest`,
  `Flag`, `Dynamic`; subcommands, validation, dry-run previews, destructive confirmations, client data collectors,
  cooldowns, rate limits, timeouts, undo, `ClientRun`.
- **Type system.** `Type.Choice`, `Map`, `Dynamic`, `Enumerable`, `Custom`, `Number`, `Integer`, `String`,
  `Boolean`, `Pattern`, `Range`, `List`, `Optional`, `Union`, `Tuple`, `Struct`, `Transform`, `Refine`, `FromEnum`;
  45 built-in types (players, teams, user ids, durations, timestamps, colors, vectors, instances, classes, tags,
  enums, keybinds, commands, …); prefix selectors (`%Team`, `#Tag`, custom).
- **Input language.** Quotes and escapes, raw strings, comments, `;` `&&` `||` `|`, embedded commands `${…}`,
  variables `$name` `$$` `$1…$9` `$@` `$:ref`, built-in `$functions()`, flags and named arguments, global `--dry`
  and `--yes`, aliases and macros. Error-tolerant lexer and parser with spans for every diagnostic.
- **Operators.** `*`, `**`, `.`, `?N`, `~fuzzy`, globs, `/patterns/`, lists, union, difference, intersection,
  complement, grouping and stepped numeric ranges for every enumerable type.
- **Completion.** Cursor-anywhere completion inside quotes, embeds and pipelines; fzy-style fuzzy matching with
  highlights, smart case, multi-term queries and top-K selection; frecency; signature hints; live diagnostics;
  resolution previews; ghost text.
- **Console UI.** Six contrast-audited themes and `Theme.Create`; virtualized log with tables, lists, key/value
  blocks, color swatches, links and live progress; syntax-highlighted input with custom caret; suggestion popup;
  command palette; fuzzy history search; prompt dialogs; toasts; copy sheet; docking, dragging and resizing;
  touch chips and button; remappable keymap; typed settings (`config`); reduced-motion support.
- **Server and networking.** Single RemoteFunction + RemoteEvent with a versioned handshake, schema-validated
  payloads, token-bucket rate limiting, server-side re-parsing, streamed output, remote prompts, cancellation,
  server-held values for pipes, per-player visibility lists, persisted user data, MessagingService announcements.
- **Permissions.** Default deny; users, groups and ranks, roles, game passes, badges, Studio, predicates and
  combinators; per command or per group.
- **Built-in commands** (61): help, commands, types, operators, echo, math, random, replace, len, run, runif, wait,
  history, clear, hide, palette, theme, config, export-log, alias, unalias, aliases, set, get, unset, vars, bind,
  unbind, binds, undo, redo, resolve, version, uptime, kick, kill, respawn, teleport, to, bring, heal, speed,
  freeze, thaw, announce, shutdown, players, inspect, tags, tag, untag, blink, position, audit, reload, in, every,
  repeat, schedules, cancel, run-script.
- **Extension points.** Plugins, hooks (`RegisterHooks`, `RegisterHooksIn` with `RoShell.Hooks`), middleware,
  `RegisterTypesIn`, selectors, `$functions`, themes, output renderers, typed environment keys; storage, audit and
  telemetry adapters (memory and DataStore implementations, fan-out); localization.
- **Tooling.** `RoShell.Test` headless harness, `RoShell.Docs` schema and Markdown generator, unit specs (headless
  and in Studio), positive and negative type tests, benchmarks with budgets, GitHub Actions CI, a demo place and
  examples.
