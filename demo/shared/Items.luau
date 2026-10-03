--!strict
--[[
	The demo's loot table.
]]

--// Types
export type Rarity = "common" | "uncommon" | "rare" | "epic" | "legendary"

export type Item = {
	read Id: string,
	read Name: string,
	read Rarity: Rarity,
	read Color: Color3,
	read Description: string,
}

--// Constants
const ITEMS: { Item } = {
	{
		Id = "sword_embers",
		Name = "Sword of Embers",
		Rarity = "legendary",
		Color = Color3.fromRGB(255, 120, 60),
		Description = "Burns on every hit",
	},
	{
		Id = "shadow_sword",
		Name = "Shadow Sword",
		Rarity = "epic",
		Color = Color3.fromRGB(110, 80, 170),
		Description = "Strikes from the dark",
	},
	{
		Id = "swift_executioner",
		Name = "Swift Executioner",
		Rarity = "rare",
		Color = Color3.fromRGB(80, 170, 255),
		Description = "Fast and merciless",
	},
	{
		Id = "iron_sword",
		Name = "Iron Sword",
		Rarity = "common",
		Color = Color3.fromRGB(170, 170, 180),
		Description = "Reliable and plain",
	},
	{
		Id = "frost_bow",
		Name = "Frost Bow",
		Rarity = "epic",
		Color = Color3.fromRGB(150, 220, 255),
		Description = "Slows its targets",
	},
	{
		Id = "hunting_bow",
		Name = "Hunting Bow",
		Rarity = "uncommon",
		Color = Color3.fromRGB(150, 110, 70),
		Description = "Good range",
	},
	{
		Id = "healing_potion",
		Name = "Healing Potion",
		Rarity = "common",
		Color = Color3.fromRGB(255, 80, 110),
		Description = "Restores 50 health",
	},
	{
		Id = "speed_potion",
		Name = "Speed Potion",
		Rarity = "uncommon",
		Color = Color3.fromRGB(90, 230, 140),
		Description = "Run faster for 30s",
	},
	{
		Id = "dragon_scale",
		Name = "Dragon Scale",
		Rarity = "legendary",
		Color = Color3.fromRGB(60, 200, 120),
		Description = "Proof of a legend",
	},
	{
		Id = "golden_apple",
		Name = "Golden Apple",
		Rarity = "rare",
		Color = Color3.fromRGB(255, 210, 70),
		Description = "Shiny and filling",
	},
	{
		Id = "wooden_shield",
		Name = "Wooden Shield",
		Rarity = "common",
		Color = Color3.fromRGB(160, 120, 80),
		Description = "Blocks a little",
	},
	{
		Id = "aegis",
		Name = "Aegis",
		Rarity = "legendary",
		Color = Color3.fromRGB(240, 240, 255),
		Description = "Blocks everything once",
	},
}

const RARITY_COLORS: { [Rarity]: Color3 } = {
	common = Color3.fromRGB(170, 170, 180),
	uncommon = Color3.fromRGB(90, 200, 120),
	rare = Color3.fromRGB(80, 160, 255),
	epic = Color3.fromRGB(170, 100, 255),
	legendary = Color3.fromRGB(255, 170, 40),
}

return table.freeze({
	List = ITEMS,
	RarityColors = RARITY_COLORS,
})
