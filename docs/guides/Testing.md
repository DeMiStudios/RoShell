# Testing commands

`RoShell.Test` runs command lines against a headless shell: no UI, no network, and a virtual clock, so waits finish
instantly. It works inside any test framework, in Studio and headless (RoShell's own suite runs under the Luau CLI).

```lua
const result = RoShell.Test.Run({
	Text = "give Bob sword 3",
	Commands = { giveCommand },
	As = player,                 -- optional executor (nil = server console)
	Answers = { "yes" },         -- prompt answers, in order
})

assert(result.Ok, result.Output)
print(result.Value)              -- value of the last command
print(result.Lines)              -- text/value/list/table output, one entry per line
print(#result.Prompts)           -- prompts the commands raised
```

Reuse one shell for several runs:

```lua
const harness = RoShell.Test.new({
	Commands = { giveCommand, takeCommand },
	Types = { Item },
	Defaults = true,     -- also register the built-in commands
	Client = false,      -- true: run `ClientRun` handlers instead of `Run`
})
harness.Run("give Bob sword")
harness.Run("take Bob sword", { Answers = { "yes" } })
harness.Clock:Advance(60)   -- drive scheduled commands (`in`, `every`) forward
```

## RoShell's own tests

- `bash scripts/test.sh`: every spec headlessly (lexer, parser, resolver, types, operators, fuzzy, completion,
  dispatcher, built-in commands, themes, highlighting, formatting, the public API and the spec's worked examples),
  under the Luau CLI through the headless loader described below.
- `require(game.ServerStorage.RoShellDev.tests.Studio)()` — the same suite in Studio, plus engine-only specs (real
  colors/vectors/enums/instances, text metrics, permissions with a real player, waits inside engine callbacks).
- `bash scripts/analyze.sh` — strict type check of everything, including `tests/types/positive`.
- `bash scripts/typetests.sh` — `tests/types/negative`: each line marked `-- expect-error` must fail to type-check,
  and nothing else may.
- `bash scripts/run.sh tests/bench.luau --codegen`: benchmarks with budgets ([results](../BENCHMARKS.md)).

### The headless loader

RoShell requires its modules the way Roblox does (`require(script.Parent.Shared.Fuzzy)`), and the Luau CLI only
knows string requires, has no `script` and cannot read files. `bash scripts/run.sh <entry.luau> [luau options]`
bridges the two:

1. `scripts/headless.py` mirrors the Rojo tree of `demo.project.json` with Rojo's rules: a folder is a `Folder`, a
   folder with an `init.luau` is that module with the other files as its children, `X.luau` is a `ModuleScript`,
   `X.server.luau` a `Script` and `X.client.luau` a `LocalScript`. Tests live at
   `ServerStorage.RoShellDev.tests`, next to `RoShellDev.src`, exactly as in the demo place.
2. It writes `.cache/headless/<entry>.luau`, a program holding that tree, every script's source and the loader,
   and runs `luau` on it with your options.
3. The loader (`scripts/Headless.luau`) gives every module a read-only `script` proxy (`Name`, `ClassName`,
   `Parent`, children by name or `["02-CustomTypes"]`, `FindFirstChild`, `WaitForChild`, `GetChildren`,
   `GetFullName`, `IsA`) and a `require` that loads the file behind a ModuleScript proxy once and caches it. Like
   Roblox, it errors on a missing member, on a module that does not return exactly one value or failed to load
   before, and on a require cycle (naming the chain).

Errors and tracebacks name the real file and line (`tests/unit/ParserSpec.luau:42`). With `--codegen`, the modules
the entry requires are compiled into the generated program so they run as native code, and errors in them name
lines of the generated file. Any `.luau` file of the tree can be an entry; `scripts/reference.luau` regenerates
[the reference](../Reference.md) this way.
