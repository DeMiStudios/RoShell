--!strict
--[[
	The network boundary: every payload arrives as `unknown` and must be narrowed or rejected; everything sent is
	sanitized.
]]

const Net = require("../../src/Shared/Net")
const Prng = require("../support/Prng")
const Runner = require("../Runner")

const function depth(value: unknown): number
	if type(value) ~= "table" then
		return 0
	end
	local deepest = 0
	for _, item in pairs(value) do
		deepest = math.max(deepest, depth(item))
	end
	return deepest + 1
end

return function(t: Runner.Api)
	t.describe("Run requests", function()
		t.it("accepts a well-formed request", function()
			const run = Net.ReadRun({
				Id = 3,
				Text = "kick Bob",
				Dry = true,
				Yes = false,
				IsHuman = true,
				Data = { Position = 5 },
				Pipe = { Ref = "12" },
			})
			t.expect(run ~= nil):toBe(true)
			if run then
				t.expect(run.Id):toBe(3)
				t.expect(run.Text):toBe("kick Bob")
				t.expect(run.Dry):toBe(true)
				t.expect(run.PipeRef):toBe("12")
				t.expect(run.PipeText):toBeNil()
			end
		end)

		t.it("rejects malformed requests", function()
			t.expect(Net.ReadRun(nil)):toBeNil()
			t.expect(Net.ReadRun("kick Bob")):toBeNil()
			t.expect(Net.ReadRun({ Id = 1 })):toBeNil()
			t.expect(Net.ReadRun({ Id = -1, Text = "x" })):toBeNil()
			t.expect(Net.ReadRun({ Id = 1.5, Text = "x" })):toBeNil()
			t.expect(Net.ReadRun({ Id = 1, Text = 42 })):toBeNil()
			t.expect(Net.ReadRun({ Id = 1, Text = string.rep("a", 9000) })):toBeNil()
		end)

		t.it("coerces flags to booleans and ignores unknown fields", function()
			const run = Net.ReadRun({
				Id = 1,
				Text = "x",
				Dry = "yes",
				Yes = 1,
				Evil = function()
				end,
			})
			t.expect(run and run.Dry):toBe(false)
			t.expect(run and run.Yes):toBe(false)
		end)
	end)

	t.describe("Other client messages", function()
		t.it("validates prompt answers, cancels and user data", function()
			const answer = Net.ReadPromptAnswer({ Id = 2, PromptId = 7, Answer = "yes" })
			t.expect(answer and answer.Answer):toBe("yes")
			t.expect(Net.ReadPromptAnswer({ Id = 2 })):toBeNil()
			t.expect(Net.ReadCancel({ Id = 4 })):toBe(4)
			t.expect(Net.ReadCancel({ Id = "4" })):toBeNil()
			const history = Net.ReadUserData({ Key = "History", Value = { "a", "b" } })
			t.expect(history and history.Key):toBe("History")
			t.expect(Net.ReadUserData({ Key = "Admin", Value = true })):toBeNil()
			t.expect(Net.ReadUserData({ Key = string.rep("k", 100), Value = 1 })):toBeNil()
		end)
	end)

	t.describe("Sanitize", function()
		t.it("drops functions and threads and bounds depth and size", function()
			const nested: { [string]: unknown } = {}
			local cursor = nested
			for _ = 1, 10 do
				const child: { [string]: unknown } = {}
				cursor.Child = child
				cursor = child
			end
			const sanitized = Net.Sanitize({
				Fn = function()
				end,
				Thread = coroutine.create(function()
				end),
				Deep = nested,
			})
			t.expect(type(sanitized)):toBe("table")
			t.expect(Net.Field(sanitized, "Fn")):toBeNil()
			t.expect(Net.Field(sanitized, "Thread")):toBeNil()
			t.expect(depth(sanitized) <= 4):toBe(true)

			const big: { number } = {}
			for index = 1, 1000 do
				big[index] = index
			end
			const trimmed = Net.Sanitize(big)
			local count = 0
			if type(trimmed) == "table" then
				for _ in pairs(trimmed) do
					count += 1
				end
			end
			t.expect(count <= 256):toBe(true)
			t.expect(Net.Sanitize(string.rep("x", 10000)) == string.rep("x", 4096)):toBe(true)
		end)
	end)

	t.describe("Server messages", function()
		t.it("narrows every block kind and drops unknown ones", function()
			const text = Net.ReadBlock({ Kind = "text", Text = "hi", Level = "bogus" })
			t.expect(text and text.Kind):toBe("text")
			if text and text.Kind == "text" then
				t.expect(text.Level):toBe("plain")
			end
			const tableBlock = Net.ReadBlock({ Kind = "table", Columns = { "A", 5 }, Rows = { { "x", true } } })
			if tableBlock and tableBlock.Kind == "table" then
				t.expect(tableBlock.Columns[2]):toBe("")
				t.expect(tableBlock.Rows[1][2]):toBe("")
			else
				error("table block was rejected", 0)
			end
			const progress = Net.ReadBlock({ Kind = "progress", Id = "p", Label = "x", Fraction = 7 })
			if progress and progress.Kind == "progress" then
				t.expect(progress.Fraction):toBe(1)
			else
				error("progress block was rejected", 0)
			end
			t.expect(Net.ReadBlock({ Kind = "script", Source = "bad" })):toBeNil()
			t.expect(Net.ReadBlock({ Kind = "color", Color = "red" })):toBeNil()
		end)

		t.it("narrows prompts and results", function()
			const prompt = Net.ReadPrompt({ Kind = "choice", Message = "Pick", Choices = { "a", 2, "b" } })
			t.expect(prompt and prompt.Choices and #prompt.Choices):toBe(2)
			t.expect(Net.ReadPrompt({ Kind = "eval", Message = "x" })):toBeNil()
			const result = Net.ReadResult({ Ok = true, Duration = "fast", Blocks = 3 })
			t.expect(result and result.Duration):toBe(0)
			t.expect(result and result.Blocks):toBe(3)
			t.expect(Net.ReadResult({ Ok = "yes" })):toBeNil()
		end)

		t.it("never errors on random payloads (fuzz)", function()
			const rng = Prng.new(77)
			const function randomValue(level: number): unknown
				const roll = rng:NextInteger(1, 7)
				if roll == 1 or level > 3 then
					return rng:NextInteger(-5, 5)
				elseif roll == 2 then
					return rng:Pick({ "text", "table", "list", "progress", "value", "link", "custom", "keyvalue" })
				elseif roll == 3 then
					return rng:NextInteger(0, 1) == 1
				elseif roll == 4 then
					return nil
				end
				const map: { [string]: unknown } = {}
				for _ = 1, rng:NextInteger(0, 5) do
					map[rng:Pick({ "Kind", "Text", "Id", "Items", "Rows", "Columns", "Entries", "Fraction", "Ok" })] = randomValue(
						level + 1
					)
				end
				return map
			end
			for _ = 1, 500 do
				const payload = randomValue(0)
				Net.ReadRun(payload)
				Net.ReadBlock(payload)
				Net.ReadPrompt(payload)
				Net.ReadResult(payload)
				Net.ReadUserData(payload)
				Net.Sanitize(payload)
			end
		end)
	end)

	t.describe("Rate limiting", function()
		t.it("refills tokens over time", function()
			const bucket: Net.Bucket = { Tokens = 2, Updated = 0 }
			t.expect(Net.Take(bucket, 0, 2, 1)):toBe(true)
			t.expect(Net.Take(bucket, 0, 2, 1)):toBe(true)
			t.expect(Net.Take(bucket, 0, 2, 1)):toBe(false)
			t.expect(Net.Take(bucket, 1, 2, 1)):toBe(true)
			t.expect(Net.Take(bucket, 100, 2, 1)):toBe(true)
			t.expect(bucket.Tokens <= 2):toBe(true)
		end)
	end)
end
