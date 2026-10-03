--!strict
--[[
	Negative type test for type constructors and typed services (see scripts/typetests.sh).
]]

const Command = require("../../../src/Shared/Command")
const Keys = require("../../../src/Shared/Keys")
const TypeBuilder = require("../../../src/Shared/TypeBuilder")

-- Choices must belong to the declared union.
const Mode = TypeBuilder.Choice<<"easy" | "hard">>({ Name = "mode", Choices = { "easy", "extreme" } }) -- expect-error

-- Number bounds are numbers.
const Bad = TypeBuilder.Number({ Name = "bad", Min = "1" }) -- expect-error

const Numbers = TypeBuilder.List(TypeBuilder.Number())
const Pair = TypeBuilder.Tuple({
	Name = "pair",
	Members = { { left = TypeBuilder.Number() }, { right = TypeBuilder.String() } },
})
const Either = TypeBuilder.Union({ Name = "either", Members = { TypeBuilder.Number(), TypeBuilder.Boolean() } })

const sum = Command.new({
	Name = "sum",
	Args = {
		{ values = Command.Arg(Numbers) },
		{ pair = Command.Arg(Pair) },
		{ either = Command.Arg(Either) },
		{ mode = Command.Default(Mode, "easy") },
	},
}):Run(
	function(ctx, args)
		const _listIsNotNumber = args.values + 1 -- expect-error
		const _tupleField: number = args.pair.right -- expect-error
		const _unionNeedsNarrowing: number = args.either -- expect-error
		const console = ctx:GetEnv(Keys.Console)
		if console then
			console.Clear(1) -- expect-error
		end
		return nil
	end
)

return { Bad, sum }
