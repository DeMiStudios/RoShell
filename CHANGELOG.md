# Changelog

All notable changes to RoShell are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses [Semantic Versioning](https://semver.org/).

## [Unreleased]

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
