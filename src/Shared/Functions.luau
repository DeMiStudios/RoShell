--!strict
--[[
	Built-in `$functions` for the input language: `give me sword $random(1, 5)`, `announce $upper(hello)`.
	Every shell registers these; add more with `registry:RegisterFunction({ Name, Description, Call })`.
]]

--// Imports
const Types = require("./Types")
const Util = require("./Util")

--// Helpers

const function number(text: string?, fallback: number): number
	const value = if text then tonumber(Util.Trim(text)) else nil
	return value or fallback
end

const function join(args: { read string }): string
	return Util.Join(args, ", ")
end

--// Functions
const FUNCTIONS: { Types.FunctionDefinition } = {
	{
		Name = "random",
		Description = "A random integer: $random(max) or $random(min, max)",
		Call = function(request: Types.FunctionCallRequest): string
			const args = request.Args
			if #args >= 2 then
				const low = number(args[1], 1)
				const high = number(args[2], low)
				return tostring(request.Platform.Random(math.min(low, high), math.max(low, high)))
			end
			return tostring(request.Platform.Random(1, math.max(1, number(args[1], 100))))
		end,
	},
	{
		Name = "pick",
		Description = "One of the arguments at random: $pick(red, green, blue)",
		Call = function(request: Types.FunctionCallRequest): string
			const args = request.Args
			if #args == 0 then
				return ""
			end
			return Util.Trim(args[request.Platform.Random(1, #args)])
		end,
	},
	{
		Name = "time",
		Description = "The current Unix time in seconds",
		Call = function(request: Types.FunctionCallRequest): string
			return tostring(math.floor(request.Platform.Now()))
		end,
	},
	{
		Name = "date",
		Description = "The current UTC date and time: $date() or $date(%Y-%m-%d)",
		Call = function(request: Types.FunctionCallRequest): string
			const format = if request.Args[1] and Util.Trim(request.Args[1]) ~= "" then Util.Trim(join(request.Args))
				else "%Y-%m-%d %H:%M:%S"
			return os.date("!" .. format, math.floor(request.Platform.Now()))
		end,
	},
	{
		Name = "upper",
		Description = "Uppercases text: $upper(hello)",
		Call = function(request: Types.FunctionCallRequest): string
			return join(request.Args):upper()
		end,
	},
	{
		Name = "lower",
		Description = "Lowercases text: $lower(HELLO)",
		Call = function(request: Types.FunctionCallRequest): string
			return join(request.Args):lower()
		end,
	},
	{
		Name = "len",
		Description = "Number of characters: $len(hello)",
		Call = function(request: Types.FunctionCallRequest): string
			const text = join(request.Args)
			return tostring(utf8.len(text) or #text)
		end,
	},
	{
		Name = "round",
		Description = "Rounds a number: $round(2.5) or $round(3.14159, 2)",
		Call = function(request: Types.FunctionCallRequest): string
			const value = number(request.Args[1], 0)
			const places = math.clamp(math.floor(number(request.Args[2], 0)), 0, 10)
			const factor = 10 ^ places
			return tostring(math.floor(value * factor + 0.5) / factor)
		end,
	},
	{
		Name = "me",
		Description = "Your name",
		Call = function(request: Types.FunctionCallRequest): string
			return Util.ExecutorName(request.Executor)
		end,
	},
}

return table.freeze({ All = FUNCTIONS })
