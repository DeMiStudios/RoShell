--!strict
--[[
	Scheduling and scripts: in, every, repeat, schedules, cancel, run-script. Scheduled commands run as you, with
	your permissions checked on every run, and stop when you leave.
]]

--// Imports
const BuiltInTypes = require("../Shared/BuiltInTypes")
const Command = require("../Shared/Command")
const Keys = require("../Shared/Keys")
const Parser = require("../Shared/Parser")
const Scheduler = require("../Server/Scheduler")
const ShellDirectory = require("../Shared/ShellDirectory")
const TypeBuilder = require("../Shared/TypeBuilder")
const Types = require("../Shared/Types")
const Util = require("../Shared/Util")

--// Types
type Context = Types.Context

--// Constants
const T = BuiltInTypes.Types

const ScriptName = TypeBuilder.Dynamic({
	Name = "script",
	Candidates = function(request: Types.CandidateRequest): { Types.Candidate<Instance> }
		const candidates: { Types.Candidate<Instance> } = {}
		const shell = ShellDirectory.Get(request.Shell)
		const folder = if shell then shell.Registry:GetEnv(Keys.Scripts) else nil
		if folder then
			for _, child in folder:GetChildren() do
				if child:IsA("ModuleScript") or child:IsA("StringValue") then
					table.insert(candidates, { Key = child.Name, Value = child })
				end
			end
		end
		return candidates
	end,
})

--// Helpers

const function scheduler(ctx: Context): Scheduler.Scheduler?
	return ctx:GetEnv(Keys.Scheduler)
end

const function joinWords(words: { string }): string
	return table.concat(words, " ")
end

const function checkSyntax(text: string): string?
	const parsed = Parser.Parse(text)
	const first = parsed.Diagnostics[1]
	return if first then first.Message else nil
end

--// Commands

const inCommand = Command.new({
	Name = "in",
	Aliases = { "after" },
	Description = "Runs a command line after a delay",
	Group = "Schedule",
	Examples = { "in 5m announce Restarting", "in 30s kick Bob" },
	Args = { { delay = Command.Arg(T.Duration) }, { script = Command.Rest(T.String) } },
}):Run(function(ctx, args)
	const jobs = scheduler(ctx)
	if jobs == nil then
		return ctx:Error("Scheduling is only available on the server")
	end
	const text = joinWords(args.script)
	const syntaxError = checkSyntax(text)
	if syntaxError then
		return ctx:Error(syntaxError)
	end
	const job = jobs:Schedule(ctx.Executor, text, args.delay)
	return ctx:Success(`#{job.Id} runs in {Util.FormatDuration(args.delay)}: {text}`)
end)

const every = Command.new({
	Name = "every",
	Description = "Runs a command line repeatedly",
	Group = "Schedule",
	Examples = { "every 1m announce Hydrate!", "every 10s heal * --times 6" },
	Args = {
		{
			interval = Command.Arg(
				TypeBuilder.Refine(T.Duration, function(value: number): (boolean, string?)
					return value >= 1, "The interval must be at least 1s"
				end)
			),
		},
		{ script = Command.Rest(T.String) },
		{ times = Command.Optional(TypeBuilder.Integer({ Min = 1, Max = 10000 }), { Short = "n", Named = true }) },
	},
}):Run(function(ctx, args)
	const jobs = scheduler(ctx)
	if jobs == nil then
		return ctx:Error("Scheduling is only available on the server")
	end
	const text = joinWords(args.script)
	const syntaxError = checkSyntax(text)
	if syntaxError then
		return ctx:Error(syntaxError)
	end
	const job = jobs:Schedule(ctx.Executor, text, args.interval, args.interval, args.times)
	return ctx:Success(
		`#{job.Id} runs every {Util.FormatDuration(args.interval)}{if args.times then ` ({args.times} times)` else ""}: {text}`
	)
end)

const repeatCommand = Command.new({
	Name = "repeat",
	Description = "Runs a command line several times now (stops at the first failure)",
	Group = "Schedule",
	Examples = { "repeat 3 echo hi", "repeat 5 spawnloot rare --interval 1s" },
	Args = {
		{ count = Command.Arg(TypeBuilder.Integer({ Min = 1, Max = 100 })) },
		{ script = Command.Rest(T.String) },
		{ interval = Command.Default(T.Duration, 0, { Short = "i", Named = true }) },
	},
}):ClientRun(function(ctx, args)
	const text = joinWords(args.script)
	for index = 1, args.count do
		ctx:CheckCancelled()
		const result = ctx:Run(text)
		if not result.Ok then
			return ctx:Error(`Stopped at run {index}`)
		end
		if args.interval > 0 and index < args.count then
			ctx.Shell.Platform.Wait(args.interval)
		end
	end
	return ctx:Success(`Ran {args.count} times`)
end)

const schedules = Command.new({
	Name = "schedules",
	Aliases = { "jobs" },
	Description = "Lists your scheduled commands",
	Group = "Schedule",
	Args = {},
}):Run(function(ctx)
	const jobs = scheduler(ctx)
	if jobs == nil then
		return ctx:Error("Scheduling is only available on the server")
	end
	const now = ctx.Shell.Platform.Clock()
	const lines: { string } = {}
	for _, job in jobs:List(ctx.Executor) do
		table.insert(lines, Scheduler.Describe(job, now))
	end
	if #lines == 0 then
		return ctx:Info("Nothing scheduled")
	end
	return ctx:List(lines, "Scheduled")
end)

const cancel = Command.new({
	Name = "cancel",
	Description = "Cancels a scheduled command (or all of yours with 'all')",
	Group = "Schedule",
	Args = {
		{
			id = Command.Arg(
				TypeBuilder.Union({
					Name = "job",
					Members = { T.Integer, TypeBuilder.Choice<<"all">>({ Name = "all", Choices = { "all" } }) },
				})
			),
		},
	},
}):Run(function(ctx, args)
	const jobs = scheduler(ctx)
	if jobs == nil then
		return ctx:Error("Scheduling is only available on the server")
	end
	if args.id == "all" then
		return ctx:Success(`Cancelled {jobs:CancelAll(ctx.Executor)} job(s)`)
	end
	if type(args.id) == "number" and jobs:Cancel(args.id, ctx.Executor) then
		return ctx:Success(`Cancelled #{args.id}`)
	end
	return ctx:Error(`No job #{tostring(args.id)}`)
end)

const runScript = Command.new({
	Name = "run-script",
	Aliases = { "script" },
	Description = "Runs a stored script (a ModuleScript returning text, or a StringValue)",
	Group = "Schedule",
	Args = { { script = Command.Arg(ScriptName) } },
}):Run(function(ctx, args)
	const source = args.script
	local text: string? = nil
	if source:IsA("StringValue") then
		text = source.Value
	elseif source:IsA("ModuleScript") then
		const ok, result = pcall(require, source)
		if ok and type(result) == "string" then
			text = result
		end
	end
	if text == nil then
		return ctx:Error(`{source.Name} is not a script (it must be text)`)
	end
	const syntaxError = checkSyntax(text)
	if syntaxError then
		return ctx:Error(`{source.Name}: {syntaxError}`)
	end
	const result = ctx:Run(text)
	if not result.Ok then
		return ctx:Error(`{source.Name} failed`)
	end
	return ctx:Success(`Ran {source.Name} ({#result.Results} command(s))`)
end)

return { inCommand, every, repeatCommand, schedules, cancel, runScript } :: { Types.Command }
