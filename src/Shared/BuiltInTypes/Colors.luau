--!strict
--[[
	Color types. `color3` accepts `#ff8800`, `ff8800`, `#f80`, `255,128,0`, `1,0.5,0`, `rgb(255,128,0)`,
	`hsv(30,100,100)`, named colors and BrickColor names. `colorHex` accepts hex only. `brickColor` completes
	from the BrickColor palette.
]]

--// Imports
const Fuzzy = require("../Fuzzy")
const TypeBuilder = require("../TypeBuilder")
const Types = require("../Types")

--// Types
type ParseRequest = Types.ParseRequest

--// Constants
const NAMED_COLORS: { [string]: { number } } = {
	white = { 255, 255, 255 },
	black = { 0, 0, 0 },
	gray = { 128, 128, 128 },
	grey = { 128, 128, 128 },
	silver = { 192, 192, 192 },
	red = { 255, 59, 48 },
	maroon = { 128, 0, 0 },
	orange = { 255, 149, 0 },
	yellow = { 255, 204, 0 },
	gold = { 255, 215, 0 },
	lime = { 50, 215, 75 },
	green = { 52, 199, 89 },
	teal = { 48, 176, 199 },
	cyan = { 50, 173, 230 },
	blue = { 0, 122, 255 },
	navy = { 0, 0, 128 },
	indigo = { 88, 86, 214 },
	purple = { 175, 82, 222 },
	magenta = { 255, 45, 85 },
	pink = { 255, 105, 180 },
	brown = { 162, 132, 94 },
}
const NAMED_LIST: { string } = {}
for name in NAMED_COLORS do
	table.insert(NAMED_LIST, name)
end
table.sort(NAMED_LIST)

--// Globals
local brickCandidates: { Types.Candidate<BrickColor> }? = nil

const function loadBrickColors(): { read Types.Candidate<BrickColor> }
	if brickCandidates then
		return brickCandidates
	end
	const candidates: { Types.Candidate<BrickColor> } = {}
	const seen: { [string]: true } = {}
	for index = 0, 127 do
		const brick = BrickColor.palette(index)
		if not seen[brick.Name] then
			seen[brick.Name] = true
			table.insert(candidates, { Key = brick.Name, Value = brick, Detail = "#" .. brick.Color:ToHex():upper() })
		end
	end
	table.freeze(candidates)
	brickCandidates = candidates
	return candidates
end

--// Helpers

const function fail(request: ParseRequest, message: string): Types.ParseError
	return { Ok = false, Error = message, Span = request.Span, Progress = 0 }
end

const function parseHex(text: string): Color3?
	local hex = text:match("^#?(%x+)$")
	if hex == nil then
		return nil
	end
	if #hex == 3 then
		hex = hex:sub(1, 1):rep(2) .. hex:sub(2, 2):rep(2) .. hex:sub(3, 3):rep(2)
	end
	if #hex ~= 6 then
		return nil
	end
	return Color3.fromRGB(
		tonumber(hex:sub(1, 2), 16) :: number,
		tonumber(hex:sub(3, 4), 16) :: number,
		tonumber(hex:sub(5, 6), 16) :: number
	)
end

const function parseTriple(text: string): (number?, number?, number?)
	const a, b, c = text:match("^%s*([%d%.]+)%s*[,%s]%s*([%d%.]+)%s*[,%s]%s*([%d%.]+)%s*$")
	return tonumber(a), tonumber(b), tonumber(c)
end

const function parseColor(text: string): (Color3?, string?)
	const lowered = text:lower()
	const hex = parseHex(lowered)
	if hex then
		return hex, nil
	end
	const named = NAMED_COLORS[lowered]
	if named then
		return Color3.fromRGB(named[1], named[2], named[3]), nil
	end
	const hsvBody = lowered:match("^hsv%((.-)%)$")
	if hsvBody then
		const h, s, v = parseTriple(hsvBody)
		if h and s and v then
			return Color3.fromHSV((h % 360) / 360, math.clamp(s / 100, 0, 1), math.clamp(v / 100, 0, 1)), nil
		end
		return nil, "hsv(...) expects hue, saturation and value: hsv(30,100,100)"
	end
	const r, g, b = parseTriple(lowered:match("^rgb%((.-)%)$") or lowered)
	if r and g and b then
		if r <= 1 and g <= 1 and b <= 1 and (text:find("%.") ~= nil) then
			return Color3.new(r, g, b), nil
		end
		if r > 255 or g > 255 or b > 255 then
			return nil, "RGB components must be between 0 and 255"
		end
		return Color3.fromRGB(r, g, b), nil
	end
	for _, candidate in loadBrickColors() do
		if candidate.Key:lower() == lowered then
			return candidate.Value.Color, nil
		end
	end
	const suggestion = Fuzzy.Suggest(text, NAMED_LIST)
	return
		nil,
		if suggestion then `Unknown color '{text}'. Did you mean '{suggestion}'?`
			else `'{text}' is not a color (try #ff8800, 255,128,0, rgb(...), hsv(...) or a name)`
end

const function display(color: Color3): string
	return "#" .. color:ToHex():upper()
end

--// Types

const Color = TypeBuilder.Custom({
	Name = "color3",
	Description = "A color: #ff8800, 255,128,0, rgb(255,128,0), hsv(30,100,100), or a name",
	Examples = { "#ff8800", "255,128,0", "hsv(200,80,100)", "orange" },
	Parse = function(request: ParseRequest): Types.ParseResult<Color3>
		const color, err = parseColor(request.Text)
		if color == nil then
			return fail(request, err or "Invalid color")
		end
		return { Ok = true, Value = color, Display = display(color) }
	end,
	Suggestions = NAMED_LIST,
	Color = "type.color",
	Icon = "color",
})

const ColorHex = TypeBuilder.Custom({
	Name = "colorHex",
	Description = "A hex color: #ff8800 or #f80",
	Examples = { "#ff8800" },
	Parse = function(request: ParseRequest): Types.ParseResult<Color3>
		const color = parseHex(request.Text)
		if color == nil then
			return fail(request, `'{request.Text}' is not a hex color (#rrggbb)`)
		end
		return { Ok = true, Value = color, Display = display(color) }
	end,
	Color = "type.color",
	Icon = "color",
})

const BrickColorType = TypeBuilder.Enumerable({
	Name = "brickColor",
	Description = "A BrickColor name",
	Examples = { "Bright red", "Really black" },
	Candidates = loadBrickColors,
	Color = "type.color",
	Icon = "color",
})

const ColorTypes = {
	Color3 = Color,
	Color3s = TypeBuilder.List(Color, { Name = "color3s" }),
	ColorHex = ColorHex,
	BrickColor = BrickColorType,
	BrickColors = TypeBuilder.List(BrickColorType, { Name = "brickColors" }),
	ParseColor = parseColor,
}

return table.freeze(ColorTypes)
