--!strict
const Command = require("../../src/Shared/Command")
const Completion = require("../../src/Shared/Completion")
const Platform = require("../../src/Shared/Platform")
const Runner = require("../Runner")
const Shell = require("../../src/Shared/Shell")
const TypeBuilder = require("../../src/Shared/TypeBuilder")
const Types = require("../../src/Shared/Types")

--// Fixture

const PEOPLE = { "Bob", "Bobby", "Alice", "Carol" }
const ITEMS = { "Sword of Embers", "Shadow Sword", "Swift Executioner", "Apple" }

const function stringCandidates(names: { string }): { Types.Candidate<string> }
	const candidates: { Types.Candidate<string> } = {}
	for _, name in names do
		table.insert(candidates, { Key = name, Value = name })
	end
	return candidates
end

const Person = TypeBuilder.Dynamic({
	Name = "player",
	Candidates = function(): { Types.Candidate<string> }
		return stringCandidates(PEOPLE)
	end,
	Default = function(): string?
		return "Alice"
	end,
	Selectors = {
		{
			Prefix = "%",
			Name = "team",
			Description = "Team members",
			Example = "%Red",
			Resolve = function(): Types.ParseResult<{ read string }>
				return { Ok = true, Value = { "Bob" } }
			end,
		},
	},
})
const People = TypeBuilder.List(Person, { Name = "players" })
const Item = TypeBuilder.Dynamic({
	Name = "item",
	Candidates = function(): { Types.Candidate<string> }
		return stringCandidates(ITEMS)
	end,
})

const function makeShell(): Types.Shell
	const shell = Shell.new({ IsServer = true, IsClient = false, Platform = Platform.Headless().Platform })
	shell.Registry:RegisterCommands({
		Command.new({
			Name = "give",
			Aliases = { "grant" },
			Description = "Give items",
			Args = {
				{ targets = Command.Arg(People, { Description = "Who receives the item" }) },
				{ item = Command.Arg(Item) },
				{ amount = Command.Default(TypeBuilder.Integer({ Min = 1 }), 1, { Short = "n" }) },
				{ silent = Command.Flag({ Short = "s" }) },
				{ reason = Command.Optional(TypeBuilder.String(), { Named = true }) },
			},
		}):Run(function()
			return nil
		end),
		Command.new({
			Name = "kick",
			Args = { { target = Command.Arg(Person) }, { reason = Command.Optional(TypeBuilder.String()) } },
		}):Run(function()
			return nil
		end),
		Command.new({ Name = "gravity", Args = { { value = Command.Arg(TypeBuilder.Number()) } } }):Run(function()
			return nil
		end),
	})
	return shell
end

--- Runs a query where `█` marks the cursor.
const function query(shell: Types.Shell, marked: string): (Completion.CompletionResult, string)
	const cursor = marked:find("█", 1, true) or (#marked + 1)
	const text = marked:gsub("█", "")
	return Completion.Query({ Shell = shell, Text = text, Cursor = cursor }), text
end

const function texts(result: Completion.CompletionResult): { string }
	const list: { string } = {}
	for _, suggestion in result.Suggestions do
		table.insert(list, suggestion.Text)
	end
	return list
end

return function(t: Runner.Api)
	const shell = makeShell()

	t.it("completes commands and aliases", function()
		const result = query(shell, "giv█")
		t.expect(result.Context):toBe("Command")
		t.expect(texts(result)[1]):toBe("give")
		t.expect(result.Replace.Start):toBe(1)
		t.expect(result.Replace.End):toBe(4)
		const aliasResult = query(shell, "gra█")
		t.expect(texts(aliasResult)[1]):toBe("grant")
		t.expect(aliasResult.Suggestions[1].Kind):toBe("alias")
	end)

	t.it("ranks players fuzzily with highlights", function()
		const result = query(shell, "give B█")
		t.expect(result.Context):toBe("Argument")
		t.expect(result.ActiveArg):toBe(1)
		const list = texts(result)
		t.expect(list[1]):toBe("Bob")
		t.expect(list[2]):toBe("Bobby")
		t.expect(#result.Suggestions[1].MatchRanges):toBe(1)
	end)

	t.it("lists operators for an operator prefix", function()
		const result = query(shell, "give *█")
		t.expect(result.Context):toBe("Operator")
		const list = texts(result)
		t.expect(table.find(list, "*") ~= nil):toBe(true)
		t.expect(table.find(list, "**") ~= nil):toBe(true)
	end)

	t.it("offers `.` (you) only for types that have a value for you", function()
		const players = texts((query(shell, "kick █")))
		t.expect(table.find(players, ".") ~= nil):toBe(true)
		const items = texts((query(shell, "give Bob █")))
		t.expect(table.find(items, ".")):toBeNil()
		t.expect(table.find(items, "?") ~= nil):toBe(true)
		t.expect(table.find(items, "~") ~= nil):toBe(true)
		const function symbols(type: Types.Type<string>): { string }
			const list: { string } = {}
			for _, operator in type.Operators do
				table.insert(list, operator.Symbol)
			end
			return list
		end
		t.expect(table.find(symbols(Person), ".") ~= nil):toBe(true)
		t.expect(table.find(symbols(Item), ".")):toBeNil()
	end)

	t.it("completes the second argument", function()
		const result = query(shell, "give Bob sw█")
		t.expect(result.ActiveArg):toBe(2)
		const list = texts(result)
		t.expect(list[1]):toBe('"Sword of Embers"')
		t.expect(table.find(list, '"Shadow Sword"') ~= nil):toBe(true)
	end)

	t.it("suggests unused flags after --", function()
		const result = query(shell, "give Bob sword --█")
		t.expect(result.Context):toBe("Flag")
		const list = texts(result)
		t.expect(table.find(list, "--amount") ~= nil):toBe(true)
		t.expect(table.find(list, "--silent") ~= nil):toBe(true)
		t.expect(table.find(list, "--reason") ~= nil):toBe(true)
		t.expect(table.find(list, "--targets")):toBeNil()
	end)

	t.it("completes flag values", function()
		const result = query(shell, "give Bob sword --amount █")
		t.expect(result.Context):toBe("FlagValue")
		t.expect(result.ActiveArg):toBe(3)
	end)

	t.it("completes inside quotes without the open quote", function()
		const result, text = query(shell, 'kick "Bo█')
		t.expect(text:sub(result.Replace.Start, result.Replace.End - 1)):toBe("Bo")
		t.expect(texts(result)[1]):toBe("Bob")
	end)

	t.it("works with the cursor in the middle of the text", function()
		const result = query(shell, "give █ sword")
		t.expect(result.ActiveArg):toBe(1)
		t.expect(result.Signature and result.Signature.ActiveType):toBe("players")
	end)

	t.it("completes inside embeds and after pipes", function()
		const embedded = query(shell, "kick ${giv█}")
		t.expect(embedded.Embedded):toBe(true)
		t.expect(texts(embedded)[1]):toBe("give")
		const piped = query(shell, "kick Bob | gra█")
		t.expect(piped.Context):toBe("Command")
		t.expect(table.find(texts(piped), "gravity") ~= nil):toBe(true)
	end)

	t.it("builds signature hints with the active argument", function()
		const result = query(shell, "give Bob █")
		const signature = result.Signature
		t.expect(signature ~= nil):toBe(true)
		if signature then
			t.expect(signature.Parts[1].Text):toBe("give")
			t.expect(signature.Parts[3].Active):toBe(true)
			t.expect(signature.Parts[4].Text):toBe("[amount: integer = 1]")
		end
	end)

	t.it("previews resolutions", function()
		const result = query(shell, "give *-Bob█")
		const preview = result.Preview
		t.expect(preview ~= nil):toBe(true)
		if preview then
			t.expect(preview.Text):toBe("3 players")
		end
	end)

	t.it(
		"computes ghost text and common prefixes",
		function()
			const result = query(shell, "give Bob Sw█")
			t.expect(Completion.Ghost(result)):toBe(nil) -- top suggestion is quoted, so not a plain extension
			const commands = query(shell, "gi█")
			t.expect(Completion.Ghost(commands)):toBe("ve")
			const prefix = Completion.CommonPrefix(
				{
					{ Text = "Bobby", Display = "", Kind = "", Score = 0, MatchRanges = {} },
					{ Text = "Bobbin", Display = "", Kind = "", Score = 0, MatchRanges = {} },
				},
				"bo"
			)
			t.expect(prefix):toBe("Bobb")
		end
	)

	t.it("reports live diagnostics", function()
		const result = query(shell, "give Bob nothing█")
		t.expect(#result.Diagnostics > 0):toBe(true)
		t.expect(result.Diagnostics[1].Message):toContain("Unknown item")
	end)
end
