--!strict
--[[
	The worked examples of the specification's appendix: every input of Appendix B must parse, validate and
	resolve; the completion table of Appendix C must hold. Runs against a fake world:

		Red    = Bob, Alice          Blue = Bobby          Admins = Bob, Carol          (+ Dave, no team)
]]

const BuiltInTypes = require("../../src/Shared/BuiltInTypes")
const Command = require("../../src/Shared/Command")
const Completion = require("../../src/Shared/Completion")
const FakeWorld = require("../support/FakeWorld")
const Runner = require("../Runner")
const Test = require("../../src/Shared/Test")
const TypeBuilder = require("../../src/Shared/TypeBuilder")
const Types = require("../../src/Shared/Types")

type ItemDef = { Name: string }

const Item = TypeBuilder.Map({
	Name = "item",
	Entries = {
		{ Key = "Sword of Embers", Value = { Name = "Sword of Embers" } :: ItemDef },
		{ Key = "Shadow Sword", Value = { Name = "Shadow Sword" } :: ItemDef },
		{ Key = "Swift Executioner", Value = { Name = "Swift Executioner" } :: ItemDef },
		{ Key = "Healing Potion", Value = { Name = "Healing Potion" } :: ItemDef },
	},
})

const function giveCommand(log: { string }): Types.Command
	return Command.new({
		Name = "give",
		Aliases = { "grant" },
		Description = "Gives items",
		Args = {
			{ targets = Command.Default(BuiltInTypes.Types.Players, "me") },
			{ item = Command.Arg(Item) },
			{ amount = Command.Default(TypeBuilder.Integer({ Min = 1 }), 1) },
			{ reason = Command.Optional(TypeBuilder.String(), { Named = true }) },
			{ silent = Command.Flag({ Short = "s" }) },
		},
	}):Run(function(ctx, args)
		for _, player in args.targets do
			table.insert(log, `{player.Name}:{args.item.Name}x{args.amount}`)
		end
		return ctx:Success("given")
	end)
end

const function setup(): (FakeWorld.World, Test.Harness, { string })
	const world = FakeWorld.new({ Red = { "Bob", "Alice" }, Blue = { "Bobby" }, Admins = { "Bob", "Carol" } }, {
		"Dave",
	})
	const log: { string } = {}
	const harness = Test.new({ Defaults = true, Platform = world.Controller.Platform, Commands = { giveCommand(log) } })
	return world, harness, log
end

const function labels(result: Completion.CompletionResult): { string }
	const list: { string } = {}
	for _, suggestion in result.Suggestions do
		table.insert(list, suggestion.Display)
	end
	return list
end

const function query(harness: Test.Harness, text: string, cursor: number?): Completion.CompletionResult
	return Completion.Query({ Shell = harness.Shell, Text = text, Cursor = cursor or #text + 1, Limit = 50 })
end

const function has(list: { string }, value: string): boolean
	return table.find(list, value) ~= nil
end

return function(t: Runner.Api)
	t.describe(
		"Appendix B: inputs",
		function()
			t.it("validates every example", function()
				const _, harness = setup()
				for _, line in {
					'kick *-Bob --reason "AFK"',
					'give ~sw 3 && announce "Loot dropped"',
					'players --team Red | kick --reason "friendly fire"',
					"tp Bob ${players ?}",
					"heal %Red&%Admins",
					"setspeed Bo* 16..32/8",
					'alias gg = "announce GG $1"',
					"in 5m shutdown --dry",
				} do
					const evaluation = harness.Shell.Dispatcher:Evaluate({ Text = line })
					const messages: { string } = {}
					for _, diagnostic in evaluation.Diagnostics do
						table.insert(messages, diagnostic.Message)
					end
					if not evaluation.Ok then
						error(`{line}: {table.concat(messages, "; ")}`, 0)
					end
				end
			end)

			t.it(
				"resolves wildcards and set arithmetic",
				function()
					const _, harness = setup()
					const function resolve(text: string): string
						const evaluation = harness.Shell.Dispatcher:Evaluate({ Text = `heal {text}` })
						const resolved = evaluation.Commands[1].Args[1]
						const names: { string } = {}
						const value = resolved.Value
						if type(value) == "table" then
							for _, player in value do
								if typeof(player) == "Instance" or type(player) == "table" then
									const name = (player :: Player).Name
									table.insert(names, name)
								end
							end
						end
						return table.concat(names, ",")
					end
					t.expect(resolve("%Red&%Admins")):toBe("Bob")
					-- Results keep the player enumeration order: Bob, Carol, Bobby, Alice, Dave.
					t.expect(resolve("*-Bob")):toBe("Carol,Bobby,Alice,Dave")
					t.expect(resolve("Bo*")):toBe("Bob,Bobby")
					t.expect(resolve("%Red+%Blue")):toBe("Bob,Bobby,Alice")
					t.expect(resolve("!%Admins")):toBe("Bobby,Alice,Dave")
				end
			)

			t.it(
				"runs a chain with fuzzy items and a confirmation for many targets",
				function()
					const world, harness, log = setup()
					const result = harness.Run('give ~embers 3 && kick *-Bob --reason "AFK"', { Answers = { "yes" } })
					t.expect(result.Ok):toBe(false) -- `give` needs targets: `~embers` is not a player
					t.expect(#log):toBe(0)

					const kicked = harness.Run('give Bob ~embers 3 && kick *-Bob --reason "AFK"', {
						Answers = { "yes" },
					})
					t.expect(kicked.Ok):toBe(true)
					t.expect(log[1]):toBe("Bob:Sword of Embersx3")
					t.expect(#world.Kicked):toBe(4)
					t.expect(world.Kicked[1].Message):toBe("AFK")
				end
			)

			t.it("expands stepped ranges", function()
				const _, harness = setup()
				const evaluation = harness.Shell.Dispatcher:Evaluate({ Text = "setspeed Bo* 16..32/8" })
				const speeds = evaluation.Commands[1].Args[2]
				t.expect(speeds.Ok):toBe(true)
				t.expect(speeds.Display):toBe("16, 24, 32")
			end)
		end
	)

	t.describe("Appendix C: completion", function()
		t.it('"giv" offers the command; aliases complete under their own name', function()
			const _, harness = setup()
			const result = query(harness, "giv")
			t.expect(labels(result)[1]):toBe("give")
			t.expect(result.Replace.Start):toBe(1)
			t.expect(result.Replace.End):toBe(4)
			const alias = query(harness, "gra")
			t.expect(labels(alias)[1]):toBe("grant")
			t.expect(alias.Suggestions[1].Detail):toBe("alias of give")
		end)

		t.it('"give B" ranks players fuzzily with highlights', function()
			const _, harness = setup()
			const result = query(harness, "give B")
			const names = labels(result)
			t.expect(names[1]):toBe("Bob")
			t.expect(names[2]):toBe("Bobby")
			t.expect(#result.Suggestions[1].MatchRanges > 0):toBe(true)
		end)

		t.it('"give *" lists operators', function()
			const _, harness = setup()
			const result = query(harness, "give *")
			local operators = 0
			for _, suggestion in result.Suggestions do
				if suggestion.Kind == "operator" then
					operators += 1
				end
			end
			t.expect(operators > 0):toBe(true)
		end)

		t.it('"give Bob sw" suggests items', function()
			const _, harness = setup()
			const names = labels(query(harness, "give Bob sw"))
			t.expect(has(names, "Sword of Embers")):toBe(true)
			t.expect(has(names, "Shadow Sword")):toBe(true)
			t.expect(has(names, "Swift Executioner")):toBe(true)
		end)

		t.it('"give Bob sword --" suggests flags', function()
			const _, harness = setup()
			const names = labels(query(harness, 'give Bob "Shadow Sword" --'))
			t.expect(has(names, "--silent")):toBe(true)
			t.expect(has(names, "--reason")):toBe(true)
			t.expect(has(names, "--amount")):toBe(true)
		end)

		t.it("completes inside quotes without replacing the open quote", function()
			const _, harness = setup()
			const result = query(harness, 'kick "Bo')
			t.expect(result.Replace.Start):toBe(7)
			t.expect(labels(result)[1]):toBe("Bob")
		end)

		t.it("completes the argument under a cursor in the middle of the text", function()
			const _, harness = setup()
			const text = "give  sword"
			const result = query(harness, text, 6)
			t.expect(result.ActiveArg):toBe(1)
			t.expect(has(labels(result), "Alice")):toBe(true)
		end)
	end)
end
