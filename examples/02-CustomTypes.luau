--!strict
--[[
	Custom argument types. Every constructor infers the value type, so commands using these types get precise
	`args` without annotations. Register shared types once (`registry:RegisterTypes(...)`) to make them available
	to `help`, `types` and pipe checks by name.
]]

const RoShell = require(game:GetService("ReplicatedStorage").RoShell)

export type Pet = { Species: string, Speed: number }

const Types = {}

--- A fixed set of words: the value type is the union of the choices.
Types.Difficulty = RoShell.Type.Choice<<"easy" | "normal" | "hard">>({
	Name = "difficulty",
	Choices = { "easy", "normal", "hard" },
	Descriptions = { hard = "No respawns" },
	Aliases = { normal = { "medium" } },
})

--- Keys mapped to rich values (the value type is `Pet`).
Types.Pet = RoShell.Type.Map({
	Name = "pet",
	Entries = {
		{ Key = "cat", Value = { Species = "cat", Speed = 16 } :: Pet, Detail = "fast" },
		{ Key = "dog", Value = { Species = "dog", Speed = 14 } :: Pet, Aliases = { "puppy" } },
		{ Key = "turtle", Value = { Species = "turtle", Speed = 2 } :: Pet, Detail = "slow" },
	},
})

--- Candidates computed at run time (cached for 5 seconds). Supports wildcards, `~fuzzy`, globs and lists.
Types.Zone = RoShell.Type.Dynamic({
	Name = "zone",
	Plural = "zones",
	CacheSeconds = 5,
	Candidates = function(): { RoShell.Candidate<BasePart> }
		const candidates: { RoShell.Candidate<BasePart> } = {}
		const folder = workspace:FindFirstChild("Zones")
		if folder then
			for _, part in folder:GetChildren() do
				if part:IsA("BasePart") then
					table.insert(candidates, { Key = part.Name, Value = part, Detail = part.Material.Name })
				end
			end
		end
		return candidates
	end,
})
Types.Zones = RoShell.Type.List(Types.Zone, { Name = "zones" })

--- Structured input: `x=1,y=2` records (value type `{ x: number, y: number }`).
Types.Offset = RoShell.Type.Struct({
	Name = "offset",
	Fields = { x = RoShell.Type.Number(), y = RoShell.Type.Number() },
})

--- Derive one type from another.
Types.Seconds = RoShell.Type.Transform({
	From = RoShell.Types.Duration,
	To = function(seconds: number): number
		return math.floor(seconds)
	end,
	Name = "seconds",
})

--- Narrow an existing type with a check.
Types.EvenNumber = RoShell.Type.Refine(
	RoShell.Type.Integer(),
	function(value: number): (boolean, string?)
		return value % 2 == 0, "Expected an even number"
	end,
	"even number"
)

--- Either a number or a difficulty word (value type `number | "easy" | "normal" | "hard"`).
Types.Level = RoShell.Type.Union({ Name = "level", Members = { RoShell.Type.Integer(), Types.Difficulty } })

const configure = RoShell.Command({
	Name = "configure",
	Description = "Shows how the custom types arrive in Run",
	Group = "Examples",
	Args = {
		{ difficulty = RoShell.Default(Types.Difficulty, "normal") },
		{ pet = RoShell.Optional(Types.Pet) },
		{ offset = RoShell.Optional(Types.Offset, { Named = true }) },
		{ level = RoShell.Optional(Types.Level, { Named = true }) },
	},
}):Run(
	function(ctx, args)
		-- args.difficulty: "easy" | "normal" | "hard"; args.pet: Pet?; args.offset: { x: number, y: number }?
		const pet = args.pet
		const speed = if pet then pet.Speed else 0
		const offset = args.offset
		const shift = if offset then `{offset.x},{offset.y}` else "none"
		return ctx:Info(`difficulty={args.difficulty} speed={speed} offset={shift}`)
	end
)

return table.freeze({ Types = Types, Commands = { configure } })
