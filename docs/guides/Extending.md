# Writing plugins and extending RoShell

Everything below is typed; the [examples](../../examples/) folder has runnable versions.

## Plugins

A plugin bundles commands, types, `$functions`, hooks and middleware so a feature can be shared between games.
Register it on the server, and on clients too when it has client parts (`ClientRun` commands, themes, renderers).

```lua
return RoShell.Plugin({
	Name = "Weather",
	Commands = { forecast },
	Types = { Weather },
	Functions = { { Name = "season", Description = "The current season", Call = function() return "winter" end } },
	Hooks = { AfterRun = function(ctx, result) --[[ … ]] end },
	Middleware = { timing },
	Setup = function(shell) --[[ anything else: env values, selectors, locale ]] end,
})

shell.Registry:RegisterPlugin(Weather)   -- the same line on each side
```

Plugins can also carry `Themes = { { Name, Base, Overrides } }` and `Renderers = { name = fn }` for custom output
blocks:

```lua
-- server: ctx:Block({ Kind = "custom", Renderer = "scoreboard", Data = { Red = 3, Blue = 5 } })
Renderers = {
	scoreboard = function(data)
		const rows = {}
		for team, score in data do table.insert(rows, { team, tostring(score) }) end
		return { Kind = "table", Columns = { "Team", "Score" }, Rows = rows }
	end,
},
```

## Registry

| Method | Purpose |
|---|---|
| `RegisterCommand(command)`, `RegisterCommands(list)` | Add commands (a later registration replaces a built-in of the same name) |
| `RegisterCommandsIn(container, filter?)` | Load every ModuleScript under `container` returning a command or a list of them |
| `ReloadCommands()` | Hot reload: re-require (fresh copies of) every container registered above; returns the count (`reload` command) |
| `UnregisterCommand(name)` | Remove a command |
| `RegisterDefaultCommands(filter?)` | Built-ins, optionally filtered by group list or predicate. `Start` registers them all unless you did (or passed `DefaultCommands = false` or a list of groups to `RoShell.new`) |
| `RegisterType(type)`, `RegisterTypes(list)` | Make types known by name (help, `types`, `resolve`, pipe checks) |
| `RegisterTypesIn(container)` | Load every ModuleScript returning a type or a list/record of types |
| `RegisterHooksIn(container)` | Load every ModuleScript returning `RoShell.Hooks({ ... })` |
| `RegisterTheme(options)` | A console theme (`{ Name, Base, Overrides }`), created on clients when the console starts |
| `RegisterOutputRenderer(name, fn)` | Turns `custom` output blocks into standard blocks on the client |
| `RegisterSelector(type, selector)` | Add a prefix form (`@rank:200`) to an enumerable type |
| `RegisterFunction({ Name, Description, Call })` | Add a `$name(args)` function |
| `RegisterHooks({ BeforeRun, AfterRun, OnError }, priority?)` | Global hooks; returns an unregister function |
| `RegisterMiddleware(fn, priority?)` | Wrap every execution; returns an unregister function |
| `RegisterPlugin(plugin)` | All of the above at once |
| `AddEnv(key, value)` | Typed values for commands (`ctx:GetEnv(key)`) |
| `GetCommand(s)`, `GetType(s)`, `GetFunctions()`, `GetCommandNames()` | Lookups |

### Hooks and middleware

```lua
registry:RegisterHooks({
	BeforeRun = function(ctx)            -- return a message to block the command
		if ctx.Command.Group == "Admin" and workspace:GetAttribute("Tournament") then
			return "Admin commands are disabled during tournaments"
		end
		return nil
	end,
	AfterRun = function(ctx, result) end,
	OnError = function(ctx, message) warn(message) end,
})

registry:RegisterMiddleware(function(ctx, nextHandler)
	const started = os.clock()
	const result = nextHandler()
	print(ctx.Command.Name, os.clock() - started)
	return result
end)
```

### Typed environment

```lua
const Economy = RoShell.EnvKey<<EconomyService>>("Economy")
shell.Registry:AddEnv(Economy, economyService)

-- in a command
const economy = ctx:GetEnv(Economy)   -- EconomyService?
```

## Adapters

### Storage (`RoShell.StorageAdapter`)

Persists per-player console data (history, aliases, binds, variables, settings) and `ctx:GetStore` data.

```lua
RoShell.new({ Storage = RoShell.Storage.DataStore("RoShellUserData") })   -- default: RoShell.Storage.Memory()
```

A custom adapter implements `Get(self, scope, key)`, `Set(self, scope, key, value)` and `Remove(self, scope, key)`.

### Audit (`RoShell.AuditSink`)

Every server-side execution produces `{ Time, Executor, ExecutorId, Raw, Command, Args, Ok, Result, Duration }`.

```lua
RoShell.new({
	Audit = RoShell.Audit.Fanout({
		RoShell.Audit.Memory(500),            -- the `audit` command reads `Recent`
		RoShell.Audit.DataStore("RoShellAudit"),
		webhookSink(url),                     -- see examples/05-ServerSetup.luau
	}),
})
```

A sink implements `Write(self, entry)` and optionally `Recent(self, count)`.

### Telemetry (`RoShell.TelemetrySink`)

`{ Command, Ok, Duration, Executor }` per execution, for usage counts, error rates and latency percentiles:

```lua
RoShell.new({ Telemetry = { Record = function(_self, event) analytics:Track(event) end } })
```

## Localization

All built-in strings go through `shell.Locale`. Override any key:

```lua
RoShell.new({ Locale = { ["run.canceled"] = "Annulé" } })
shell.Locale:Set({ ["run.canceled"] = "Annulé" })
```

## Events between server and client

```lua
ctx:SendEvent(player, "Confetti", { Color = Color3.new(1, 0, 0) })   -- server command
shell:SendEvent(player, "Confetti", payload)                          -- anywhere on the server
shell:OnEvent("Confetti", function(payload) --[[ … ]] end)            -- client
```

Payloads are sanitized (no functions, bounded depth and size) before they are sent.

## Documentation generation

```lua
print(RoShell.Docs.Markdown(shell.Registry))                         -- Markdown reference
const schema = RoShell.Docs.Schema(shell.Registry, { Filter = … })    -- plain data, JSON-encodable
```

[docs/Reference.md](../Reference.md) is generated this way (`bash scripts/run.sh scripts/reference.luau > docs/Reference.md`).
