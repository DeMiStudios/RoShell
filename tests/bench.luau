--!strict
--[[
	Benchmark entry: `bash scripts/run.sh tests/bench.luau --codegen` (without `--codegen` for the interpreter).
	Prints Markdown tables (pasted into docs/BENCHMARKS.md) and fails when a median exceeds its budget.
--]]

const Bench = require(script.Parent.benchmarks.Bench)
const FuzzyBench = require(script.Parent.benchmarks.FuzzyBench)
const PipelineBench = require(script.Parent.benchmarks.PipelineBench)

const fuzzy = FuzzyBench.Run()
const pipeline = PipelineBench.Run()
print(Bench.Report("Fuzzy matching", fuzzy))
print("")
print(Bench.Report("Per-keystroke pipeline", pipeline))

const failures: { string } = {}
for _, group in { fuzzy, pipeline } do
	for _, failure in Bench.Check(group) do
		table.insert(failures, failure)
	end
end
if #failures > 0 then
	error("over budget:\n" .. table.concat(failures, "\n"), 0)
end
