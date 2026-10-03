# Testing commands

`RoShell.Test` runs command lines against a headless shell: no UI, no network, and a virtual clock, so waits finish
instantly. It works inside any test framework and in the standalone Luau runtime.

```lua
local result = RoShell.Test.Run({
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
local harness = RoShell.Test.new({
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

- `luau tests/cli.luau` — every spec headlessly (lexer, parser, resolver, types, operators, fuzzy, completion,
  dispatcher, built-in commands, themes, highlighting, formatting, the public API and the spec's worked examples).
- `require(game.ServerStorage.RoShellDev.tests.Studio)()` — the same suite in Studio, plus engine-only specs (real
  colors/vectors/enums/instances, text metrics, permissions with a real player, waits inside engine callbacks).
- `bash scripts/analyze.sh` — strict type check of everything, including `tests/types/positive`.
- `bash scripts/typetests.sh` — `tests/types/negative`: each line marked `-- expect-error` must fail to type-check,
  and nothing else may.
- `luau --codegen tests/bench.luau` — benchmarks with budgets ([results](../BENCHMARKS.md)).
