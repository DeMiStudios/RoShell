--!strict
--[[
	Primitive built-in types: strings, numbers, integers, booleans, percentages, ranges, Luau patterns, URLs,
	JSON and asset ids.
]]

--// Imports
const TypeBuilder = require("../TypeBuilder")
const Types = require("../Types")

--// Types
type ParseRequest = Types.ParseRequest

--// Helpers

const function fail(request: ParseRequest, message: string): Types.ParseError
	return { Ok = false, Error = message, Span = request.Span, Progress = 0 }
end

--// Types
const String = TypeBuilder.String({ Name = "string", Description = "Any text" })
const Number = TypeBuilder.Number({ Name = "number" })
const Integer = TypeBuilder.Integer({ Name = "integer" })
const Boolean = TypeBuilder.Boolean("boolean")
const Percent = TypeBuilder.Number({
	Name = "percent",
	Min = 0,
	Max = 100,
	Suffix = "%",
	Description = "0-100 (a % sign is optional)",
})
const Range = TypeBuilder.Range({ Name = "range" })

const Pattern = TypeBuilder.Custom({
	Name = "pattern",
	Description = "A Luau string pattern",
	Examples = { "^Guest%d+$" },
	Parse = function(request: ParseRequest): Types.ParseResult<string>
		const ok, err = pcall(string.find, "", request.Text, 1, false)
		if not ok then
			return fail(request, `Invalid pattern: {tostring(err):gsub("^.-:%d+: ", "")}`)
		end
		return { Ok = true, Value = request.Text, Display = request.Text }
	end,
	Color = "type.string",
})

const Url = TypeBuilder.Custom({
	Name = "url",
	Description = "An http(s) URL",
	Examples = { "https://example.com/path" },
	Parse = function(request: ParseRequest): Types.ParseResult<string>
		if not request.Text:match("^https?://[%w%-%._~:/%?#%[%]@!%$&'%(%)%*%+,;=%%]+$") then
			return fail(request, `'{request.Text}' is not a valid http(s) URL`)
		end
		return { Ok = true, Value = request.Text, Display = request.Text }
	end,
	Color = "type.string",
})

const Json = TypeBuilder.Custom({
	Name = "json",
	Description = "A JSON value",
	Examples = { '{"a":1}', "[1,2,3]" },
	Parse = function(request: ParseRequest): Types.ParseResult<unknown>
		const ok, value = pcall(function(): unknown
			return game:GetService("HttpService"):JSONDecode(request.Text)
		end)
		if not ok then
			return fail(request, "Invalid JSON")
		end
		return { Ok = true, Value = value, Display = request.Text }
	end,
	Color = "type.string",
})

const Asset = TypeBuilder.Custom({
	Name = "asset",
	Description = "An asset id (123, rbxassetid://123 or a creator store URL)",
	Examples = { "rbxassetid://1818", "1818" },
	Parse = function(request: ParseRequest): Types.ParseResult<number>
		const text = request.Text
		const id = text:match("^(%d+)$")
			or text:match("^rbxassetid://(%d+)$")
			or text:match("^rbxasset://.-(%d+)")
			or text:match("roblox%.com/[%w/]-/(%d+)")
			or text:match("[?&]id=(%d+)")
		const number = if id then tonumber(id) else nil
		if number == nil then
			return fail(request, `'{text}' is not an asset id`)
		end
		return { Ok = true, Value = number, Display = `rbxassetid://{id}` }
	end,
	Color = "type.number",
})

const Primitives = {
	String = String,
	Strings = TypeBuilder.List(String, { Name = "strings" }),
	Number = Number,
	Numbers = TypeBuilder.List(Number, { Name = "numbers" }),
	Integer = Integer,
	Integers = TypeBuilder.List(Integer, { Name = "integers" }),
	Boolean = Boolean,
	Percent = Percent,
	Range = Range,
	Pattern = Pattern,
	Url = Url,
	Json = Json,
	Asset = Asset,
}

return table.freeze(Primitives)
