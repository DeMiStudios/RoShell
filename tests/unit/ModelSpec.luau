--!strict
const Command = require("../../src/Shared/Command")
const Completion = require("../../src/Shared/Completion")
const Model = require("../../src/Client/UI/Model")
const Picker = require("../../src/Client/UI/Picker")
const Runner = require("../Runner")
const Test = require("../../src/Shared/Test")
const TypeBuilder = require("../../src/Shared/TypeBuilder")
const Types = require("../../src/Shared/Types")

--// Fixture

const COLORS: Model.Colors = {
	Text = "#EEEEEE",
	Secondary = "#AAAAAA",
	Muted = "#777777",
	Accent = "#3366FF",
	Type = function(_token: string?): string
		return "#55AA55"
	end,
}

const Fruit = TypeBuilder.Choice({
	Name = "fruit",
	Choices = { "apple", "banana", "cherry" },
	Descriptions = { apple = "Crisp and red" },
})

const ban = Command.new({
	Name = "ban",
	Icon = "lock-closed",
	Description = "Manages bans",
	Args = {},
	Subcommands = {
		Command.new({ Name = "add", Icon = "circle-plus", Description = "Bans someone", Args = {} }):Run(function()
			return nil
		end),
	},
}):Run(function()
	return nil
end)

const function harness(): Test.Harness
	return Test.new({
		Defaults = true,
		Commands = {
			Command.new({
				Name = "eat",
				Icon = "heart",
				Description = "Eats a fruit",
				Group = "Food",
				Examples = { "eat apple" },
				Args = {
					{ fruit = Command.Arg(Fruit, { Description = "What to eat" }) },
					{ count = Command.Default(TypeBuilder.Integer({ Min = 1 }), 1) },
				},
			}):Run(function()
				return nil
			end),
			ban,
		},
	})
end

const function suggest(test: Test.Harness, text: string, selected: number?): Model.Assist
	const result = Completion.Query({ Shell = test.Shell, Text = text, Cursor = #text + 1 })
	return Model.Suggest({
		Result = result,
		Selected = selected,
		Diagnostic = nil,
		GetCommand = function(name: string): Types.Command?
			return test.Shell.Registry:GetCommand(name)
		end,
		Colors = COLORS,
	})
end

const function labels(list: Model.List?): { string }
	const out: { string } = {}
	if list then
		for _, item in list.Items do
			table.insert(out, item.Label)
		end
	end
	return out
end

const function headings(details: Model.Details?): { string }
	const out: { string } = {}
	if details then
		for _, section in details.Sections do
			table.insert(out, section.Heading or "")
		end
	end
	return out
end

--// Spec

return function(t: Runner.Api)
	t.describe(
		"Model.Suggest",
		function()
			t.it("lists matching commands with icons and descriptions, and describes the highlighted one", function()
				const model = suggest(harness(), "ea")
				t.expect(model.Focus):toBe("left")
				const left = model.Left
				t.expect(left ~= nil):toBe(true)
				if left then
					const first = left.Items[1]
					t.expect(first.Label):toBe("eat")
					t.expect(first.Subtitle):toBe("Eats a fruit")
					t.expect(first.Icon):toBe("heart")
					t.expect(left.Selected):toBe(1)
				end
				const details = model.Details
				t.expect(details ~= nil and details.Title:find("eat", 1, true) ~= nil):toBe(true)
				t.expect(table.find(headings(details), "Arguments") ~= nil):toBe(true)
				t.expect(table.find(headings(details), "Examples") ~= nil):toBe(true)
				t.expect(model.Right):toBeNil()
			end)

			t.it(
				"keeps only the command on the left and puts the argument and its candidates on the right",
				function()
					const model = suggest(harness(), "eat ")
					t.expect(model.Focus):toBe("right")
					t.expect(labels(model.Left)):toEqual({ "eat" })
					t.expect(model.Left and model.Left.Selected):toBe(1)
					const details = model.Details
					t.expect(details ~= nil):toBe(true)
					if details then
						const active = details.Active
						t.expect(active and active.Name):toBe("fruit")
						t.expect(active and active.Type):toBe("Fruit")
						t.expect(active and active.Description):toBe("What to eat")
						-- The active argument is drawn in the accent color.
						t.expect(
							details.Title:find(`<font color="#3366FF"><b>&lt;fruit&gt;</b></font>`, 1, true) ~= nil
						):toBe(true)
					end
					-- The values, then the operators the type understands.
					t.expect(labels(model.Right)):toEqual({ "apple", "banana", "cherry", "?", "~" })
				end
			)

			t.it(
				"describes the highlighted candidate on a line that stays while the highlight moves",
				function()
					const first = suggest(harness(), "eat ")
					const hint = first.Details and first.Details.Hint
					t.expect(hint ~= nil and hint:find("Crisp and red", 1, true) ~= nil):toBe(true)
					t.expect(first.Details and first.Details.HintSlot):toBe(true)
					-- banana has no description: the line is empty but keeps its room.
					const second = suggest(harness(), "eat ", 2)
					t.expect(second.Details and second.Details.Hint):toBeNil()
					t.expect(second.Details and second.Details.HintSlot):toBe(true)
					-- Without descriptions there is no line at all.
					const counts = suggest(harness(), "eat apple ")
					t.expect(counts.Details and counts.Details.HintSlot):toBe(false)
				end
			)

			t.it(
				"does not open the hint line for operators alone (their rows name them)",
				function()
					const Color = TypeBuilder.Choice({ Name = "color", Choices = { "red", "blue" } })
					const test = Test.new({
						Commands = {
							Command.new({ Name = "paint", Args = { { color = Command.Arg(Color) } } }):Run(function()
								return nil
							end),
						},
					})
					-- The values, then the operators (which have descriptions).
					t.expect(labels(suggest(test, "paint ").Right)):toEqual({ "blue", "red", "?", "~" })
					const onOperator = suggest(test, "paint ", 3)
					t.expect(onOperator.Details and onOperator.Details.HintSlot):toBe(false)
					t.expect(onOperator.Details and onOperator.Details.Hint):toBeNil()
				end
			)

			t.it("explains a problem when nothing matches", function()
				const test = harness()
				const text = "zzqx"
				const result = Completion.Query({ Shell = test.Shell, Text = text, Cursor = #text + 1 })
				const model = Model.Suggest({
					Result = result,
					Selected = nil,
					Diagnostic = {
						Severity = "error",
						Message = "Unknown command 'zzqx'",
						Span = { Start = 1, End = 5 },
					},
					GetCommand = function(name: string): Types.Command?
						return test.Shell.Registry:GetCommand(name)
					end,
					Colors = COLORS,
				})
				t.expect(model.Left):toBeNil()
				const notice = model.Details and model.Details.Notice
				t.expect(notice and notice.Text):toBe("Unknown command 'zzqx'")
				t.expect(notice and notice.Level):toBe("error")
			end)
		end
	)

	t.describe("Model helpers", function()
		t.it("finds subcommands by their full name", function()
			const test = harness()
			const function get(name: string): Types.Command?
				return test.Shell.Registry:GetCommand(name)
			end
			const found = Model.FindCommand(get, "ban add")
			t.expect(found and found.Name):toBe("add")
			t.expect(Model.FindCommand(get, "ban nope")):toBeNil()
			t.expect(Model.FindCommand(get, "nope")):toBeNil()
		end)

		t.it("writes signatures with required, optional and flag arguments", function()
			const test = harness()
			const eat = test.Shell.Registry:GetCommand("eat")
			t.expect(eat ~= nil):toBe(true)
			if eat then
				const plain = Model.Signature(eat, nil, COLORS):gsub("<[^>]+>", ""):gsub("&lt;", "<"):gsub("&gt;", ">")
				t.expect(plain):toBe("eat <fruit> [count]")
			end
		end)
	end)

	t.describe("Picker", function()
		const function entries(log: { string }): { Picker.Entry }
			const list: { Picker.Entry } = {}
			for _, name in { "Midnight", "Sakura", "Ocean" } do
				table.insert(list, {
					Item = { Label = name },
					Search = name,
					Details = function(): Model.Details
						return { Title = name, Sections = {} }
					end,
					Preview = function()
						table.insert(log, "preview " .. name)
					end,
					Choose = function()
						table.insert(log, "choose " .. name)
					end,
				})
			end
			return list
		end

		t.it("filters fuzzily, highlights matches and describes the highlighted entry", function()
			const picker = Picker.new()
			picker.Open({ Placeholder = "Search", Entries = entries({}) })
			picker.SetQuery("sak")
			const model = picker.Model()
			t.expect(labels(model.Left)):toEqual({ "Sakura" })
			const ranges = model.Left and model.Left.Items[1].Ranges
			t.expect(ranges ~= nil and #ranges > 0):toBe(true)
			t.expect(model.Details and model.Details.Title):toBe("Sakura")
		end)

		t.it("ranks names and aliases above descriptions", function()
			const function entry(label: string, search: string, extra: string): Picker.Entry
				return {
					Item = { Label = label },
					Search = search,
					Extra = extra,
					Choose = function()
					end,
				}
			end
			const picker = Picker.new()
			picker.Open({
				Placeholder = "Search",
				Entries = {
					entry("give", "give", "Gives items to players"),
					entry("teleport", "teleport tp", "Teleports players to another player"),
				},
			})
			picker.SetQuery("tp")
			t.expect(labels(picker.Model().Left)):toEqual({ "teleport", "give" })
		end)

		t.it("previews the highlighted entry and undoes it when closed without a choice", function()
			const log: { string } = {}
			local cancelled = 0
			const picker = Picker.new()
			picker.Open({
				Placeholder = "Search",
				Entries = entries(log),
				Selected = 2,
				OnCancel = function()
					cancelled += 1
				end,
			})
			t.expect(log[1]):toBe("preview Sakura")
			picker.Move(1)
			t.expect(log[2]):toBe("preview Ocean")
			picker.Close()
			t.expect(cancelled):toBe(1)
			t.expect(picker.IsOpen()):toBe(false)
		end)

		t.it("choosing closes without cancelling", function()
			const log: { string } = {}
			local cancelled = 0
			const picker = Picker.new()
			picker.Open({
				Placeholder = "Search",
				Entries = entries(log),
				OnCancel = function()
					cancelled += 1
				end,
			})
			picker.Choose(false)
			t.expect(log[#log]):toBe("choose Midnight")
			t.expect(cancelled):toBe(0)
			t.expect(picker.IsOpen()):toBe(false)
		end)
	end)
end
