--!strict
const Runner = require("../Runner")
const TestShell = require("../support/TestShell")
const Types = require("../../src/Shared/Types")

const function lastValue(result: Types.RunResult): unknown
	const last = result.Last
	return if last then last.Value else nil
end

const function lastMessage(result: Types.RunResult): string?
	const last = result.Last
	return if last then last.Message else nil
end

return function(t: Runner.Api)
	t.describe("Basics", function()
		t.it("runs a command and returns typed values", function()
			const harness = TestShell.new()
			const result = harness.Run("add 2 3")
			t.expect(result.Ok):toBe(true)
			t.expect(lastValue(result)):toBe(5)
			t.expect(harness.Texts()[1]):toBe("5")
		end)

		t.it("resolves aliases and is case-insensitive", function()
			const harness = TestShell.new()
			t.expect(harness.Run("SAY hello world").Ok):toBe(true)
			t.expect(harness.Texts()[1]):toBe("hello world")
		end)

		t.it("applies defaults", function()
			const harness = TestShell.new()
			t.expect(lastValue(harness.Run("add 7"))):toBe(7)
		end)

		t.it("reports unknown commands with suggestions", function()
			const harness = TestShell.new()
			const result = harness.Run("ad 1 2")
			t.expect(result.Ok):toBe(false)
			t.expect(lastMessage(result)):toContain("Did you mean 'add'?")
		end)

		t.it("reports missing and invalid arguments", function()
			const harness = TestShell.new()
			t.expect(lastMessage(harness.Run("double"))):toContain("Missing argument <n: number>")
			t.expect(lastMessage(harness.Run("add x"))):toContain("not a number")
		end)

		t.it("catches handler errors without breaking the dispatcher", function()
			const harness = TestShell.new()
			const result = harness.Run("throw")
			t.expect(result.Ok):toBe(false)
			t.expect(lastMessage(result)):toContain("kaboom")
			t.expect(harness.Run("add 1 1").Ok):toBe(true)
		end)

		t.it("refuses syntax errors without running anything", function()
			const harness = TestShell.new()
			const result = harness.Run("add 1 &&")
			t.expect(result.Ok):toBe(false)
			t.expect(lastMessage(result)):toContain("Syntax error")
		end)
	end)

	t.describe("Flags and named arguments", function()
		t.it("supports --flags, short clusters, --name value and name=value", function()
			const harness = TestShell.new()
			harness.Run("greet Bob --loud")
			t.expect(harness.Texts()[1]):toBe("HI BOB")
			harness.Run("greet Bob -l -t 2")
			t.expect(harness.Texts()[1]):toBe("HI BOB; HI BOB")
			harness.Run("greet Bob times=2 suffix=!")
			t.expect(harness.Texts()[1]):toBe("hi Bob!; hi Bob!")
			harness.Run("greet --times=2 Bob")
			t.expect(harness.Texts()[1]):toBe("hi Bob; hi Bob")
		end)

		t.it("reports unknown flags with suggestions", function()
			const harness = TestShell.new()
			t.expect(lastMessage(harness.Run("greet Bob --lod"))):toContain("Did you mean '--loud'?")
		end)

		t.it("validates flag values", function()
			const harness = TestShell.new()
			t.expect(lastMessage(harness.Run("greet Bob --times 9"))):toContain("at most 5")
		end)

		t.it("treats -- as the end of options", function()
			const harness = TestShell.new()
			harness.Run("echo -- --not-a-flag")
			t.expect(harness.Texts()[1]):toBe("--not-a-flag")
		end)

		t.it("merges excess words into a trailing string argument", function()
			const harness = TestShell.new()
			t.expect(lastMessage(harness.Run("add 1 2 3"))):toContain("Too many arguments")
		end)
	end)

	t.describe("Chains, pipes and embeds", function()
		t.it("runs && only after success and || only after failure", function()
			const harness = TestShell.new()
			harness.Run("fail && echo no || echo yes")
			const texts = harness.Texts()
			t.expect(texts[1]):toBe("boom")
			t.expect(texts[2]):toBe("yes")
			t.expect(#texts):toBe(2)
		end)

		t.it("runs statements separated by ; and newlines", function()
			const harness = TestShell.new()
			harness.Run("echo a; echo b\necho c")
			t.expect(harness.Texts()):toEqual({ "a", "b", "c" })
		end)

		t.it("pipes typed values into the pipe argument", function()
			const harness = TestShell.new()
			const result = harness.Run("add 2 3 | double | double")
			t.expect(lastValue(result)):toBe(20)
		end)

		t.it("stops a pipeline at the first failure", function()
			const harness = TestShell.new()
			const result = harness.Run("fail | double")
			t.expect(result.Ok):toBe(false)
			t.expect(lastMessage(result)):toBe("boom")
		end)

		t.it("rejects piping into commands without a pipe argument", function()
			const harness = TestShell.new()
			t.expect(lastMessage(harness.Run("add 1 2 | echo"))):toContain("does not accept piped input")
		end)

		t.it("substitutes embedded commands (nested)", function()
			const harness = TestShell.new()
			t.expect(lastValue(harness.Run("add ${add 1 2} ${add ${add 1 1} 2}"))):toBe(7)
		end)

		t.it("reports failing embeds", function()
			const harness = TestShell.new()
			t.expect(lastMessage(harness.Run("add ${fail} 1"))):toContain("Embedded command failed")
		end)

		t.it("substitutes variables and $$", function()
			const harness = TestShell.new()
			harness.Shell:GetSession(nil).Variables.who = "Carol"
			harness.Run("greet $who")
			t.expect(harness.Texts()[1]):toBe("hi Carol")
			harness.Run("add 20 1")
			t.expect(lastValue(harness.Run("double $$"))):toBe(42)
			t.expect(lastMessage(harness.Run("echo $nope"))):toContain("Unknown variable $nope")
		end)

		t.it("interpolates inside double quotes only", function()
			const harness = TestShell.new()
			harness.Shell:GetSession(nil).Variables.name = "Bob"
			harness.Run(`echo "hi $name" 'hi $name'`)
			t.expect(harness.Texts()[1]):toBe("hi Bob hi $name")
		end)
	end)

	t.describe("Aliases", function()
		t.it("binds $1..$9 to the alias words", function()
			const harness = TestShell.new()
			harness.Run("hello Ann Ben")
			t.expect(harness.Texts()[1]):toBe("hello Ann and Ben")
			t.expect(lastValue(harness.Run("twice 21"))):toBe(42)
		end)
	end)

	t.describe("Subcommands", function()
		t.it("dispatches to subcommands", function()
			const harness = TestShell.new()
			harness.Run("team add Bob")
			t.expect(harness.Texts()[1]):toBe("added Bob")
			t.expect(lastMessage(harness.Run("team ad Bob"))):toContain("Did you mean 'add'?")
			t.expect(lastMessage(harness.Run("team"))):toContain("Expected a subcommand")
		end)
	end)

	t.describe("Validation, confirmation and dry runs", function()
		t.it("runs cross-argument validation", function()
			const harness = TestShell.new()
			t.expect(lastMessage(harness.Run("range 5 1"))):toBe("low must not exceed high")
			t.expect(harness.Run("range 1 5").Ok):toBe(true)
		end)

		t.it("validates before a --dry preview", function()
			const harness = TestShell.new()
			const refused = harness.Run("range 5 1 --dry")
			t.expect(refused.Ok):toBe(false)
			t.expect(lastMessage(refused)):toBe("low must not exceed high")
			t.expect(harness.Run("range 1 5 --dry").Ok):toBe(true)
		end)

		t.it("asks before destructive commands", function()
			const harness = TestShell.new()
			table.insert(harness.Answers, "no")
			t.expect(lastMessage(harness.Run("danger"))):toBe("Declined")
			table.insert(harness.Answers, "yes")
			t.expect(harness.Run("danger").Ok):toBe(true)
			t.expect(harness.Run("danger --yes").Ok):toBe(true)
			t.expect(#harness.Prompts):toBe(2)
		end)

		t.it("shows previews for --dry", function()
			const harness = TestShell.new()
			const result = harness.Run("wipe Bob --dry")
			t.expect(result.Ok):toBe(true)
			const block = harness.Blocks[1]
			t.expect(block.Kind):toBe("list")
			if block.Kind == "list" then
				t.expect(block.Items[1]):toBe("Would wipe Bob")
			end
			t.expect(lastMessage(harness.Run("add 1 2 --dry"))):toContain("does not support --dry")
		end)
	end)

	t.describe("Timeouts and cancellation", function()
		t.it("times out long commands", function()
			const harness = TestShell.new()
			local result: Types.RunResult? = nil
			const thread = coroutine.create(function()
				result = harness.Run("slow 10")
			end)
			coroutine.resume(thread)
			harness.Controller:Advance(6)
			harness.Controller:Flush()
			t.expect(result ~= nil):toBe(true)
			if result then
				t.expect(lastMessage(result)):toContain("timed out")
			end
		end)

		t.it("finishes when within the timeout", function()
			const harness = TestShell.new()
			local result: Types.RunResult? = nil
			const thread = coroutine.create(function()
				result = harness.Run("slow 1")
			end)
			coroutine.resume(thread)
			harness.Controller:Advance(2)
			t.expect(result ~= nil and result.Ok):toBe(true)
		end)
	end)

	t.describe("Evaluate", function()
		t.it("validates without running and defers embeds", function()
			const harness = TestShell.new()
			const evaluation = harness.Evaluate("add ${add 1 2} x")
			t.expect(evaluation.Ok):toBe(false)
			t.expect(#evaluation.Commands):toBe(2)
			const outer = evaluation.Commands[1]
			t.expect(outer.Args[1].Deferred):toBe(true)
			t.expect(outer.Args[2].Ok):toBe(false)
			t.expect(harness.Evaluate("add 1 2 | double").Ok):toBe(true)
		end)

		t.it("reports diagnostics with spans", function()
			const harness = TestShell.new()
			const evaluation = harness.Evaluate("greet Bob --times nine")
			t.expect(evaluation.Ok):toBe(false)
			const span = evaluation.Diagnostics[1].Span
			t.expect(("greet Bob --times nine"):sub(span.Start, span.End - 1)):toBe("nine")
		end)
	end)
end
