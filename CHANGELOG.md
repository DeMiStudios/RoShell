# Changelog

All notable changes to RoShell are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Changed

- The console docks to the top of the screen by default, like Cmdr: centered below Roblox's top bar and only as
  tall as its output needs (up to 40% of the screen). `config dock float|bottom` restores the other placements.
- Toasts and the touch button sit below Roblox's top bar.
- Settings persist only values that differ from the defaults, so later default changes reach existing players.
- `config` completes and checks values with the setting's own type (`config dock ` offers top, bottom, float).

### Fixed

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
