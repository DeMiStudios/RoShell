--!strict
--[[
	Custom argument types used by the demo commands.
]]

--// Imports
const Items = require("./Items")
const RoShell = require(game:GetService("ReplicatedStorage").RoShell)

--// Helpers

const function entries(): { RoShell.MapEntry<Items.Item> }
	const list: { RoShell.MapEntry<Items.Item> } = {}
	for _, item in Items.List do
		table.insert(list, {
			Key = item.Name,
			Value = item,
			Aliases = { item.Id },
			Description = item.Description,
			Detail = item.Rarity,
		})
	end
	return list
end

--// Types
const Item = RoShell.Type.Map({
	Name = "item",
	Description = "An item from the loot table (fuzzy: `~sw`, globs: `*Sword`)",
	Entries = entries(),
	Color = "type.enum",
	Icon = "value",
})

const Rarity = RoShell.Type.Choice<<Items.Rarity>>({
	Name = "rarity",
	Choices = { "common", "uncommon", "rare", "epic", "legendary" },
	Descriptions = {
		common = "Found everywhere",
		legendary = "One in a thousand",
	},
})

const Weather = RoShell.Type.Choice<<"clear" | "dusk" | "night" | "storm">>({
	Name = "weather",
	Choices = { "clear", "dusk", "night", "storm" },
})

--- How many of something: `3`, or one count per item, `1,5` (repeats allowed: `2,2`).
const Amounts = RoShell.Type.List(RoShell.Type.Integer({ Name = "amount", Min = 1 }), {
	Name = "amounts",
	Unique = false,
	Description = "One amount for every item, or one per item: 1,5",
})

return table.freeze({
	Item = Item,
	Items = RoShell.Type.List(Item, { Name = "items" }),
	Amounts = Amounts,
	Rarity = Rarity,
	Weather = Weather,
})
