# Your first command

A command is one ModuleScript that returns `RoShell.Command(...)`. Register the folder that holds your commands on
**both** the server and the client: the client needs the definitions for completion and validation, the server runs
them.

```lua
-- ReplicatedStorage/Commands/Heal.luau
--!strict
local RoShell = require(game.ReplicatedStorage.RoShell)

return RoShell.Command({
	Name = "heal",
	Icon = "heart",                       -- shown next to the command in the console (see the console guide)
	Aliases = { "hp" },
	Description = "Restores players' health",
	Group = "Admin",
	Examples = { "heal me", "heal %Red 50" },
	Args = {
		{ targets = RoShell.Default(RoShell.Types.Players, "me", { Description = "Who to heal" }) },
		{ amount = RoShell.Optional(RoShell.Type.Number({ Min = 0, Max = 100 })) },
	},
}):Run(function(ctx, args)
	-- args.targets: { Player }, args.amount: number?
	for _, player in args.targets do
		local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid.Health = if args.amount then humanoid.Health + args.amount else humanoid.MaxHealth
		end
	end
	return ctx:Success(`Healed {#args.targets} player(s)`)
end)
```

```lua
server.Registry:RegisterCommandsIn(game.ReplicatedStorage.Commands)   -- server Script
client.Registry:RegisterCommandsIn(game.ReplicatedStorage.Commands)   -- client LocalScript
```

## Arguments

`Args` is an ordered list of single-key tables, `{ name = constructor(Type, options?) }`. The key becomes the field
of `args` and the argument's name in help, signatures and `--name=value`.

| Constructor | In `args` | Notes |
|---|---|---|
| `RoShell.Arg(T)` | `T` | Required |
| `RoShell.Optional(T)` | `T?` | |
| `RoShell.Default(T, value)` | `T` | `value` is a value of `T` or the text a player would type (`"me"`, `"5m"`) |
| `RoShell.DefaultFn(T, fn, display)` | `T` | Computed per run from the request (executor, platform…) |
| `RoShell.Rest(T)` | `{ T }` | Collects every remaining word |
| `RoShell.Flag()` | `boolean` | `--name` / `-n` |
| `RoShell.Dynamic(resolve)` | `unknown` | Type chosen at run time from earlier arguments |

Options (second argument of every constructor): `Description`, `Short` (`-n`), `Named` (only `--name value` /
`name=value`), `Hidden`, `Examples`, `Validate`, `RequireConfirmAbove` (lists: confirm when more targets),
`AllowEmpty`, `Pipe` (receives piped input).

Optional arguments may come before required ones. When there are fewer words than arguments, an optional argument
whose type does not accept the word (but the next argument's does) keeps its default: with
`give [targets = me] <item> [amount = 1]`, `give sword 3` gives three swords to you, while `give Bob sword` still
binds `Bob` to `targets`.

## Replies

Return a string, a reply from `ctx`, or nothing:

```lua
ctx:Reply("plain line")                           -- shown immediately
return ctx:Success("Done")                        -- also Info / Warn / Error (Error fails `&&` chains)
return ctx:Table({ Columns = { "Name", "Score" }, Rows = rows })
return ctx:List({ "a", "b" }, "Title")
return ctx:KeyValue({ { Key = "Health", Value = "100" } })
ctx:Color(Color3.new(1, 0, 0), "red")
ctx:Progress({ Label = "Saving", Fraction = 0.4 })   -- updates in place
return ctx:Value(RoShell.Types.Players, list)     -- typed value for pipes, `$$` and embeds
```

## More of the command definition

```lua
RoShell.Command({
	Name = "wipe",
	Description = "Deletes a player's data",
	Group = "Admin",
	Destructive = true,          -- always asks for confirmation (skip with --yes)
	SupportsDryRun = true,       -- `wipe Bob --dry` shows :Preview() instead of running
	Cooldown = 5,                -- seconds between two runs by the same player
	RateLimit = { Count = 10, Per = 60 },
	Timeout = 30,                -- cancelled after 30 s (0 disables)
	Returns = RoShell.Types.Players,   -- enables pipe type checks
	Args = { { target = RoShell.Arg(RoShell.Types.Player) } },
})
	:Validate(function(ctx, args) return args.target ~= ctx.Executor, "Not yourself" end)
	:Preview(function(ctx, args) return { `Would wipe {args.target.Name}` } end)
	:Run(function(ctx, args)
		ctx:Undoable({ Description = "wipe", Undo = function() --[[ restore ]] end })
		return ctx:Success("Wiped")
	end)
```

- `:ClientRun(fn)` runs on the player's machine. Returning `nil` continues on the server if `:Run` exists.
- `:Data(fn)` runs on the client first and ships its result to the server (`ctx:GetData()`).
- `Subcommands = { … }` builds `ban add|remove|list` style trees ([example](../../examples/03-Subcommands.luau)).
- Long-running handlers should call `ctx:CheckCancelled()` in loops; Ctrl+C or `cancel` stops them.
- `ctx:Confirm`, `ctx:Choose` and `ctx:Input` ask the player (server commands included) and yield for the answer.

## Running commands from code

```lua
server:Run("kick Bob --reason AFK")         -- as the server console (always permitted)
server:Run("heal me", player)              -- as a player (permissions apply)
client:Run("theme Mocha")                  -- on the client, no echo
```
