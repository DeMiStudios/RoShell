--!strict
const Platform = require("../../src/Shared/Platform")
const Runner = require("../Runner")
const Shell = require("../../src/Shared/Shell")
const Types = require("../../src/Shared/Types")

type Harness = {
	Shell: Types.Shell,
	Run: (text: string) -> (Types.RunResult, { string }),
}

const function harness(): Harness
	const shell = Shell.new({ IsServer = false, IsClient = true, Platform = Platform.Headless(7).Platform })
	shell.Registry:RegisterDefaultCommands()
	return {
		Shell = shell,
		Run = function(text: string): (Types.RunResult, { string })
			const lines: { string } = {}
			const result = shell.Dispatcher:Run({
				Text = text,
				OnBlock = function(block: Types.Block)
					if block.Kind == "text" then
						table.insert(lines, block.Text)
					elseif block.Kind == "value" then
						table.insert(lines, block.Display)
					elseif block.Kind == "list" then
						table.insert(lines, `[{#block.Items} items]`)
					end
				end,
			})
			return result, lines
		end,
	}
end

const function lastValue(result: Types.RunResult): unknown
	const last = result.Last
	return if last then last.Value else nil
end

return function(t: Runner.Api)
	t.it("registers every built-in command", function()
		const h = harness()
		for _, name in {
			"help",
			"echo",
			"math",
			"alias",
			"set",
			"kick",
			"teleport",
			"inspect",
			"in",
			"every",
			"schedules",
		} do
			t.expect(h.Shell.Registry:GetCommand(name) ~= nil):toBe(true)
		end
	end)

	t.it("echo and math return typed values", function()
		const h = harness()
		const _, lines = h.Run('echo "hello world"')
		t.expect(lines[1]):toBe("hello world")
		t.expect(lastValue(h.Run("math (2 + 3) * 4"))):toBe(20)
		t.expect(lastValue(h.Run("calc 2 ^ 10"))):toBe(1024)
		const failed = h.Run("math 1 +")
		t.expect(failed.Ok):toBe(false)
	end)

	t.it("pipes math into math through $$ and variables", function()
		const h = harness()
		h.Run("set base 21")
		t.expect(lastValue(h.Run("math $base * 2"))):toBe(42)
		h.Run("math 10")
		t.expect(lastValue(h.Run("math $$ + 1"))):toBe(11)
		t.expect(lastValue(h.Run("get base"))):toBe("21")
		h.Run("unset base")
		t.expect(h.Run("get base").Ok):toBe(false)
	end)

	t.it("defines aliases with parameters and validates their bodies", function()
		const h = harness()
		t.expect(h.Run('alias double = "math $1 * 2"').Ok):toBe(true)
		t.expect(lastValue(h.Run("double 21"))):toBe(42)
		t.expect(h.Run('alias broken = "nosuchcommand 1"').Ok):toBe(false)
		t.expect(h.Run('alias bad = "echo &&"').Ok):toBe(false)
		t.expect(h.Run("unalias double").Ok):toBe(true)
		t.expect(h.Shell.Registry:GetCommand("double")):toBeNil()
	end)

	t.it("runif runs only when the condition holds", function()
		const h = harness()
		const _, yes = h.Run("runif equals a a echo yes")
		t.expect(yes[1]):toBe("yes")
		const _, no = h.Run("runif > 1 2 echo never")
		t.expect(no[1]):toBe("Condition not met")
	end)

	t.it("replace and len work on text", function()
		const h = harness()
		t.expect(lastValue(h.Run("replace hello l L"))):toBe("heLLo")
		t.expect(lastValue(h.Run("replace a.b . - --plain"))):toBe("a-b")
		t.expect(lastValue(h.Run("len héllo"))):toBe(5)
	end)

	t.it("help explains commands, types and operators", function()
		const h = harness()
		t.expect(h.Run("help").Ok):toBe(true)
		const result, lines = h.Run("help echo")
		t.expect(result.Ok):toBe(true)
		t.expect(lines[1]):toContain("echo <...text: string>")
		t.expect(h.Run("help players").Ok):toBe(true)
		t.expect(h.Run("help operators").Ok):toBe(true)
		t.expect(h.Run("types").Ok):toBe(true)
		t.expect(h.Run("commands").Ok):toBe(true)
	end)

	t.it("random stays within bounds", function()
		const h = harness()
		for _ = 1, 20 do
			const value = lastValue(h.Run("random 3 5"))
			t.expect(type(value) == "number" and value >= 3 and value <= 5):toBe(true)
		end
	end)

	t.it("console commands explain when there is no console", function()
		const h = harness()
		const result = h.Run("clear")
		t.expect(result.Ok):toBe(false)
	end)
end
