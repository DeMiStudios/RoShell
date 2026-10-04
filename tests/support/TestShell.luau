--!strict
--[[
	A headless server-side shell with a handful of test commands, for dispatcher/resolver/completion specs.
]]

const Command = require("../../src/Shared/Command")
const Platform = require("../../src/Shared/Platform")
const Shell = require("../../src/Shared/Shell")
const TypeBuilder = require("../../src/Shared/TypeBuilder")
const Types = require("../../src/Shared/Types")

export type TestShell = {
	Shell: Types.Shell,
	Controller: Platform.HeadlessController,
	Blocks: { Types.Block },
	--- Answers given to prompts, in order ("yes"/"no"/text). Empty -> prompts are cancelled.
	Answers: { string },
	Prompts: { Types.PromptRequest },
	Run: (text: string, options: Types.RunOptions?) -> Types.RunResult,
	Evaluate: (text: string) -> Types.EvaluateResult,
	Texts: () -> { string },
}

const People = TypeBuilder.Dynamic({
	Name = "person",
	Plural = "people",
	Candidates = function(): { Types.Candidate<string> }
		return {
			{ Key = "Alice", Value = "Alice" },
			{ Key = "Bob", Value = "Bob" },
			{ Key = "Carol", Value = "Carol" },
		}
	end,
	Default = function(): string?
		return "Alice"
	end,
})
const PeopleList = TypeBuilder.List(People, { Name = "people" })
const Num = TypeBuilder.Number()
const Text = TypeBuilder.String()

const function buildCommands(log: { string }): { Types.Command }
	const echo = Command.new({
		Name = "echo",
		Aliases = { "say" },
		Description = "Prints text",
		Args = { { text = Command.Rest(Text) } },
	}):Run(function(_ctx, args)
		return table.concat(args.text, " ")
	end)

	const add = Command.new({
		Name = "add",
		Description = "Adds two numbers",
		Returns = Num,
		Args = { { a = Command.Arg(Num) }, { b = Command.Default(Num, 0) } },
	}):Run(function(ctx, args)
		return ctx:Value(Num, args.a + args.b)
	end)

	const double = Command.new({
		Name = "double",
		Pipe = "n",
		Returns = Num,
		Args = { { n = Command.Arg(Num) } },
	}):Run(function(ctx, args)
		return ctx:Value(Num, args.n * 2)
	end)

	const fail = Command.new({ Name = "fail", Args = {} }):Run(function(ctx)
		return ctx:Error("boom")
	end)

	const throw = Command.new({ Name = "throw", Args = {} }):Run(function()
		error("kaboom")
	end)

	const greet = Command.new({
		Name = "greet",
		Args = {
			{ who = Command.Arg(PeopleList) },
			{ loud = Command.Flag({ Short = "l" }) },
			{ times = Command.Default(TypeBuilder.Integer({ Min = 1, Max = 5 }), 1, { Short = "t" }) },
			{ suffix = Command.Optional(Text, { Named = true }) },
		},
	}):Run(function(ctx, args)
		const parts: { string } = {}
		for _ = 1, args.times do
			for _, name in args.who do
				const line = `hi {name}{args.suffix or ""}`
				table.insert(parts, if args.loud then line:upper() else line)
			end
		end
		return ctx:Value(PeopleList, args.who, table.concat(parts, "; "))
	end)

	const danger = Command.new({ Name = "danger", Destructive = true, Args = {} }):Run(function(ctx)
		return ctx:Success("boom done")
	end)

	const slow = Command.new({ Name = "slow", Timeout = 5, Args = { { seconds = Command.Arg(Num) } } }):Run(function(
		ctx,
		args
	)
		ctx.Shell.Platform.Wait(args.seconds)
		ctx:CheckCancelled()
		return "finished"
	end)

	const preview = Command.new({ Name = "wipe", SupportsDryRun = true, Args = { { who = Command.Arg(People) } } }):Preview(function(
		_ctx,
		args
	)
		return { `Would wipe {args.who}` }
	end):Run(function(ctx, args)
		table.insert(log, "wiped " .. args.who)
		return ctx:Success(`Wiped {args.who}`)
	end)

	const team = Command.new({
		Name = "team",
		Args = {},
		Subcommands = {
			Command.new({ Name = "add", Args = { { who = Command.Arg(People) } } }):Run(function(_ctx, args)
				return `added {args.who}`
			end),
			Command.new({ Name = "list", Args = {} }):Run(function()
				return "team list"
			end),
		},
	})

	const checked = Command.new({
		Name = "range",
		SupportsDryRun = true,
		Args = { { low = Command.Arg(Num) }, { high = Command.Arg(Num) } },
	}):Validate(function(_ctx, args)
		return args.low <= args.high, "low must not exceed high"
	end):Preview(function(_ctx, args)
		return { `Would cover {args.low}..{args.high}` }
	end):Run(function(_ctx, args)
		return `{args.low}..{args.high}`
	end)

	return { echo, add, double, fail, throw, greet, danger, slow, preview, team, checked }
end

const TestShell = {}

TestShell.People = People
TestShell.PeopleList = PeopleList

function TestShell.new(): TestShell
	const controller = Platform.Headless(99)
	const shell = Shell.new({ IsServer = true, IsClient = false, Platform = controller.Platform })
	const log: { string } = {}
	shell.Registry:RegisterCommands(buildCommands(log))
	shell.Registry:RegisterCommand(Command.Alias("hello", "echo hello $1 and $2"))
	shell.Registry:RegisterCommand(Command.Alias("twice", "add $1 $1"))

	const blocks: { Types.Block } = {}
	const answers: { string } = {}
	const prompts: { Types.PromptRequest } = {}
	const harness: TestShell = {
		Shell = shell,
		Controller = controller,
		Blocks = blocks,
		Answers = answers,
		Prompts = prompts,
		Run = function(text: string, options: Types.RunOptions?): Types.RunResult
			table.clear(blocks)
			return shell.Dispatcher:Run({
				Text = text,
				Options = options,
				OnBlock = function(block: Types.Block)
					table.insert(blocks, block)
				end,
				OnPrompt = function(prompt: Types.PromptRequest): Types.PromptAnswer
					table.insert(prompts, prompt)
					return table.remove(answers, 1)
				end,
			})
		end,
		Evaluate = function(text: string): Types.EvaluateResult
			return shell.Dispatcher:Evaluate({ Text = text })
		end,
		Texts = function(): { string }
			const texts: { string } = {}
			for _, block in blocks do
				if block.Kind == "text" then
					table.insert(texts, block.Text)
				elseif block.Kind == "value" then
					table.insert(texts, block.Display)
				end
			end
			return texts
		end,
	}
	return harness
end

return table.freeze(TestShell)
