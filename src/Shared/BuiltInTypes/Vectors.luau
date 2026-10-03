--!strict
--[[
	Vector types: `x,y,z` (commas or spaces in quotes), and `.`/`me`/`here` for the executor's position.
]]

--// Imports
const TypeBuilder = require("../TypeBuilder")
const Types = require("../Types")
const Util = require("../Util")

--// Types
type ParseRequest = Types.ParseRequest

--// Helpers

const function numbers(text: string): { number }?
	const values: { number } = {}
	for piece in text:gsub("[%(%)]", ""):gmatch("[^,%s]+") do
		const value = tonumber(piece)
		if value == nil then
			return nil
		end
		table.insert(values, value)
	end
	return values
end

const function executorPosition(request: ParseRequest): Vector3?
	const executor = request.Executor
	const character = if executor then executor.Character else nil
	if character then
		const ok, pivot = pcall(function(): CFrame
			return character:GetPivot()
		end)
		if ok then
			return pivot.Position
		end
	end
	return nil
end

const function isSelf(text: string): boolean
	const lowered = text:lower()
	return lowered == "." or lowered == "me" or lowered == "here" or lowered == "@me"
end

--// Types

const Vector3Type = TypeBuilder.Custom({
	Name = "vector3",
	Description = "A position: x,y,z (or . / here for your position)",
	Examples = { "0,10,0", "here" },
	Parse = function(request: ParseRequest): Types.ParseResult<Vector3>
		if isSelf(request.Text) then
			const position = executorPosition(request)
			if position == nil then
				return { Ok = false, Error = "You have no character to take a position from", Span = request.Span }
			end
			return { Ok = true, Value = position, Display = Util.FormatValue(position) }
		end
		const values = numbers(request.Text)
		if values == nil or #values ~= 3 then
			return { Ok = false, Error = `'{request.Text}' is not a vector (x,y,z)`, Span = request.Span }
		end
		const vector = Vector3.new(values[1], values[2], values[3])
		return { Ok = true, Value = vector, Display = Util.FormatValue(vector) }
	end,
	Default = executorPosition,
	Suggestions = { "here", "0,0,0" },
	Color = "type.number",
	Icon = "vector",
})

const Vector2Type = TypeBuilder.Custom({
	Name = "vector2",
	Description = "A 2D vector: x,y",
	Examples = { "0.5,0.5" },
	Parse = function(request: ParseRequest): Types.ParseResult<Vector2>
		const values = numbers(request.Text)
		if values == nil or #values ~= 2 then
			return { Ok = false, Error = `'{request.Text}' is not a vector (x,y)`, Span = request.Span }
		end
		const vector = Vector2.new(values[1], values[2])
		return { Ok = true, Value = vector, Display = Util.FormatValue(vector) }
	end,
	Color = "type.number",
	Icon = "vector",
})

const VectorTypes = {
	Vector3 = Vector3Type,
	Vector3s = TypeBuilder.List(Vector3Type, { Name = "vector3s" }),
	Vector2 = Vector2Type,
	Vector2s = TypeBuilder.List(Vector2Type, { Name = "vector2s" }),
}

return table.freeze(VectorTypes)
