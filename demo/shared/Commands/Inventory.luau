--!strict
--[[
	Demo: an attribute-backed inventory. `give` and `take` are undoable; `inventory` renders a table.

		give me ~embers 3
		give %Red,-Bob "Healing Potion" 5
		give * Aegis --dry
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

--// Commands
const give = RoShell.Command({
	Name = "give",
	Description = "Gives items to players",
	Group = "Demo",
	SupportsDryRun = true,
	Examples = {
		{ Text = "give me ~embers 3", Description = "Fuzzy item match" },
		{ Text = 'give %Red,-Bob "Healing Potion" 5', Description = "Team Red except Bob" },
		{ Text = "give * Aegis --dry", Description = "Preview without giving" },
	},
	Args = {
		{ targets = RoShell.Arg(RoShell.Types.Players, { Description = "Who receives the items" }) },
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

return { give, take, inventory, items }
