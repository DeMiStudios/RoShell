# Custom types in 60 seconds

A type turns the text a player typed into a value, suggests completions, and (for enumerable types) supports every
operator: `*`, `~fuzzy`, globs, lists, set arithmetic. The value type is inferred, so commands using your type get
precise `args` with no annotations.

## A fixed set of words — `Type.Choice` (4 lines)

```lua
local Rarity = RoShell.Type.Choice<<"common" | "rare" | "epic">>({
	Name = "rarity",
	Choices = { "common", "rare", "epic" },
})
-- args.rarity: "common" | "rare" | "epic"
```

The explicit `<<…>>` names the literal union (Luau does not infer literal unions from table literals).
`Descriptions` and `Aliases` (keyed by choice) are optional.

## Words mapped to values — `Type.Map` (6 lines)

```lua
local Difficulty = RoShell.Type.Map({
	Name = "difficulty",
	Entries = {
		{ Key = "easy", Value = 0.5 }, { Key = "normal", Value = 1 }, { Key = "hard", Value = 2, Aliases = { "h" } },
	},
})
-- args.difficulty: number
```

Entries also take `Description` (shown in the suggestion footer) and `Detail` (right-aligned in the list).

## Candidates computed at run time — `Type.Dynamic` (6 lines)

```lua
local Zone = RoShell.Type.Dynamic({
	Name = "zone",
	CacheSeconds = 5,
	Candidates = function()
		local list = {}
		for _, part in workspace.Zones:GetChildren() do table.insert(list, { Key = part.Name, Value = part }) end
		return list
	end,
})
-- args.zone: Instance;   Zone.Invalidate() drops the cache
```

`Candidates` receives the request (executor, platform), so the list can depend on who is asking.

## Anything else — `Type.Custom` (≤ 15 lines)

```lua
local Hex = RoShell.Type.Custom({
	Name = "hex",
	Description = "A hexadecimal number",
	Examples = { "ff", "0x1A" },
	Parse = function(request)
		local digits = request.Text:gsub("^0x", "")
		local value = tonumber(digits, 16)
		if value == nil then
			return { Ok = false, Error = "Expected a hexadecimal number", Span = request.Span }
		end
		return { Ok = true, Value = value, Display = `0x{string.format("%X", value)}` }
	end,
	Suggestions = { "ff", "7f", "0x10" },
})
```

## Composing types

| Constructor | Value | Example input |
|---|---|---|
| `Type.List(T)` | `{ T }` | `a,b,c`, operators for enumerable `T` |
| `Type.Optional(T)` | `T?` | |
| `Type.Union({ Members = { A, B } })` | `A \| B` | first member that parses wins (best error otherwise) |
| `Type.Tuple({ Members = { { count = A }, { item = B } } })` | `{ count: A, item: B }` | `3:sword` or `"3 sword"` |
| `Type.Struct({ Fields = { x = A, y = B } })` | `{ x: A, y: B }` | `x=1,y=2` |
| `Type.Transform({ From = A, To = fn })` | result of `fn` | |
| `Type.Refine(A, check, name)` | `A` | adds a check |
| `Type.Number({ Min, Max, Integer, Suffix })`, `Type.Integer`, `Type.String({ Pattern, MinLength, MaxLength })`, `Type.Boolean`, `Type.Range`, `Type.Pattern` | | |
| `Type.Enumerable({ Candidates, Selectors, Default })` | | full control over an enumerable type |
| `Type.FromEnum({ Enum = Enum.Material })` | `Enum.Material` items | `Neon`, `~gras` |

## Registering

Types work without registration. Register shared ones so `help <type>`, `types`, `resolve <type> …` and pipe
checks know them by name:

```lua
registry:RegisterType(Rarity)          -- or RegisterTypes({ … })
```

Prefix selectors extend existing types: `registry:RegisterSelector(RoShell.Types.Players, { Prefix = "@",
Name = "role", Resolve = … })` makes `@role:Moderator` resolve to players. Built-in types are listed in the
[reference](../Reference.md#types).
