--!strict
const Command = require("../../src/Shared/Command")
const Docs = require("../../src/Shared/Docs")
const Runner = require("../Runner")
const Test = require("../../src/Shared/Test")
const TypeBuilder = require("../../src/Shared/TypeBuilder")

const Count = TypeBuilder.Integer({ Name = "count", Min = 1 })
const Mode = TypeBuilder.Choice<<"easy" | "hard">>({ Name = "mode", Choices = { "easy", "hard" } })

const double = Command.new({
	Name = "double",
	Description = "Doubles a number",
	Group = "Math",
	Examples = { { Text = "double 4", Description = "Prints 8" } },
	Args = {
		{ n = Command.Default(Count, "3", { Description = "The number" }) },
		{ mode = Command.Default(Mode, "easy") },
	},
}):Run(function(ctx, args)
	return ctx:Value(Count, args.n * 2, `{args.n * 2} ({args.mode})`)
end)

const nap = Command.new({ Name = "nap", Args = { { seconds = Command.Arg(TypeBuilder.Number()) } } }):Run(function(
	ctx,
	args
)
	ctx.Shell.Platform.Wait(args.seconds)
	return "rested"
end)

const ask = Command.new({ Name = "ask", Args = {} }):Run(function(ctx)
	if ctx:Confirm("Sure?") then
		return ctx:Success("confirmed")
	end
	return ctx:Warn("declined")
end)

return function(t: Runner.Api)
	t.describe("Test harness", function()
		t.it("runs a command and collects its output", function()
			const result = Test.Run({ Text = "double 5 hard", Commands = { double } })
			t.expect(result.Ok):toBe(true)
			t.expect(result.Value):toBe(10)
			t.expect(result.Output):toBe("10 (hard)")
		end)

		t.it("parses text defaults per run", function()
			const result = Test.Run({ Text = "double", Commands = { double } })
			t.expect(result.Value):toBe(6)
			t.expect(result.Output):toBe("6 (easy)")
		end)

		t.it("finishes waits on the virtual clock", function()
			const result = Test.Run({ Text = "nap 30", Commands = { nap } })
			t.expect(result.Ok):toBe(true)
			t.expect(result.TimedOut):toBe(false)
			t.expect(result.Output):toBe("rested")
		end)

		t.it("answers prompts in order", function()
			const harness = Test.new({ Commands = { ask } })
			t.expect(harness.Run("ask", { Answers = { "yes" } }).Output):toBe("confirmed")
			const declined = harness.Run("ask", { Answers = { "no" } })
			t.expect(declined.Output):toBe("declined")
			t.expect(#declined.Prompts):toBe(1)
		end)

		t.it("includes the built-in commands on request (client side)", function()
			const result = Test.Run({ Text = "echo hi && math 2 + 3", Defaults = true, Client = true })
			t.expect(result.Ok):toBe(true)
			t.expect(result.Lines[1]):toBe("hi")
		end)
	end)

	t.describe("Functions", function()
		const function run(text: string): string
			return Test.Run({ Text = text, Defaults = true, Client = true }).Output
		end

		t.it("substitutes built-in function calls", function()
			t.expect(run("echo $upper(hi there)")):toBe("HI THERE")
			t.expect(run("echo $lower(LOUD)")):toBe("loud")
			t.expect(run("echo $len(héllo)")):toBe("5")
			t.expect(run("echo $round(3.14159, 2)")):toBe("3.14")
			t.expect(run("echo $me()")):toBe("Server")
		end)

		t.it("keeps random results in range", function()
			for _ = 1, 20 do
				const value = tonumber(run("echo $random(3, 5)"))
				t.expect(value ~= nil and value >= 3 and value <= 5):toBe(true)
			end
			const picked = run("echo $pick(red, green)")
			t.expect(picked == "red" or picked == "green"):toBe(true)
		end)
	end)

	t.describe("Docs", function()
		t.it("builds a schema of commands and types", function()
			const harness = Test.new({ Commands = { double, nap } })
			const schema = Docs.Schema(harness.Shell.Registry)
			t.expect(#schema.Commands):toBe(2)
			const first = schema.Commands[1]
			t.expect(first.Name):toBe("double")
			t.expect(first.Args[1].Default):toBe("3")
			t.expect(first.Args[1].Description):toBe("The number")
			t.expect(#schema.Types > 0):toBe(true)
		end)

		t.it("renders Markdown grouped by command group", function()
			const harness = Test.new({ Commands = { double } })
			const markdown = Docs.Markdown(harness.Shell.Registry)
			t.expect((markdown:find("## Math", 1, true))):Not():toBeNil()
			t.expect((markdown:find("### `double`", 1, true))):Not():toBeNil()
			t.expect((markdown:find("| `n` | count | no | The number (default: 3) |", 1, true))):Not():toBeNil()
			t.expect((markdown:find("`double 4` — Prints 8", 1, true))):Not():toBeNil()
		end)
	end)
end
