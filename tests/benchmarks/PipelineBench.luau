--!strict
--[[
	Per-keystroke pipeline benchmarks (spec §11): lexing/parsing long input, live evaluation, and completion
	against a registry of 500 commands with a 200-candidate argument type, plus the 10 000-candidate worst case.

	Budgets: completion for one keystroke ≤ 1 ms median with ≤ 500 commands and ≤ 200 candidates; ≤ 4 ms with
	10 000 candidates.
]]

const Bench = require("./Bench")
const Command = require("../../src/Shared/Command")
const Completion = require("../../src/Shared/Completion")
const FuzzyBench = require("./FuzzyBench")
const Lexer = require("../../src/Shared/Lexer")
const Parser = require("../../src/Shared/Parser")
const Platform = require("../../src/Shared/Platform")
const Shell = require("../../src/Shared/Shell")
const TypeBuilder = require("../../src/Shared/TypeBuilder")
const Types = require("../../src/Shared/Types")

const PipelineBench = {}

const function catalog(name: string, count: number): Types.Type<string>
	const names = FuzzyBench.Candidates(count, count)
	const candidates: { Types.Candidate<string> } = {}
	for _, item in names do
		table.insert(candidates, { Key = item, Value = item })
	end
	return TypeBuilder.Dynamic({
		Name = name,
		Candidates = function(): { Types.Candidate<string> }
			return candidates
		end,
		CacheSeconds = 60,
	})
end

const function buildShell(): Types.Shell
	const controller = Platform.Headless(7)
	const shell = Shell.new({ IsServer = true, IsClient = false, Platform = controller.Platform })
	const items = catalog("item", 200)
	const huge = catalog("asset", 10000)
	const commands: { Types.Command } = {}
	const nouns = FuzzyBench.Candidates(500, 99)
	for index = 1, 500 do
		const name = (nouns[index]:lower():gsub("%s+", "-"))
		table.insert(
			commands,
			Command.new({
				Name = name,
				Description = `Benchmark command {index}`,
				Args = {
					{ item = Command.Arg(items) },
					{ amount = Command.Default(TypeBuilder.Integer({ Min = 1 }), 1) },
				},
			}):Run(function()
				return nil
			end)
		)
	end
	table.insert(
		commands,
		Command.new({
			Name = "spawn",
			Args = { { asset = Command.Arg(huge) }, { count = Command.Arg(TypeBuilder.Number()) } },
		}):Run(function()
			return nil
		end)
	)
	shell.Registry:RegisterCommands(commands)
	return shell
end

function PipelineBench.Run(): { Bench.BenchResult }
	const shell = buildShell()
	const results: { Bench.BenchResult } = {}
	const commandName = shell.Registry:GetCommands()[1].Name

	-- Lexing/parsing a long script (memoization disabled by varying the text).
	const longScript = string.rep('give me "Sword of Embers" 3 && echo ${add 1 2} | double; ', 40)
	local counter = 0
	table.insert(
		results,
		Bench.Measure(
			"Lexer.Tokenize 2.3 KB script",
			100,
			function()
				Lexer.Tokenize(longScript)
			end,
			0.004
		)
	)
	table.insert(
		results,
		Bench.Measure(
			"Parser.Parse 2.3 KB script",
			100,
			function()
				counter += 1
				Parser.Parse(longScript .. tostring(counter))
			end,
			0.008
		)
	)

	-- One keystroke: evaluate + complete, as the console does.
	const typed = `{commandName} Shadow Bla`
	table.insert(
		results,
		Bench.Measure(
			"Evaluate (500 cmds, 200 candidates)",
			200,
			function()
				shell.Dispatcher:Evaluate({ Text = typed })
			end,
			0.001
		)
	)
	table.insert(
		results,
		Bench.Measure(
			"Complete argument (500 cmds, 200 candidates)",
			200,
			function()
				Completion.Query({ Shell = shell, Text = typed, Cursor = #typed + 1, Limit = 50 })
			end,
			0.001
		)
	)
	table.insert(
		results,
		Bench.Measure(
			"Complete command name (500 cmds)",
			200,
			function()
				Completion.Query({ Shell = shell, Text = "sha", Cursor = 4, Limit = 50 })
			end,
			0.001
		)
	)
	const hugeTyped = "spawn mythic st"
	table.insert(
		results,
		Bench.Measure(
			"Complete argument (10 000 candidates)",
			30,
			function()
				Completion.Query({ Shell = shell, Text = hugeTyped, Cursor = #hugeTyped + 1, Limit = 50 })
			end,
			0.004
		)
	)
	return results
end

return table.freeze(PipelineBench)
