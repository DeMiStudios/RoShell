--!strict
--[[
	Test harness for user commands: runs command lines against a headless shell (no UI, no network, virtual
	clock) and returns everything they produced. Works under Roblox (TestEZ/Jest-Lua/anything) and the standalone
	Luau runtime.

		local result = RoShell.Test.Run({ Text = "give me sword 3", Commands = { giveCommand } })
		assert(result.Ok, result.Output)

	For several runs against one shell, create a harness: `RoShell.Test.new({ Commands = ... })`.
]]

--// Imports
const Platform = require("./Platform")
const Shell = require("./Shell")
const Types = require("./Types")
const Util = require("./Util")

--// Types
export type HarnessOptions = {
	Commands: { Types.Command }?,
	Types: { Types.Type<unknown> }?,
	--- Also register the built-in commands (default false).
	Defaults: boolean?,
	--- Run as the client side of the shell (default: server).
	Client: boolean?,
	--- Engine abstraction (default: headless with a virtual clock; waits complete instantly).
	Platform: Types.PlatformInfo?,
	Seed: number?,
}

export type RunSpec = {
	--- The executor (a real or fake Player; nil runs as the server console).
	As: Player?,
	--- Answers to prompts in order (`"yes"`/`"no"`/choice/text). Missing answers cancel the prompt.
	Answers: { string }?,
	Yes: boolean?,
	Dry: boolean?,
	Data: unknown,
}

export type RunOptions = RunSpec & HarnessOptions & { Text: string }

export type TestResult = {
	read Ok: boolean,
	read Result: Types.RunResult,
	--- Every block the commands produced, in order.
	read Blocks: { Types.Block },
	--- Text of the text/value/list blocks, one entry per line.
	read Lines: { string },
	--- `Lines` joined with newlines (handy in assertion messages).
	read Output: string,
	--- Value of the last command.
	read Value: unknown,
	read Prompts: { Types.PromptRequest },
	--- True when the run was still waiting (e.g. on a long `wait`) after the virtual clock was flushed.
	read TimedOut: boolean,
}

export type Harness = {
	read Shell: Types.Shell,
	--- Controls the virtual clock (nil when a custom platform was given).
	read Clock: Platform.HeadlessController?,
	read Run: (text: string, spec: RunSpec?) -> TestResult,
}

--// Constants
const MAX_FLUSHES = 1000

--// Helpers

const function linesOf(blocks: { Types.Block }): { string }
	const lines: { string } = {}
	for _, block in blocks do
		if block.Kind == "text" then
			table.insert(lines, block.Text)
		elseif block.Kind == "value" then
			table.insert(lines, block.Display)
		elseif block.Kind == "list" then
			for _, item in block.Items do
				table.insert(lines, item)
			end
		elseif block.Kind == "keyvalue" then
			for _, entry in block.Entries do
				table.insert(lines, `{entry.Key}: {entry.Value}`)
			end
		elseif block.Kind == "table" then
			for _, row in block.Rows do
				table.insert(lines, Util.Join(row, " | "))
			end
		end
	end
	return lines
end

--// Test
const Test = {}

--- Creates a reusable headless shell with the given commands and types.
function Test.new(options: HarnessOptions?): Harness
	const opts: HarnessOptions = options or {}
	const controller = if opts.Platform then nil else Platform.Headless(opts.Seed or 1)
	const platform: Types.PlatformInfo = opts.Platform or (controller :: Platform.HeadlessController).Platform
	const isClient = opts.Client == true
	const shell = Shell.new({ IsServer = not isClient, IsClient = isClient, Platform = platform })
	if opts.Types then
		shell.Registry:RegisterTypes(opts.Types)
	end
	if opts.Defaults then
		shell.Registry:RegisterDefaultCommands()
	end
	if opts.Commands then
		shell.Registry:RegisterCommands(opts.Commands)
	end

	return table.freeze({
		Shell = shell,
		Clock = controller,
		Run = function(text: string, spec: RunSpec?): TestResult
			const runSpec: RunSpec = spec or {}
			const answers = table.clone(runSpec.Answers or {})
			const blocks: { Types.Block } = {}
			const prompts: { Types.PromptRequest } = {}
			local result: Types.RunResult? = nil
			const thread = coroutine.create(function()
				result = shell.Dispatcher:Run({
					Text = text,
					Executor = runSpec.As,
					Options = { Yes = runSpec.Yes, Dry = runSpec.Dry, Data = runSpec.Data, IsHuman = true },
					OnBlock = function(block: Types.Block)
						table.insert(blocks, block)
					end,
					OnPrompt = function(prompt: Types.PromptRequest): Types.PromptAnswer
						table.insert(prompts, prompt)
						return table.remove(answers, 1)
					end,
				})
			end)
			const ok, err = coroutine.resume(thread)
			if not ok then
				error(err, 0)
			end
			-- Let waits and timers finish on the virtual clock.
			if controller then
				local flushes = 0
				while result == nil and flushes < MAX_FLUSHES do
					controller:Flush()
					flushes += 1
				end
			end
			const final: Types.RunResult = result
				or { Ok = false, Results = {}, Last = nil, Diagnostics = {}, Cancelled = false }
			const lines = linesOf(blocks)
			const last = final.Last
			return table.freeze({
				Ok = final.Ok,
				Result = final,
				Blocks = blocks,
				Lines = lines,
				Output = table.concat(lines, "\n"),
				Value = if last then last.Value else nil,
				Prompts = prompts,
				TimedOut = result == nil,
			})
		end,
	})
end

--- Runs one command line in a fresh harness.
function Test.Run(options: RunOptions): TestResult
	return Test.new(options).Run(options.Text, options)
end

return table.freeze(Test)
