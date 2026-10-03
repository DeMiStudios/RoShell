--!strict
--[[
	Type test: must type-check with zero errors. Every `expectType` call pins the inferred type of `args` fields.
]]

const Command = require("../../../src/Shared/Command")
const TypeBuilder = require("../../../src/Shared/TypeBuilder")

--- Compile-time assertion helper: `expectType<<T>>(value)` errors unless `value` is a `T`.
const function expectType<T>(_value: T)
end

type ItemDef = { Id: string, Rarity: number }

const Rarity = TypeBuilder.Choice<<"common" | "rare">>({ Name = "rarity", Choices = { "common", "rare" } })
const Count = TypeBuilder.Integer({ Name = "count", Min = 1 })
const Item = TypeBuilder.Dynamic({
	Name = "item",
	Candidates = function()
		const items: { ItemDef } = { { Id = "sword", Rarity = 2 } }
		const candidates = {}
		for _, item in items do
			table.insert(candidates, { Key = item.Id, Value = item })
		end
		return candidates
	end,
})
const Target = TypeBuilder.Union({ Name = "target", Members = { Count, Rarity } })
const Point = TypeBuilder.Struct({ Name = "point", Fields = { x = TypeBuilder.Number(), y = TypeBuilder.Number() } })
const Material = TypeBuilder.FromEnum({ Name = "material", Enum = Enum.Material })
const Names = TypeBuilder.List(TypeBuilder.String())

const give = Command.new({
	Name = "give",
	Args = {
		{ rarity = Command.Arg(Rarity) },
		{ item = Command.Arg(Item, { Description = "The item" }) },
		{ amount = Command.Default(Count, 1) },
		{ target = Command.Optional(Target) },
		{ at = Command.Optional(Point) },
		{ material = Command.Arg(Material) },
		{ names = Command.Arg(Names) },
		{ silent = Command.Flag({ Short = "s" }) },
		{ rest = Command.Rest(TypeBuilder.String()) },
	},
}):Run(function(ctx, args)
	expectType<<"common" | "rare">>(args.rarity)
	expectType<<ItemDef>>(args.item)
	expectType<<number>>(args.amount)
	expectType<<(number | "common" | "rare")?>>(args.target)
	expectType<<{ x: number, y: number }?>>(args.at)
	expectType<<Enum.Material>>(args.material)
	expectType<<{ string }>>(args.names)
	expectType<<boolean>>(args.silent)
	expectType<<{ string }>>(args.rest)
	return ctx:Success(`Gave {args.amount}x {args.item.Id}`)
end)

const ping = Command.new({ Name = "ping", Args = {} }):ClientRun(function(ctx, _args)
	return "pong"
end)

const validated = Command.new({
	Name = "heal",
	Args = {
		{
			amount = Command.Arg(Count, {
				Validate = function(value: number): (boolean, string?)
					return value <= 100, "At most 100"
				end,
			}),
		},
	},
}):Validate(function(_ctx, args)
	return args.amount > 0, "Positive only"
end):Run(function(_ctx, args)
	expectType<<number>>(args.amount)
	return nil
end)

return { give, ping, validated }
