--!strict
const Fuzzy = require("../../src/Shared/Fuzzy")
const Prng = require("../support/Prng")
const Runner = require("../Runner")

const function score(query: string, text: string): number?
	return Fuzzy.Score(Fuzzy.PrepareQuery(query), Fuzzy.Prepare(text))
end

const function scoreOf(query: string, text: string): number
	const value = score(query, text)
	assert(value ~= nil, `expected '{query}' to match '{text}'`)
	return value
end

const function highlighted(query: string, text: string): string
	const match = Fuzzy.Match(Fuzzy.PrepareQuery(query), Fuzzy.Prepare(text))
	assert(match, "expected a match")
	const parts: { string } = {}
	for _, range in match.Ranges do
		table.insert(parts, text:sub(range.Start, range.End - 1))
	end
	return table.concat(parts, "|")
end

const function identity(item: string): string
	return item
end

return function(t: Runner.Api)
	t.describe("Prepare", function()
		t.it("records codepoints, offsets and a mask", function()
			const prepared = Fuzzy.Prepare("héllo")
			t.expect(prepared.Length):toBe(5)
			t.expect(prepared.Offsets[1]):toBe(1)
			t.expect(prepared.Offsets[3]):toBe(4) -- the accented character is two bytes
			t.expect(prepared.Mask):Not():toBe(0)
		end)

		t.it("caches prepared strings", function()
			t.expect(Fuzzy.PrepareCached("sword")):toBe(Fuzzy.PrepareCached("sword"))
		end)
	end)

	t.describe("Score", function()
		t.it("rejects non-subsequences", function()
			t.expect(score("xyz", "sword")):toBeNil()
			t.expect(score("swordd", "sword")):toBeNil()
		end)

		t.it("matches subsequences with smart case", function()
			t.expect(score("swd", "Sword")):Not():toBeNil()
			t.expect(score("SWD", "sword")):toBeNil()
			t.expect(score("SwD", "SwordDance")):Not():toBeNil()
		end)

		t.it("ranks exact > prefix > subsequence", function()
			const exact = scoreOf("give", "give")
			const prefix = scoreOf("give", "giveall")
			const sub = scoreOf("give", "forgiveness")
			t.expect(exact):toBeGreaterThan(prefix)
			t.expect(prefix):toBeGreaterThan(sub)
		end)

		t.it("prefers consecutive and boundary matches", function()
			t.expect(scoreOf("sw", "Sword of Embers")):toBeGreaterThan(scoreOf("sw", "Shadow"))
			t.expect(scoreOf("soe", "Sword of Embers")):toBeGreaterThan(scoreOf("soe", "shoes"))
			t.expect(scoreOf("tp", "teleport-player")):toBeGreaterThan(scoreOf("tp", "attempt"))
		end)

		t.it("supports multi-term queries in any order", function()
			t.expect(score("red sw", "Red Sword")):Not():toBeNil()
			t.expect(score("sw red", "Red Sword")):Not():toBeNil()
			t.expect(score("red axe", "Red Sword")):toBeNil()
		end)

		t.it("matches everything for an empty query", function()
			t.expect(score("", "anything")):toBe(0)
			t.expect(score("   ", "anything")):toBe(0)
		end)

		t.it("is unicode safe", function()
			t.expect(score("hw", "héllo wörld")):Not():toBeNil()
			t.expect(highlighted("wö", "héllo wörld")):toBe("wö")
		end)
	end)

	t.describe("Match ranges", function()
		t.it("highlights the optimal alignment", function()
			t.expect(highlighted("sw", "Shadow Sword")):toBe("Sw")
			t.expect(highlighted("soe", "Sword of Embers")):toBe("S|o|E")
			t.expect(highlighted("give", "give")):toBe("give")
		end)

		t.it("produces valid, ordered, non-overlapping ranges (property)", function()
			const rng = Prng.new(1234)
			for _ = 1, 400 do
				const text = rng:NextString("abcAB_- ./éx1", 0, 24)
				const query = rng:NextString("abAéx_ ", 0, 4)
				const prepared = Fuzzy.Prepare(text)
				const preparedQuery = Fuzzy.PrepareQuery(query)
				const scored = Fuzzy.Score(preparedQuery, prepared)
				const match = Fuzzy.Match(preparedQuery, prepared)
				-- Score and Match agree on whether there is a match, and on the score.
				t.expect(scored == nil):toBe(match == nil)
				if match and scored then
					t.expect(match.Score):toBeCloseTo(scored, 1e-6)
					local previousEnd = 0
					for _, range in match.Ranges do
						t.expect(range.Start >= 1 and range.End <= #text + 1 and range.Start < range.End):toBe(true)
						t.expect(range.Start >= previousEnd):toBe(true)
						previousEnd = range.End
					end
				end
				-- Idempotence.
				t.expect(Fuzzy.Score(preparedQuery, Fuzzy.Prepare(text))):toBe(scored)
			end
		end)

		t.it("a longer prefix of the same candidate never scores lower (monotonic property)", function()
			const rng = Prng.new(99)
			for _ = 1, 200 do
				const text = rng:NextString("abcdefg", 4, 16)
				const prefixLength = rng:NextInteger(1, #text - 1)
				const shorter = scoreOf(text:sub(1, prefixLength), text)
				const longer = scoreOf(text:sub(1, prefixLength + 1), text)
				t.expect(longer >= shorter):toBe(true)
			end
		end)
	end)

	t.describe("Filter", function()
		t.it("returns the best K in descending order", function()
			const items = { "give", "grant", "god", "giveall", "forgive", "kick", "gravity" }
			const results = Fuzzy.Filter("giv", items, identity, 3)
			t.expect(#results):toBe(3)
			t.expect(results[1].Item):toBe("give")
			t.expect(results[1].Score >= results[2].Score and results[2].Score >= results[3].Score):toBe(true)
		end)

		t.it("matches a full sort (property)", function()
			const rng = Prng.new(7)
			const items: { string } = {}
			for _ = 1, 300 do
				table.insert(items, rng:NextString("abcdefgh_", 1, 12))
			end
			const query = Fuzzy.PrepareQuery("abc")
			const all: { number } = {}
			for _, item in items do
				const value = Fuzzy.Score(query, Fuzzy.PrepareCached(item))
				if value then
					table.insert(all, value)
				end
			end
			table.sort(all, function(a: number, b: number): boolean
				return a > b
			end)
			const top = Fuzzy.Filter(query, items, identity, 10)
			for index, result in top do
				t.expect(result.Score):toBeCloseTo(all[index], 1e-9)
			end
		end)
	end)

	t.describe("Suggest", function()
		t.it("finds typos and abbreviations", function()
			t.expect(Fuzzy.Suggest("swrod", { "sword", "shield", "bow" })):toBe("sword")
			t.expect(Fuzzy.Suggest("tleport", { "teleport", "kick" })):toBe("teleport")
			t.expect(Fuzzy.Suggest("zzzz", { "teleport", "kick" })):toBeNil()
		end)
	end)
end
