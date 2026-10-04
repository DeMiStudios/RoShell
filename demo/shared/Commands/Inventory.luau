--!strict
--[[
	Demo: an attribute-backed inventory. `inventory` renders a table.

	Two ways to write the same idea:
	- `giveitem` is the simple form: players, one item, one amount.
	- `give` takes lists everywhere: several players, several items, and either one amount for all of them or
	  one per item. A cross-argument check (`:Validate`) rejects amounts that do not line up with the items,
	  before anything happens (also for `--dry` previews). Both are undoable.

		giveitem me ~embers 3
		give me,Bob ~embers,~aegis 2          two of each to two players
		give %Red ~embers,~healing 1,5        one sword and five potions to team Red
		give * *Sword --dry                   preview every sword for everyone
		inventory Bob
]]

--// Imports
const DemoTypes = require("../DemoTypes")
const Items = require("../Items")
const RoShell = require(game:GetService("ReplicatedStorage").RoShell)

--// Helpers

const function attributeOf(item: Items.Item): string
	return "Item_" .. item.Id
end

const function countOf(player: Player, item: Items.Item): number
	const value = player:GetAttribute(attributeOf(item))
	return if type(value) == "number" then value else 0
end

const function setCount(player: Player, item: Items.Item, count: number)
	player:SetAttribute(attributeOf(item), if count > 0 then count else nil)
end

const function names(players: { Player }): string
	if #players == 1 then
		return players[1].Name
	end
	return `{#players} players`
end

--- The amount of each item: one amount for all of them, or one per item in order.
const function amountsFor(items: { Items.Item }, amounts: { number }): ({ number }?, string?)
	if #amounts == 1 then
		return table.create(#items, amounts[1]), nil
	elseif #amounts == #items then
		return amounts, nil
	end
	const counted = if #items == 1 then "1 item" else `{#items} items`
	return nil, `{#amounts} amounts for {counted}: give one amount for everything, or one per item`
end

--- `2× Sword of Embers, 5× Healing Potion` (the first few).
const function describe(items: { Items.Item }, amounts: { number }): string
	const parts: { string } = {}
	for index, item in items do
		if index > 3 then
			table.insert(parts, `{#items - 3} more`)
			break
		end
		table.insert(parts, `{amounts[index]}× {item.Name}`)
	end
	return table.concat(parts, ", ")
end

type Change = {
	Player: Player,
	Item: Items.Item,
	Before: number,
	Amount: number,
}

--// Commands
const give = RoShell.Command({
	Name = "give",
	Icon = "cube",
	Description = "Gives items to players: several players, several items, an amount for each",
	Group = "Demo",
	SupportsDryRun = true,
	Examples = {
		{ Text = "give me ~embers", Description = "One item (fuzzy match), one of it" },
		{ Text = "give me,Bob ~embers,~aegis 2", Description = "Two of each item to both players" },
		{ Text = "give %Red ~embers,~healing 1,5", Description = "One sword and five potions to team Red" },
		{ Text = "give * *Sword --dry", Description = "Preview every sword for everyone" },
	},
	Args = {
		{ targets = RoShell.Arg(RoShell.Types.Players, { Description = "Who receives the items" }) },
		{ items = RoShell.Arg(DemoTypes.Items, { Description = "What to give: one item, or several (a,b)" }) },
		{
			amounts = RoShell.Default(DemoTypes.Amounts, "1", {
				Description = "How many: one amount for every item, or one per item (1,5)",
			}),
		},
	},
}):Validate(function(_ctx, args)
	const _, problem = amountsFor(args.items, args.amounts)
	return problem == nil, problem
end):Preview(function(_ctx, args)
	const amounts: { number } = amountsFor(args.items, args.amounts) or {}
	const lines: { string } = {}
	for _, player in args.targets do
		for index, item in args.items do
			const current = countOf(player, item)
			table.insert(lines, `{player.Name}: {item.Name} {current} → {current + amounts[index]}`)
		end
	end
	return lines
end):Run(function(ctx, args)
	const amounts: { number } = amountsFor(args.items, args.amounts) or {}
	const changes: { Change } = {}
	for _, player in args.targets do
		for index, item in args.items do
			const before = countOf(player, item)
			table.insert(changes, { Player = player, Item = item, Before = before, Amount = amounts[index] })
			setCount(player, item, before + amounts[index])
		end
	end
	const summary = describe(args.items, amounts)
	ctx:Undoable({
		Description = `give {summary}`,
		Undo = function()
			for _, change in changes do
				setCount(change.Player, change.Item, change.Before)
			end
		end,
		Redo = function()
			for _, change in changes do
				setCount(change.Player, change.Item, change.Before + change.Amount)
			end
		end,
	})
	return ctx:Success(`Gave {summary} to {names(args.targets)}`)
end)

-- The simple form: one item, one amount.
const giveitem = RoShell.Command({
	Name = "giveitem",
	Icon = "diamond-gem",
	Description = "Gives one item to players (the simple form of give)",
	Group = "Demo",
	SupportsDryRun = true,
	Examples = {
		{ Text = "giveitem me ~embers 3", Description = "Fuzzy item match" },
		{ Text = 'giveitem %Red,-Bob "Healing Potion" 5', Description = "Team Red except Bob" },
		{ Text = "giveitem * Aegis --dry", Description = "Preview without giving" },
	},
	Args = {
		{ targets = RoShell.Arg(RoShell.Types.Players, { Description = "Who receives the item" }) },
		{ item = RoShell.Arg(DemoTypes.Item, { Description = "What to give" }) },
		{ amount = RoShell.Default(RoShell.Types.Integer, 1, { Description = "How many of it" }) },
	},
}):Preview(function(_ctx, args)
	const lines: { string } = {}
	for _, player in args.targets do
		const current = countOf(player, args.item)
		table.insert(lines, `{player.Name}: {args.item.Name} {current} → {current + args.amount}`)
	end
	return lines
end):Run(function(ctx, args)
	const before: { [Player]: number } = {}
	for _, player in args.targets do
		before[player] = countOf(player, args.item)
		setCount(player, args.item, before[player] + args.amount)
	end
	ctx:Undoable({
		Description = `give {args.item.Name}`,
		Undo = function()
			for player, count in before do
				setCount(player, args.item, count)
			end
		end,
		Redo = function()
			for player, count in before do
				setCount(player, args.item, count + args.amount)
			end
		end,
	})
	return ctx:Success(`Gave {args.amount}× {args.item.Name} to {names(args.targets)}`)
end)

const take = RoShell.Command({
	Name = "take",
	Icon = "backpack",
	Description = "Removes items from players",
	Group = "Demo",
	Args = {
		{ targets = RoShell.Arg(RoShell.Types.Players) },
		{ item = RoShell.Arg(DemoTypes.Item) },
		{ amount = RoShell.Default(RoShell.Types.Integer, 1) },
	},
}):Run(function(ctx, args)
	local removed = 0
	for _, player in args.targets do
		const current = countOf(player, args.item)
		const taken = math.min(current, args.amount)
		removed += taken
		setCount(player, args.item, current - taken)
	end
	if removed == 0 then
		return ctx:Warn(`Nobody had any {args.item.Name}`)
	end
	return ctx:Success(`Took {removed}× {args.item.Name} from {names(args.targets)}`)
end)

const inventory = RoShell.Command({
	Name = "inventory",
	Icon = "backpack",
	Aliases = { "inv" },
	Description = "Shows a player's items",
	Group = "Demo",
	Args = {
		{ player = RoShell.Optional(RoShell.Types.Player, { Description = "Whose inventory (default: you)" }) },
	},
}):Run(function(ctx, args)
	const player = args.player or ctx.Executor
	if player == nil then
		return ctx:Error("Specify a player when running from the server console")
	end
	const rows: { { string } } = {}
	for _, item in Items.List do
		const count = countOf(player, item)
		if count > 0 then
			table.insert(rows, { item.Name, item.Rarity, tostring(count) })
		end
	end
	if #rows == 0 then
		return ctx:Info(`{player.Name} has no items yet — try \`give me ~embers\``)
	end
	return ctx:Table({ Title = `{player.Name}'s inventory`, Columns = { "Item", "Rarity", "Count" }, Rows = rows })
end)

const items = RoShell.Command({
	Name = "items",
	Icon = "grid",
	Description = "Lists the loot table",
	Group = "Demo",
	Args = {
		{ rarity = RoShell.Optional(DemoTypes.Rarity, { Description = "Only this rarity" }) },
	},
}):Run(function(ctx, args)
	const rows: { { string } } = {}
	for _, item in Items.List do
		if args.rarity == nil or item.Rarity == args.rarity then
			table.insert(rows, { item.Name, item.Rarity, item.Description })
		end
	end
	return ctx:Table({ Columns = { "Item", "Rarity", "Description" }, Rows = rows })
end)

return { give, giveitem, take, inventory, items }
