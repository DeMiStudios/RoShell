--!strict
--[[
	Negative type test: every line marked `-- expect-error` must produce a type error, and no other line may.
	Checked by `scripts/typetests.sh`.
]]

const Command = require("../../../src/Shared/Command")
const Keys = require("../../../src/Shared/Keys")
const TypeBuilder = require("../../../src/Shared/TypeBuilder")

type ItemDef = { Id: string, Rarity: number }

const Rarity = TypeBuilder.Choice<<"common" | "rare">>({ Name = "rarity", Choices = { "common", "rare" } })
const Count = TypeBuilder.Integer({ Name = "count", Min = 1 })
const Point = TypeBuilder.Struct({ Name = "point", Fields = { x = TypeBuilder.Number(), y = TypeBuilder.Number() } })
const Item = TypeBuilder.Map({
	Name = "item",
	Entries = { { Key = "sword", Value = { Id = "sword", Rarity = 2 } :: ItemDef } },
})

-- Defaults are a value of the argument's type or its text form; anything else is rejected.
const badDefault = Command.Default(Count, true) -- expect-error

const give = Command.new({
	Name = "give",
	Args = {
		{ rarity = Command.Arg(Rarity) },
		{ item = Command.Arg(Item) },
		{ amount = Command.Default(Count, 1) },
		{ at = Command.Optional(Point) },
		{ silent = Command.Flag() },
		{ rest = Command.Rest(TypeBuilder.String()) },
	},
}):Run(
	function(ctx, args)
		const _unknownArg = args.nope -- expect-error
		const _wrongPrimitive: string = args.amount -- expect-error
		const _narrowedChoice: "legendary" = args.rarity -- expect-error
		const _optionalUnchecked: number = args.at.x -- expect-error
		const _flagIsBoolean: string = args.silent -- expect-error
		const _restIsList: string = args.rest -- expect-error
		const _itemField: number = args.item.Id -- expect-error
		const _structField = args.at and args.at.z -- expect-error
		const _envIsTyped: string = ctx:GetEnv(Keys.Scheduler) -- expect-error
		return ctx:Value(Count, "three") -- expect-error
	end
)

return { badDefault, give }
