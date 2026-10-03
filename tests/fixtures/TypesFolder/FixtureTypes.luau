--!strict
-- Fixture for RegisterTypesIn: a module returning a record of types.
const TypeBuilder = require("../../../src/Shared/TypeBuilder")

return {
	Flavor = TypeBuilder.Choice<<"vanilla" | "mint">>({ Name = "fixtureFlavor", Choices = { "vanilla", "mint" } }),
	Size = TypeBuilder.Integer({ Name = "fixtureSize", Min = 1, Max = 3 }),
	NotAType = "ignored",
}
