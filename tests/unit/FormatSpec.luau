--!strict
const Format = require("../../src/Client/UI/Format")
const Runner = require("../Runner")

const COLORS: Format.Colors = { Accent = "#111111", Secondary = "#222222", Muted = "#333333", Link = "#444444" }

const function lines(text: string): { string }
	const result: { string } = {}
	for line in (text .. "\n"):gmatch("(.-)\n") do
		table.insert(result, line)
	end
	return result
end

return function(t: Runner.Api)
	t.describe("Format", function()
		t.it("aligns table columns in monospace", function()
			const entry = Format.Block(
				{
					Kind = "table",
					Title = "Loot",
					Columns = { "Item", "Count" },
					Rows = { { "Sword of Embers", "3" }, { "Aegis", "12" } },
				},
				COLORS
			)
			const plain = lines(entry.Plain)
			t.expect(plain[1]):toBe("Loot")
			t.expect(plain[2]):toBe("Item             Count")
			t.expect(plain[3]):toBe("Sword of Embers  3")
			t.expect(plain[4]):toBe("Aegis            12")
			t.expect(entry.Wrap):toBe(false)
			t.expect((entry.Rich:find("<u>Item</u>", 1, true))):Not():toBeNil()
		end)

		t.it("pads multibyte cells by characters", function()
			const entry = Format.Block({ Kind = "table", Columns = { "Name", "X" }, Rows = { { "héé", "1" } } }, COLORS)
			t.expect(lines(entry.Plain)[2]):toBe("héé   1")
		end)

		t.it("formats lists, key/value blocks and values", function()
			const list = Format.Block({ Kind = "list", Items = { "a", "b" } }, COLORS)
			t.expect(list.Plain):toBe("• a\n• b")
			const pairs = Format.Block(
				{
					Kind = "keyvalue",
					Entries = { { Key = "Name", Value = "Bob" }, { Key = "Rank", Value = "Admin" } },
				},
				COLORS
			)
			t.expect(pairs.Plain):toBe("Name  Bob\nRank  Admin")
			const value = Format.Block(
				{ Kind = "value", Display = "Bob, Alice", TypeName = "players", Items = { "Bob", "Alice" } },
				COLORS
			)
			t.expect(value.Plain):toBe("Bob, Alice  : players")
		end)

		t.it("escapes plain text but keeps rich text", function()
			const plain = Format.Block({ Kind = "text", Text = "<b>x</b>", Level = "info" }, COLORS)
			t.expect(plain.Rich):toBe("&lt;b&gt;x&lt;/b&gt;")
			const rich = Format.Block({ Kind = "text", Text = "<b>x</b>", Level = "info", Rich = true }, COLORS)
			t.expect(rich.Rich):toBe("<b>x</b>")
			t.expect(rich.Plain):toBe("x")
		end)

		t.it("keeps the source block for re-formatting", function()
			const block = { Kind = "progress", Id = "p1", Label = "Loading", Fraction = 0.5 }
			const entry = Format.Block(block, COLORS)
			t.expect(entry.Kind):toBe("progress")
			t.expect(entry.Plain):toBe("Loading  50%")
			t.expect(entry.Source):toBe(block)
		end)

		t.it("exports with prefixes per line", function()
			const exported = Format.Export({
				{ Entry = { Kind = "echo", Level = "echo", Rich = "", Plain = "give me x", Wrap = true }, Time = 0 },
				{ Entry = { Kind = "text", Level = "error", Rich = "", Plain = "bad\nworse", Wrap = true }, Time = 0 },
			})
			const exportedLines = lines(exported)
			t.expect(#exportedLines):toBe(3)
			t.expect((exportedLines[1]:find("> give me x", 1, true))):Not():toBeNil()
			t.expect((exportedLines[3]:find("! worse", 1, true))):Not():toBeNil()
		end)
	end)
end
