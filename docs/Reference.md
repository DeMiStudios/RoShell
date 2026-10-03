# RoShell command reference

Generated for version 0.1.0.

## Admin

### `announce`

Shows a message to everyone (every server with --global)

```
announce <message: string> [--global]
```

Aliases: m, broadcast

| Argument | Type | Required | Description |
|---|---|---|---|
| `message` | string | yes |  |
| `--global` | flag | no | Send to every server (default: false) |

Examples:

- `announce Loot dropped!`
- `announce Restarting soon --global`

### `bring`

Brings players to you (undoable)

```
bring <targets: players>
```

| Argument | Type | Required | Description |
|---|---|---|---|
| `targets` | players | yes |  |

### `freeze`

Freezes players in place

```
freeze <targets: players>
```

| Argument | Type | Required | Description |
|---|---|---|---|
| `targets` | players | yes |  |

### `heal`

Restores players' health

```
heal [targets: players = you]
```

| Argument | Type | Required | Description |
|---|---|---|---|
| `targets` | players | no |  (default: you) |

### `kick`

Kicks players from the server

```
kick <targets: players> [reason: string = Kicked by a moderator]
```

| Argument | Type | Required | Description |
|---|---|---|---|
| `targets` | players | yes |  |
| `reason` | string | no |  (default: Kicked by a moderator) |

Examples:

- `kick Bob`
- `kick *-Bob --reason "AFK"`

### `kill`

Kills players' characters

```
kill <targets: players>
```

| Argument | Type | Required | Description |
|---|---|---|---|
| `targets` | players | yes |  |

### `respawn`

Respawns players

```
respawn [targets: players = you]
```

Aliases: re, refresh

| Argument | Type | Required | Description |
|---|---|---|---|
| `targets` | players | no |  (default: you) |

### `shutdown`

Kicks everyone and closes the server, after an optional countdown

```
shutdown [reason: string = The server is restarting] [--delay <duration>]
```

| Argument | Type | Required | Description |
|---|---|---|---|
| `reason` | string | no | Shown to everyone (default: The server is restarting) |
| `--delay` | duration | no | Countdown first (default: 0) |

Examples:

- `shutdown`
- `shutdown "Updating!" --delay 30s`
- `in 5m shutdown`

### `speed`

Sets walk speed; several values (or a range) are assigned in turn (undoable)

```
speed <targets: players> <speeds: numbers>
```

Aliases: setspeed, walkspeed

| Argument | Type | Required | Description |
|---|---|---|---|
| `targets` | players | yes |  |
| `speeds` | numbers | yes | Speed(s): 16, 16,24 or 16..32/8 |

Examples:

- `speed . 32`
- `setspeed Bo* 16..32/8`

### `teleport`

Teleports players to another player (undoable)

```
teleport <targets: players> <destination: player>
```

Aliases: tp

| Argument | Type | Required | Description |
|---|---|---|---|
| `targets` | players | yes |  |
| `destination` | player | yes |  |

Examples:

- `tp Bob Alice`
- `tp * .`
- `tp %Red ${players ?}`

### `thaw`

Unfreezes players

```
thaw <targets: players>
```

Aliases: unfreeze

| Argument | Type | Required | Description |
|---|---|---|---|
| `targets` | players | yes |  |

### `to`

Teleports you to a player (undoable)

```
to <target: player>
```

Aliases: goto

| Argument | Type | Required | Description |
|---|---|---|---|
| `target` | player | yes |  |

## Debug

### `audit`

Shows the most recent commands run on this server

```
audit [count: integer = 20]
```

| Argument | Type | Required | Description |
|---|---|---|---|
| `count` | integer | no |  (default: 20) |

### `blink`

Teleports you to where your mouse points

```
blink
```

Aliases: b

### `inspect`

Shows an instance's properties, attributes and tags; sets a property or attribute (undoable)

```
inspect <instance: instance> [property: property] [value: value]
```

| Argument | Type | Required | Description |
|---|---|---|---|
| `instance` | instance | yes |  |
| `property` | property | no |  |
| `value` | value | no | New value (typed from the property) |

Examples:

- `inspect workspace.Baseplate`
- `inspect workspace.Baseplate Transparency 0.5`
- `inspect . Health`

### `position`

Returns your position

```
position
```

Aliases: pos

### `reload`

Hot-reloads commands registered with RegisterCommandsIn (client and server)

```
reload
```

### `tag`

Adds a CollectionService tag to instances (undoable)

```
tag <instances: instances> <name: tag>
```

| Argument | Type | Required | Description |
|---|---|---|---|
| `instances` | instances | yes |  |
| `name` | tag | yes |  |

### `tags`

Lists the CollectionService tags of an instance, or every tag in use

```
tags [instance: instance]
```

| Argument | Type | Required | Description |
|---|---|---|---|
| `instance` | instance | no |  |

### `untag`

Removes a CollectionService tag from instances

```
untag <instances: instances> <name: tag>
```

| Argument | Type | Required | Description |
|---|---|---|---|
| `instances` | instances | yes |  |
| `name` | tag | yes |  |

## Help

### `commands`

Lists the commands you can run, optionally filtered

```
commands [filter: string]
```

Aliases: cmds

| Argument | Type | Required | Description |
|---|---|---|---|
| `filter` | string | no | Fuzzy filter |

### `help`

Lists commands, or explains a command, type or topic

```
help [subject: subject]
```

Aliases: ?, man

| Argument | Type | Required | Description |
|---|---|---|---|
| `subject` | subject | no | A command, a type, or a topic |

Examples:

- `help`
- `help give`
- `help players`
- `help operators`

### `operators`

Explains wildcards, selectors, set arithmetic and the input language

```
operators
```

### `types`

Lists every argument type with an example

```
types
```

## Schedule

### `cancel`

Cancels a scheduled command (or all of yours with 'all')

```
cancel <id: job>
```

| Argument | Type | Required | Description |
|---|---|---|---|
| `id` | job | yes |  |

### `every`

Runs a command line repeatedly

```
every <interval: duration> <...script: string> [--times <integer>]
```

| Argument | Type | Required | Description |
|---|---|---|---|
| `interval` | duration | yes |  |
| `script` | string | no |  |
| `--times` | integer | no |  |

Examples:

- `every 1m announce Hydrate!`
- `every 10s heal * --times 6`

### `in`

Runs a command line after a delay

```
in <delay: duration> <...script: string>
```

Aliases: after

| Argument | Type | Required | Description |
|---|---|---|---|
| `delay` | duration | yes |  |
| `script` | string | no |  |

Examples:

- `in 5m announce Restarting`
- `in 30s kick Bob`

### `repeat`

Runs a command line several times now (stops at the first failure)

```
repeat <count: integer> <...script: string> [--interval <duration>]
```

| Argument | Type | Required | Description |
|---|---|---|---|
| `count` | integer | yes |  |
| `script` | string | no |  |
| `--interval` | duration | no |  (default: 0) |

Examples:

- `repeat 3 echo hi`
- `repeat 5 spawnloot rare --interval 1s`

### `run-script`

Runs a stored script (a ModuleScript returning text, or a StringValue)

```
run-script <script: script>
```

Aliases: script

| Argument | Type | Required | Description |
|---|---|---|---|
| `script` | script | yes |  |

### `schedules`

Lists your scheduled commands

```
schedules
```

Aliases: jobs

## Utility

### `alias`

Defines a command alias/macro; $1..$9 and $@ are replaced by its words

```
alias <name: string> <...body: string>
```

| Argument | Type | Required | Description |
|---|---|---|---|
| `name` | string | yes | The alias name |
| `body` | string | no | The command line it runs |

Examples:

- `alias gg = "announce GG $1"`
- `alias heal-all "heal *"`

### `aliases`

Lists your aliases

```
aliases
```

### `bind`

Binds a key (with modifiers) to a command line

```
bind <key: keybind> <...script: string>
```

| Argument | Type | Required | Description |
|---|---|---|---|
| `key` | keybind | yes |  |
| `script` | string | no |  |

Examples:

- `bind F5 respawn .`
- `bind Ctrl+Shift+H heal .`

### `binds`

Lists your key bindings

```
binds
```

### `clear`

Clears the console (Ctrl+L)

```
clear
```

Aliases: cls

### `config`

Shows or changes console settings

```
config [key: setting] [value: string]
```

Aliases: settings

| Argument | Type | Required | Description |
|---|---|---|---|
| `key` | setting | no |  |
| `value` | string | no |  |

Examples:

- `config`
- `config density compact`
- `config reduceMotion true`

### `echo`

Prints text (and passes it on through pipes)

```
echo <...text: string>
```

Aliases: print

| Argument | Type | Required | Description |
|---|---|---|---|
| `text` | string | no | Text to print |

Examples:

- `echo "Hello, world"`
- `echo $$`

### `export-log`

Exports the console log as text you can copy

```
export-log
```

### `get`

Gets a variable

```
get <name: variable>
```

| Argument | Type | Required | Description |
|---|---|---|---|
| `name` | variable | yes |  |

### `hide`

Hides the console

```
hide
```

### `history`

Shows your command history, or returns one entry (negative counts from the end)

```
history [line: integer]
```

| Argument | Type | Required | Description |
|---|---|---|---|
| `line` | integer | no |  |

Examples:

- `history`
- `history -1`
- `run ${history -2}`

### `len`

Length of a text (characters), or number of items piped in

```
len <...text: string>
```

| Argument | Type | Required | Description |
|---|---|---|---|
| `text` | string | no |  |

### `math`

Evaluates an arithmetic expression

```
math <...expression: string>
```

Aliases: calc, =

| Argument | Type | Required | Description |
|---|---|---|---|
| `expression` | string | no | e.g. (2 + 3) * 4, sqrt(16), pi * 2 |

Examples:

- `math (2 + 3) * 4`
- `math sqrt(2) ^ 2`
- `math max(1, $$)`

### `palette`

Opens the command palette (Ctrl+K)

```
palette
```

### `players`

Lists (and returns) players, optionally filtered by a team

```
players [filter: players = {}] [--team <team>]
```

| Argument | Type | Required | Description |
|---|---|---|---|
| `filter` | players | no | Defaults to everyone (default: {}) |
| `--team` | team | no |  |

Examples:

- `players`
- `players --team Red | kick`

### `random`

A random integer between min and max

```
random [min: integer = 1] [max: integer = 100]
```

Aliases: rand

| Argument | Type | Required | Description |
|---|---|---|---|
| `min` | integer | no |  (default: 1) |
| `max` | integer | no |  (default: 100) |

### `redo`

Redoes your last undone command

```
redo
```

### `replace`

Replaces every match of a Luau pattern (or plain text with --plain)

```
replace <text: string> <pattern: string> [replacement: string = ] [--plain]
```

| Argument | Type | Required | Description |
|---|---|---|---|
| `text` | string | yes |  |
| `pattern` | string | yes |  |
| `replacement` | string | no |  (default: ) |
| `--plain` | flag | no | Treat the pattern as plain text (default: false) |

### `resolve`

Shows what a value (wildcards included) resolves to for a type

```
resolve <type: type> [value: value]
```

| Argument | Type | Required | Description |
|---|---|---|---|
| `type` | type | yes |  |
| `value` | value | no | A value of that type |

Examples:

- `resolve players *-Bob`
- `resolve color3 hsv(200,80,100)`

### `run`

Runs a command line (useful with variables and aliases)

```
run <...script: string>
```

| Argument | Type | Required | Description |
|---|---|---|---|
| `script` | string | no | The command line to run |

Examples:

- `run "echo hi && echo there"`

### `runif`

Runs a command line only when a condition holds

```
runif <condition: condition> <left: string> <right: string> <...script: string>
```

| Argument | Type | Required | Description |
|---|---|---|---|
| `condition` | condition | yes |  |
| `left` | string | yes |  |
| `right` | string | yes |  |
| `script` | string | no |  |

Examples:

- `runif equals $$ yes echo confirmed`
- `runif greater ${random} 50 echo high`

### `set`

Sets a variable ($name)

```
set <name: variable> <...value: string>
```

| Argument | Type | Required | Description |
|---|---|---|---|
| `name` | variable | yes |  |
| `value` | string | no |  |

Examples:

- `set target Bob`
- `kick $target`

### `theme`

Lists themes, or switches theme

```
theme [name: theme]
```

| Argument | Type | Required | Description |
|---|---|---|---|
| `name` | theme | no |  |

Examples:

- `theme`
- `theme Graphite`
- `theme Light`

### `unalias`

Removes an alias

```
unalias <name: command>
```

| Argument | Type | Required | Description |
|---|---|---|---|
| `name` | command | yes |  |

### `unbind`

Removes a key binding

```
unbind <key: keybind>
```

| Argument | Type | Required | Description |
|---|---|---|---|
| `key` | keybind | yes |  |

### `undo`

Undoes your last undoable command

```
undo
```

### `unset`

Removes a variable

```
unset <name: variable>
```

| Argument | Type | Required | Description |
|---|---|---|---|
| `name` | variable | yes |  |

### `uptime`

How long this server has been running

```
uptime
```

### `vars`

Lists your variables

```
vars
```

### `version`

Shows the RoShell version

```
version
```

### `wait`

Waits before continuing (useful in scripts and chains)

```
wait <duration: duration>
```

Aliases: sleep

| Argument | Type | Required | Description |
|---|---|---|---|
| `duration` | duration | yes |  |

## Types

| Type | Kind | Lists | Description |
|---|---|---|---|
| `asset` | custom | no | An asset id (123, rbxassetid://123 or a creator store URL) |
| `attribute` | string | no | An attribute name |
| `boolean` | boolean | no | true or false (also yes/no, on/off, 1/0) |
| `brickColor` | enumerable | no | A BrickColor name |
| `brickColors` | list | yes | One or more brickColors |
| `class` | enumerable | no | A ClassName |
| `color3` | custom | no | A color: #ff8800, 255,128,0, rgb(255,128,0), hsv(30,100,100), or a name |
| `color3s` | list | yes | One or more color3s |
| `colorHex` | custom | no | A hex color: #ff8800 or #f80 |
| `command` | enumerable | no | A command name or alias |
| `commands` | list | yes | One or more commands |
| `duration` | custom | no | A duration: 30s, 5m, 1h30m, 2d, 1.5h or 1:30 |
| `durations` | list | yes | One or more durations |
| `instance` | custom | no | An instance path: workspace.Map.Door, Workspace["New Map"].Door, or . for your character |
| `instances` | custom | no | Instance paths; the last segment may be * (children), ** (descendants) or a glob |
| `integer` | number | no | A whole number |
| `integers` | list | yes | One or more integers |
| `json` | custom | no | A JSON value |
| `keybind` | custom | no | A key with optional modifiers: F5, Ctrl+Shift+K, MouseButton2, ButtonX |
| `keycode` | enumerable | no | A value of the keycode enum |
| `material` | enumerable | no | A value of the material enum |
| `number` | number | no | A number |
| `numbers` | list | yes | One or more numbers |
| `pattern` | custom | no | A Luau string pattern |
| `percent` | number | no | 0-100 (a % sign is optional) |
| `player` | enumerable | no | A player in this server (name or display name) |
| `players` | list | yes | One or more players: names, *, **, ., ?3, %Team, #Tag, globs and set arithmetic |
| `range` | range | no | A range such as 1..10, ..5, 5.. or 1..10/2 |
| `remote` | enumerable | no | A RemoteEvent or RemoteFunction |
| `string` | string | no | Any text |
| `strings` | list | yes | One or more strings |
| `tag` | custom | no | A CollectionService tag (existing tags are suggested) |
| `team` | enumerable | no | A team |
| `teamPlayers` | transform | no | The players on a team |
| `teams` | list | yes | One or more teams |
| `timestamp` | custom | no | A point in time: now, in 5m, 2h ago, today, tomorrow, 2026-10-03, 2026-10-03T12:30 |
| `type` | enumerable | no | A registered type |
| `url` | custom | no | An http(s) URL |
| `userId` | custom | no | A user id, an online player's name, or any username |
| `userIds` | list | yes | One or more userIds |
| `variable` | custom | no | A variable name (set with `set`) |
| `vector2` | custom | no | A 2D vector: x,y |
| `vector2s` | list | yes | One or more vector2s |
| `vector3` | custom | no | A position: x,y,z (or . / here for your position) |
| `vector3s` | list | yes | One or more vector3s |

## Functions

| Function | Description |
|---|---|
| `$date()` | The current UTC date and time: $date() or $date(%Y-%m-%d) |
| `$len()` | Number of characters: $len(hello) |
| `$lower()` | Lowercases text: $lower(HELLO) |
| `$me()` | Your name |
| `$pick()` | One of the arguments at random: $pick(red, green, blue) |
| `$random()` | A random integer: $random(max) or $random(min, max) |
| `$round()` | Rounds a number: $round(2.5) or $round(3.14159, 2) |
| `$time()` | The current Unix time in seconds |
| `$upper()` | Uppercases text: $upper(hello) |

