--!strict
--[[
	Fuzzy benchmark: 10 000 realistic candidates, several queries, top-8 selection.
	Run headless: `luau --codegen tests/benchmarks/FuzzyBench.luau`, or from Studio through tests/Studio.luau.
]]

const Fuzzy = require("../../src/Shared/Fuzzy")
const Prng = require("../support/Prng")

export type BenchResult = { Name: string, Median: number, P99: number, Iterations: number }

const WORDS = {
	"sword", "shadow", "ember", "frost", "dragon", "shield", "potion", "arrow", "crystal", "golden", "ancient",
	"iron", "wooden", "mythic", "storm", "blade", "helm", "boots", "ring", "amulet", "staff", "wand", "axe",
}

const function buildCandidates(count: number): { string }
	const rng = Prng.new(42)
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

const function percentile(samples: { number }, fraction: number): number
	table.sort(samples)
	return samples[math.max(1, math.ceil(#samples * fraction))]
end

const function measure(name: string, iterations: number, body: () -> ()): BenchResult
	-- Warm-up (also fills the prepare cache, like a live registry would).
	for _ = 1, 3 do
		body()
	end
	const samples: { number } = {}
	for _ = 1, iterations do
		const started = os.clock()
		body()
		table.insert(samples, os.clock() - started)
	end
	return { Name = name, Median = percentile(samples, 0.5), P99 = percentile(samples, 0.99), Iterations = iterations }
end

const function run(): { BenchResult }
	const candidates = buildCandidates(10000)
	const identity = function(item: string): string
		return item
	end
	const results: { BenchResult } = {}
	for _, query in { "sw", "frost bl", "gdh", "mythic staff 9", "zzq" } do
		const prepared = Fuzzy.PrepareQuery(query)
		table.insert(
			results,
			measure(`Filter 10k "{query}"`, 30, function()
				Fuzzy.Filter(prepared, candidates, identity, 8)
			end)
		)
	end
	const small = buildCandidates(200)
	table.insert(
		results,
		measure("Filter 200 \"sw\"", 200, function()
			Fuzzy.Filter("sw", small, identity, 8)
		end)
	)
	return results
end

const results = run()
for _, result in results do
	print(string.format("%-28s median %7.3f ms   p99 %7.3f ms", result.Name, result.Median * 1000, result.P99 * 1000))
end

return results
