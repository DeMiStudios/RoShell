# RoShell

**A typed command console for Roblox.** Define commands once and get fully typed arguments, a real input language
(pipes, chains, wildcards, set arithmetic, variables, embedded commands), IDE-grade completion and a command bar
that stays out of the way until you need it. A ground-up remake of [Cmdr](https://github.com/evaera/cmdr).

![The command bar: the command on the left, the argument being typed and its candidates on the right](docs/images/completion.jpg)

```lua
local RoShell = require(ReplicatedStorage.RoShell)

return RoShell.Command({
	Name = "give",
	Args = {
		{ targets = RoShell.Default(RoShell.Types.Players, "me") },
		{ item = RoShell.Arg(Items) },
		{ amount = RoShell.Default(RoShell.Types.Integer, 1) },
	},
}):Run(function(ctx, args)
	-- args.targets: { Player }   args.item: ItemDef   args.amount: number   (inferred, no annotations)
	return ctx:Success(`Gave {args.amount}× {args.item.Name}`)
end)
```

```
give %Red-Bob ~embers 3 && announce "Loot dropped!"
players --team Blue | kick --reason "friendly fire"
in 5m shutdown "Update!" --dry
```

## Highlights

- **Precise types end to end.** `Run(ctx, args)` receives a record computed from `Args` by Luau type functions:
  choices become literal unions, maps and dynamic types carry their value type, optionals are `T?`, rests are
  `{ T }`. Mistakes are compile errors (see `tests/types/negative`). No `any` anywhere in the library.
- **Custom types in a few lines.** `Type.Choice`, `Type.Map`, `Type.Dynamic`, `Type.Struct`, `Type.Union`,
  `Type.Transform`, `Type.Refine`, … and 40+ built-in types (players, teams, durations, colors, vectors, instances,
  enums, timestamps, …).
- **A real input language.** Quotes and escapes, `&&` `||` `;` `|`, `${embedded commands}`, `$variables`,
  `$functions()`, aliases with `$1…$9`, flags and named arguments, `--dry` previews and `--yes`. See
  [docs/GRAMMAR.md](docs/GRAMMAR.md).
- **Operators everywhere.** `*`, `**`, `.`, `?3`, `~fuzzy`, globs, `%Team`, `#Tag`, `a,b`, `a+b`, `a-b`, `a&b`,
  `!a`, parentheses and numeric ranges, for every enumerable type, including your own.
- **Completion that understands the line.** Works mid-text, inside quotes and `${…}`, after pipes; fuzzy ranking
  with highlights and frecency; ghost text; signature hints with the active argument; live validation; resolution
  previews (`→ 7 players`). 10 000 candidates complete in under 1 ms.
- **A console that stays out of the way.** A command bar docked to the top (or bottom, or anywhere you drag it)
  with a panel that pops out only when there is something to show: the argument you are typing and its candidates,
  the output of what you ran, the whole log on demand (Ctrl+H), prompts, a command palette (Ctrl+K), fuzzy history
  search (Ctrl+R) and a theme picker with live previews. Sixteen contrast-audited themes (Midnight, Sakura, Ocean,
  Light...), icons from Roblox's icon font, springs that respect reduced motion, and touch and gamepad support.
- **Secure by default.** Default-deny permissions (users, groups, roles, game passes, badges, predicates), the
  server re-parses every request, typed schema validation at the network boundary, rate limits, cooldowns and an
  audit log.
- **Batteries included.** 60+ built-in commands: help, aliases, binds, variables, history, undo/redo, scheduling
  (`in`, `every`, `repeat`), scripts, moderation, inspection, cross-server announcements, theme and settings.
- **Testable.** `RoShell.Test.Run({ Text = "give Bob sword" })` runs commands headlessly with a virtual clock and
  scripted prompt answers.

| | |
|---|---|
| ![A command's output](docs/images/output.jpg) | ![Command palette](docs/images/palette.jpg) |
| ![Prompts raised by commands](docs/images/prompt.jpg) | ![Sakura theme](docs/images/sakura.jpg) |

## Quickstart

Put RoShell in `ReplicatedStorage` (Wally, the `.rbxm` from the releases, or Rojo with `default.project.json`).
Then one line on each side.

**Server** (a `Script` in `ServerScriptService`):

```lua
local RoShell = require(game.ReplicatedStorage.RoShell)
RoShell.Server.new({ Admins = { 156 } }):Start()   -- user ids that may run every command
```

**Client** (a `LocalScript` in `StarterPlayerScripts`):

```lua
require(game.ReplicatedStorage:WaitForChild("RoShell")).Client.new():Start()
```

Press **F2** or **`** to open the console. Everyone gets the built-in commands that are open to all (help,
history, aliases, themes, settings...), the admins get everything, and in Studio every command is allowed for
testing.

**Your own commands** go in a folder in `ReplicatedStorage`, named on the server. Clients load the same folder
by themselves:

```lua
RoShell.Server.new({ Admins = { 156 }, Commands = game.ReplicatedStorage.Commands }):Start()
```

**Everything else is optional** and there when you want it: `Admins` also takes rules
(`{ 156, RoShell.Permissions.Group(1234567, 250) }`), per-group and per-command permissions and roles, hooks,
middleware, audit sinks, `DefaultCommands = { "Help", "Utility" }` to pick the built-ins, client options for keys,
themes and settings. See [examples/00-MinimalSetup.luau](examples/00-MinimalSetup.luau) and
[examples/05-ServerSetup.luau](examples/05-ServerSetup.luau) for a production setup.

**Do I need a DataStore?** No. Players' history, aliases, key binds, variables and console settings are kept in
memory for the life of the server by default. To keep them between sessions, give the server a DataStore-backed
adapter: `RoShell.Server.new({ Storage = RoShell.Storage.DataStore("RoShell") })` (or your own adapter with
`Get`/`Set`).

## Guides

- [Your first command](docs/guides/FirstCommand.md)
- [Custom types in 60 seconds](docs/guides/CustomTypes.md)
- [Operators and wildcards](docs/guides/Operators.md)
- [Permissions](docs/guides/Permissions.md)
- [The console: anatomy, keys, settings, themes, icons](docs/guides/Console.md)
- [Writing plugins and extending RoShell](docs/guides/Extending.md)
- [Security model](docs/guides/Security.md)
- [Testing commands](docs/guides/Testing.md)
- Reference: [input grammar](docs/GRAMMAR.md), [built-in commands, types and functions](docs/Reference.md)
  (generated by `RoShell.Docs.Markdown`), [benchmarks](docs/BENCHMARKS.md), [design notes](DESIGN_NOTES.md)
- Runnable [examples](examples/) and a [demo place](demo/) (`rojo serve demo.project.json`)

## Coming from Cmdr

| Cmdr v1 | RoShell |
|---|---|
| Definition module + separate `…Server` module | One module: `RoShell.Command({ … }):Run(fn)` (`:ClientRun(fn)` for client code) |
| `Args = { { Type = "player", Name = "target" } }` | `Args = { { target = RoShell.Arg(RoShell.Types.Player) } }`, typed in `Run` |
| `Optional = true`, `Default = …` | `RoShell.Optional(T)`, `RoShell.Default(T, value or "text")`, `RoShell.DefaultFn(T, fn)` |
| Type tables `{ Transform, Validate, Autocomplete, Parse }` | `RoShell.Type.Custom({ Parse, Complete })` or a constructor (`Choice`, `Map`, `Dynamic`, …) |
| `Util.MakeEnumType`, `MakeListableType`, `MakeFuzzyFinder` | `Type.Choice`, `Type.List`, fuzzy matching built into every enumerable type |
| `Registry:RegisterType("name", type)` | `Registry:RegisterType(type)` (the name comes from the type) |
| `Registry:RegisterHook("BeforeRun", fn)` | `Registry:RegisterHooks({ BeforeRun = fn })`, plus `RegisterMiddleware` |
| Group checks inside a `BeforeRun` hook | Default-deny `Permissions` per command or per group (`Permissions:SetGroup`) |
| `context:Reply(text, color)` | `ctx:Reply(text, level)`, `ctx:Success/Info/Warn/Error`, `ctx:Table/List/KeyValue/Color/Progress` |
| `Data = function(context, …)` | `:Data(fn)`; read with `ctx:GetData()` |
| `CmdrClient:HandleEvent(name, fn)` / `context:SendEvent` | `client:OnEvent(name, fn)` / `ctx:SendEvent(player, name, payload)` |
| `CmdrClient:SetActivationKeys`, `SetPlaceName`, `SetEnabled`, `Show/Hide/Toggle`, `SetMashToEnable`, `SetActivationUnlocksMouse`, `SetHideOnLostFocus` | Same names on `client` |
| `Cmdr.Dispatcher:EvaluateAndRun(text, player)` | `server:Run(text, player)` / `client:Run(text)` |
| `${…}`, `$1`, `alias`, `bind`, `var` | Same ideas, plus pipes, `&&`/`||`, `$$`, `$@`, `$fn()`, set operators and ranges |

## Development

Tools are pinned in `rokit.toml` (`rokit install`): Luau LSP, Larvae (formatter), selene, Rojo and the Luau CLI.

```bash
bash scripts/analyze.sh       # strict type check (new solver), zero errors
bash scripts/typetests.sh     # negative type tests: marked lines must fail
luau tests/cli.luau           # unit tests (headless)
luau --codegen tests/bench.luau
larvae fmt src tests demo examples
```

In Studio, `require(game.ServerStorage.RoShellDev.tests.Studio)()` runs the same suite plus the engine-only specs.

## License

MIT. RoShell is inspired by [Cmdr](https://github.com/evaera/cmdr) by evaera and contributors.
