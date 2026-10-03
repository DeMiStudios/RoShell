--!strict
--[[
	Fuzzy benchmark: 10 000 realistic candidates, several queries, top-8 selection.
	Budget (spec §7.2): 10 000 candidates scored in under 4 ms.
]]

const Bench = require("./Bench")
const Fuzzy = require("../../src/Shared/Fuzzy")
const Prng = require("../support/Prng")

const WORDS = {
	"sword",
	"shadow",
	"ember",
	"frost",
	"dragon",
	"shield",
	"potion",
	"arrow",
	"crystal",
	"golden",
	"ancient",
	"iron",
	"wooden",
	"mythic",
	"storm",
	"blade",
	"helm",
	"boots",
	"ring",
	"amulet",
	"staff",
	"wand",
	"axe",
}

const FuzzyBench = {}

--- Candidate names like "Shadow Blade 42".
function FuzzyBench.Candidates(count: number, seed: number?): { string }
	const rng = Prng.new(seed or 42)
	const items: { string } = {}
	for index = 1, count do
		const words: { string } = {}
		for _ = 1, rng:NextInteger(1, 3) do
			const word = rng:Pick(WORDS)
			table.insert(words, word:sub(1, 1):upper() .. word:sub(2))
		end
		table.insert(items, table.concat(words, " ") .. " " .. tostring(index))
	end
	return items
end

const function identity(item: string): string
	return item
end

function FuzzyBench.Run(): { Bench.BenchResult }
	const candidates = FuzzyBench.Candidates(10000)
	const results: { Bench.BenchResult } = {}
	for _, query in { "sw", "frost bl", "gdh", "mythic staff 9", "zzq" } do
		const prepared = Fuzzy.PrepareQuery(query)
		table.insert(
			results,
			Bench.Measure(
				`Fuzzy.Filter 10k "{query}"`,
				30,
				function()
					Fuzzy.Filter(prepared, candidates, identity, 8)
				end,
				0.004
			)
		)
	end
	const small = FuzzyBench.Candidates(200)
	table.insert(
		results,
		Bench.Measure(
			'Fuzzy.Filter 200 "sw"',
			200,
			function()
				Fuzzy.Filter("sw", small, identity, 8)
			end,
			0.001
		)
	)
	return results
end

return table.freeze(FuzzyBench)
