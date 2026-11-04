--!strict
--[[
	Type test: must type-check with zero errors. Game code annotates its commands, types and selectors with the
	types `RoShell` exports, and calls the client methods of the shell `RoShell.new` returns.
--]]

const RoShell = require(script.Parent.Parent.Parent.Parent.src)

--- Compile-time assertion helper: `expectType<<T>>(value)` errors unless `value` is a `T`.
const function expectType<T>(_value: T) end

const Tagged: RoShell.Selector<Model> = {
	Prefix = "#",
	Name = "tag",
	Description = "Models with a tag",
	Example = "#Boss",
	Complete = function(_request: RoShell.CompleteRequest): { RoShell.Suggestion }
		return {}
	end,
	Resolve = function(request: RoShell.ParseRequest): RoShell.ParseResult<{ read Model }>
		return { Ok = false, Error = `No models tagged {request.Text}` }
	end,
}

const function executorName(request: RoShell.CandidateRequest): string?
	const executor = request.Executor
	return if executor then executor.Name else nil
end

const ping = RoShell.Command({ Name = "ping", Args = {} }):Run(function(ctx, _args): RoShell.Output
	const reply: RoShell.Reply = ctx:Success("pong")
	return reply
end)

const shell = RoShell.new()
shell:OpenPalette()
shell:SetInput("ping ")
expectType<<(request: RoShell.CandidateRequest) -> string?>>(executorName)

return { Tagged = Tagged, ping = ping }
