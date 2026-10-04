# Permissions

RoShell is **default deny**: a player may run a command only when a permission rule grants it. The rule that
applies is the command's own `Permissions`, else its parent command's (for subcommands), else the rule mapped to
its `Group`. Commands run from the server console (`server:Run(text)` with no player) are always allowed. In Studio
everything is allowed unless you create the server with `StudioBypass = false`.

The quickest setup names the admins, who may run every command:

```lua
RoShell.Server.new({ Admins = { 156, 1234 } }):Start()                          -- user ids
RoShell.Server.new({ Admins = { 156, RoShell.Permissions.Group(1234567, 250) } }):Start()   -- ids and rules
server.Permissions:SetAdmins(RoShell.Permissions.Role("Admin"))                  -- the same from code
```

Everyone else gets what each command's rule allows. For finer control:

```lua
local P = RoShell.Permissions

-- Per group. Built-in Help and Utility commands are open to everyone; Admin, Debug and Schedule need a rule.
server.Permissions:SetGroup("Admin", P.Users({ 156, 1234 }))
server.Permissions:SetGroup("Fun", P.Everyone())

-- Roles: name a rule once, reuse it.
server.Permissions:DefineRole("Moderator", P.Group(1234567, 100))      -- rank 100+ in group 1234567
server.Permissions:DefineRole("Admin", P.Any({ P.Group(1234567, 250), P.Users({ 156 }) }))
server.Permissions:SetGroup("Admin", P.Role("Admin"))
server.Permissions:SetGroup("Schedule", P.Role("Moderator"))

-- Per command (overrides the group).
RoShell.Command({
	Name = "vip-room",
	Permissions = P.Allow({ Gamepass = 987654, Roles = { "Moderator" } }),
	Args = {},
})
```

## Rules

| Rule | Grants |
|---|---|
| `Everyone()` / `Nobody()` | everyone / no one |
| `Users({ userId, … })` | listed users |
| `Group(groupId, minimumRank?)` | group members (at or above the rank) |
| `Gamepass(id)`, `Badge(id)` | owners of the game pass / badge |
| `Role(name)` | whatever the role was defined as (`DefineRole`) |
| `Studio()` | only while running in Studio |
| `Predicate(fn(player, command, args?), description?)` | custom logic; `args` is present right before execution |
| `Any({ … })`, `All({ … })`, `Not(rule)` | combinations |
| `Allow({ Everyone, Users, Group, Groups, Role, Roles, Gamepass, Badge, Studio, Predicate })` | any of the listed rules |

Group rank, game pass and badge checks need web calls; their results are cached per player for a minute and only
evaluated where yielding is allowed (right before execution and when building a player's visibility list).

## What players see

When a client connects, the server sends the names of the commands that player may see; only those are suggested,
listed by `help`/`commands` and shown in the palette. The list is refreshed when permissions change
(`server:RefreshVisibility(player?)`). Hidden commands are never sent. Visibility is a convenience — the server
checks permissions again before parsing arguments and once more, with the parsed arguments, before running.

## Limits

- `Cooldown = seconds` on a command: per player.
- `RateLimit = { Count, Per, Scope = "player" | "global" }` on a command.
- Network rate limit for all requests from a player: `RoShell.Server.new({ RateLimit = { Burst = 20, PerSecond = 6 } })`.
- `RequireConfirmAbove` on list arguments and `Destructive = true` on commands ask before acting.
