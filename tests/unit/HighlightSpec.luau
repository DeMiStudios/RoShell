--!strict
const Highlight = require("../../src/Client/UI/Highlight")
const Runner = require("../Runner")
const TestShell = require("../support/TestShell")

const function classAt(runs: { Highlight.Run }, position: number): Highlight.SyntaxClass?
	for _, run in runs do
		if position >= run.Start and position < run.End then
			return run.Class
		end
	end
	return nil
end

const function underlinedAt(runs: { Highlight.Run }, position: number): boolean
	for _, run in runs do
		if position >= run.Start and position < run.End then
			return run.Underline
		end
	end
	return false
end

const function colorOf(class: Highlight.SyntaxClass, _token: string?): string?
	return if class == "plain" then nil else "#" .. class:sub(1, 1):rep(6):gsub("%a", "a")
end

return function(t: Runner.Api)
	t.describe("Classify", function()
		t.it("colors lexical tokens without an evaluation", function()
			const text = 'say "hi there" $name && echo ok # note'
			const runs = Highlight.Classify(text, nil)
			t.expect(classAt(runs, 5)):toBe("string")
			t.expect(classAt(runs, 16)):toBe("variable")
			t.expect(classAt(runs, 22)):toBe("operator")
			t.expect(classAt(runs, #text)):toBe("comment")
		end)

		t.it("covers the whole text with contiguous runs", function()
			const text = "give me ~emb 3 --silent"
			const runs = Highlight.Classify(text, nil)
			local expected = 1
			for _, run in runs do
				t.expect(run.Start):toBe(expected)
				expected = run.End
			end
			t.expect(expected):toBe(#text + 1)
			t.expect(classAt(runs, 16)):toBe("flag")
		end)

		t.it("uses the evaluation for command names and argument types", function()
			const harness = TestShell.new()
			const text = "add 1 2"
			const runs = Highlight.Classify(text, harness.Evaluate(text))
			t.expect(classAt(runs, 1)):toBe("command")
			t.expect(classAt(runs, 5)):toBe("number")
		end)

		t.it("flags unknown commands and invalid arguments", function()
			const harness = TestShell.new()
			const unknown = "nope 1"
			const runs = Highlight.Classify(unknown, harness.Evaluate(unknown))
			t.expect(classAt(runs, 1)):toBe("error")
			t.expect(underlinedAt(runs, 1)):toBe(true)

			const invalid = "add x"
			const invalidRuns = Highlight.Classify(invalid, harness.Evaluate(invalid))
			t.expect(classAt(invalidRuns, 5)):toBe("error")
		end)

		t.it("does not flag the word still being typed", function()
			const harness = TestShell.new()
			const text = "ech"
			const runs = Highlight.Classify(text, harness.Evaluate(text), { Start = 1, End = 4 })
			t.expect(classAt(runs, 1)):Not():toBe("error")
			t.expect(underlinedAt(runs, 1)):toBe(false)
		end)
	end)

	t.describe("Render", function()
		t.it("escapes markup and appends ghost text", function()
			const text = "echo <b>&"
			const rich = Highlight.Render(text, Highlight.Classify(text, nil), colorOf, "more", "#777777")
			t.expect((rich:find("<b>", 1, true))):toBeNil()
			t.expect((rich:find("&lt;b&gt;&amp;", 1, true))):Not():toBeNil()
			t.expect((rich:find('transparency="0.35">more</font>', 1, true))):Not():toBeNil()
		end)

		t.it("renders plain runs without tags", function()
			const rich = Highlight.Render("hello", Highlight.Classify("hello", nil), colorOf, nil, nil)
			t.expect(rich):toBe("hello")
		end)
	end)
end
