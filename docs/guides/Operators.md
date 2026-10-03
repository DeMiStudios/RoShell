# Operators and wildcards

Every *enumerable* argument type (players, teams, items, enums, instances, and your own `Type.Choice`,
`Type.Map`, `Type.Dynamic` and `Type.Enumerable` types) understands the same operators. The full table is in the
[grammar](../GRAMMAR.md#operators-and-wildcards); this page shows them in action.

```
kick Bob                 exact name (then prefix, then fuzzy: "kick bo" finds Bob)
bring .                  yourself (also: me)
heal *                   everyone
kill **                  everyone but you
tp ? .                   a random player to you
kick ?3                  three random players
give ~swrd               fuzzy: the best match ("Sword of Embers")
kick Guest*              glob (also ? and [a-m] classes)
heal %Red                players on team Red
freeze #Boss             players tagged "Boss" (player or character)
heal Bob,Alice           list
heal %Red+%Blue          union
kick *-Bob               difference
heal %Red&%Admins        intersection (binds tighter than + - ,)
kill !%Red               complement
kick (*-%Red)&Guest*     grouping
setspeed Bo* 16..32/8    numeric range with a step: 16, 24, 32
```

Rules:

- **Exact names win.** A word that exactly names a candidate is taken literally, so an item called
  `sword-of-embers` is not read as a difference.
- **Quoting disables operators.** `kick "*"` looks for a player literally named `*`.
- **Single values vs lists.** `*`, `**` and `?N` only make sense for list arguments; in a single-value argument
  they are rejected with an explanation. `~fuzzy` picks the best match for a single value and every strong match
  for a list.
- **Order is stable.** Results keep the candidate enumeration order (players in join order), except `?`.
- **Previews.** While you type, the console shows what the argument resolves to (`→ 7 players`); click the chip
  to list them. `resolve players *-Bob` prints the same in the log.
- **Confirmation.** Arguments with `RequireConfirmAbove = N` ask before acting on more than `N` targets
  (`kick *` with the default `kick` command asks first). `--yes` skips the question.

## Making your own types support operators

Build them with an enumerable constructor and they get every operator for free:

```lua
local Pet = RoShell.Type.Map({ Name = "pet", Entries = { { Key = "cat", Value = cat }, { Key = "dog", Value = dog } } })
local Pets = RoShell.Type.List(Pet, { Name = "pets" })   -- `feed *`, `feed ~ca,dog`, `feed *-cat`
```

Prefix selectors add new `%`-style forms to an existing type:

```lua
registry:RegisterSelector(RoShell.Types.Players, {
	Prefix = "@",
	Name = "rank",
	Description = "Players with at least this group rank",
	Example = "@rank:200",
	Resolve = function(request)
		local minimum = tonumber(request.Text:match("^rank:(%d+)$"))
		if minimum == nil then
			return { Ok = false, Error = "Expected @rank:<number>", Span = request.Span }
		end
		local found = {}
		for _, player in request.Platform.GetPlayers() do
			if player:GetRankInGroup(1234567) >= minimum then table.insert(found, player) end
		end
		return { Ok = true, Value = found }
	end,
})
```
