--!strict
--[[
	Tiny benchmark harness: warm-up, timed iterations, median/p99, and a report table.
]]

--// Types
export type BenchResult = {
	Name: string,
	Median: number,
	P99: number,
	Iterations: number,
	--- Budget in seconds the median must stay under (reported, and enforced by `Bench.Check`).
	Budget: number?,
}

--// Helpers

const function percentile(samples: { number }, fraction: number): number
	const sorted = table.clone(samples)
	table.sort(sorted)
	return sorted[math.max(1, math.ceil(#sorted * fraction))]
end

--// Bench
const Bench = {}

--- Times `body` `iterations` times after three warm-up runs.
function Bench.Measure(name: string, iterations: number, body: () -> (), budget: number?): BenchResult
	for _ = 1, 3 do
		body()
	end
	const samples: { number } = {}
	for _ = 1, iterations do
		const started = os.clock()
		body()
		table.insert(samples, os.clock() - started)
	end
	return {
		Name = name,
		Median = percentile(samples, 0.5),
		P99 = percentile(samples, 0.99),
		Iterations = iterations,
		Budget = budget,
	}
end

--- Formats results as a Markdown table (milliseconds).
function Bench.Report(title: string, results: { BenchResult }): string
	const lines = {
		`### {title}`,
		"",
		"| Benchmark | Median (ms) | p99 (ms) | Budget (ms) |",
		"|---|---:|---:|---:|",
	}
	for _, result in results do
		const budget = if result.Budget then string.format("%.2f", result.Budget * 1000) else "—"
		table.insert(
			lines,
			string.format("| %s | %.3f | %.3f | %s |", result.Name, result.Median * 1000, result.P99 * 1000, budget)
		)
	end
	return table.concat(lines, "\n")
end

--- Names of results whose median exceeds their budget.
function Bench.Check(results: { BenchResult }): { string }
	const failures: { string } = {}
	for _, result in results do
		if result.Budget and result.Median > result.Budget then
			table.insert(failures, `{result.Name}: {string.format("%.3f", result.Median * 1000)} ms`)
		end
	end
	return failures
end

return table.freeze(Bench)
