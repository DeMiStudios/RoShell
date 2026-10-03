--!strict
--[[
	Icons. The Roblox client ships an icon font (Builder Icons: a ligature such as `magnifying-glass` renders as one
	glyph). Labels use it once it is confirmed to load, and plain Unicode glyphs from the text fonts until then — or
	for good, if it never does — so an icon never shows up as its raw ligature name.

	Keys are semantic (`player`, `success`, `theme`), Builder Icons names (`cube`, `map-pin`), or short text drawn
	as is (choice numbers, custom glyphs). Ligatures match inside longer words, so a name the font lacks may still
	draw part of itself (`exit` draws `x`): every name used here was checked visually.
]]

--// Types
type Entry = { Builder: string, Glyph: string }

export type IconLabel = TextLabel | TextButton

--// Constants
const ICON_FONT = "rbxasset://LuaPackages/Packages/_Index/BuilderIcons/BuilderIcons/BuilderIcons.json"
--- A Builder Icons name that renders as a single glyph when the font loads.
const PROBE = "magnifying-glass"
--- Drawn for a Builder Icons name while the font is unavailable.
const FALLBACK_GLYPH = "◆"

--- Semantic keys: the Builder Icons name and the Unicode fallback (every fallback glyph renders in BuilderSans).
const KEYS: { [string]: Entry } = {
	-- Suggestion kinds
	command = { Builder = "code", Glyph = "⌘" },
	alias = { Builder = "chain-link", Glyph = "→" },
	subcommand = { Builder = "chevron-small-right", Glyph = "›" },
	argument = { Builder = "diamond", Glyph = "◇" },
	flag = { Builder = "flag", Glyph = "-" },
	operator = { Builder = "", Glyph = "*" },
	variable = { Builder = "tag", Glyph = "$" },
	history = { Builder = "clock", Glyph = "↑" },
	value = { Builder = "diamond", Glyph = "◆" },
	item = { Builder = "cube", Glyph = "◆" },
	-- Argument types
	player = { Builder = "person", Glyph = "●" },
	team = { Builder = "two-people", Glyph = "◉" },
	number = { Builder = "hashtag", Glyph = "#" },
	string = { Builder = "paragraph", Glyph = "“" },
	boolean = { Builder = "square-check", Glyph = "◐" },
	instance = { Builder = "cube", Glyph = "◈" },
	class = { Builder = "cube", Glyph = "◈" },
	color = { Builder = "paint-brush", Glyph = "●" },
	enum = { Builder = "grid", Glyph = "≡" },
	tag = { Builder = "tag", Glyph = "#" },
	time = { Builder = "clock", Glyph = "◔" },
	vector = { Builder = "compass", Glyph = "↗" },
	key = { Builder = "keyboard", Glyph = "⌥" },
	type = { Builder = "code", Glyph = "τ" },
	remote = { Builder = "lightning-bolt", Glyph = "⇄" },
	-- Console
	theme = { Builder = "paint-brush", Glyph = "◑" },
	setting = { Builder = "gear", Glyph = "≡" },
	action = { Builder = "lightning-bolt", Glyph = "→" },
	prompt = { Builder = "chevron-large-right", Glyph = "›" },
	search = { Builder = "magnifying-glass", Glyph = "›" },
	run = { Builder = "arrow-large-right", Glyph = "⏎" },
	stop = { Builder = "square", Glyph = "■" },
	log = { Builder = "clock", Glyph = "≡" },
	close = { Builder = "x", Glyph = "×" },
	help = { Builder = "circle-question", Glyph = "?" },
	palette = { Builder = "grid", Glyph = "⌘" },
	copy = { Builder = "arrow-large-down", Glyph = "≡" },
	-- Levels
	success = { Builder = "circle-check", Glyph = "✓" },
	error = { Builder = "circle-x", Glyph = "×" },
	warning = { Builder = "triangle-exclamation", Glyph = "▲" },
	info = { Builder = "circle-info", Glyph = "i" },
	echo = { Builder = "chevron-small-right", Glyph = "›" },
	muted = { Builder = "", Glyph = "·" },
	plain = { Builder = "", Glyph = "" },
}

--// Globals
local state: "unknown" | "probing" | "available" | "missing" = "unknown"
-- Labels showing an icon, re-rendered once the font's availability is known.
const shown: { [IconLabel]: string } = setmetatable({}, { __mode = "k" })
-- Builder Icons names that are not semantic keys, checked once each (a name the font lacks draws nothing).
const valid: { [string]: boolean } = {}
const checking: { [string]: true } = {}
local iconFont: Font? = nil
local textFont: Font? = nil

--// Helpers

--- Lowercase words joined by hyphens: a Builder Icons name.
const function isBuilderName(key: string): boolean
	return #key > 1 and key:match("^[a-z][a-z%-]*[a-z]$") ~= nil
end

const function fonts(): (Font, Font)
	local icon = iconFont
	local text = textFont
	if icon == nil or text == nil then
		icon = Font.new(ICON_FONT)
		text = Font.fromEnum(Enum.Font.BuilderSansBold)
		iconFont = icon
		textFont = text
	end
	return icon :: Font, text :: Font
end

--- Whether `name` renders as one glyph in `font` (a glyph is about as wide as it is tall; a name the font lacks
--- draws nothing, and spelled out it would be far wider).
const function renders(font: Font, name: string): boolean
	const ok, bounds = pcall(function(): Vector2
		const params = Instance.new("GetTextBoundsParams")
		params.Text = name
		params.Font = font
		params.Size = 20
		params.Width = 1000
		return game:GetService("TextService"):GetTextBoundsAsync(params)
	end)
	return ok and bounds.X > 0 and bounds.X <= 30
end

local render: (label: IconLabel, key: string) -> ()

const function check(name: string)
	if checking[name] or valid[name] ~= nil then
		return
	end
	checking[name] = true
	const icon = fonts()
	task.spawn(function()
		valid[name] = renders(icon, name)
		checking[name] = nil
		for label, key in shown do
			if key == name then
				render(label, key)
			end
		end
	end)
end

render = function(label: IconLabel, key: string)
	const icon, text = fonts()
	const entry = KEYS[key] or KEYS[key:lower()]
	if state == "available" then
		local name: string? = nil
		if entry then
			name = entry.Builder
		elseif isBuilderName(key) then
			if valid[key] == nil then
				check(key)
			end
			name = if valid[key] then key else nil
		end
		if name and name ~= "" then
			label.FontFace = icon
			label.Text = name
			return
		end
	end
	label.FontFace = text
	label.Text = if entry then entry.Glyph elseif isBuilderName(key) then FALLBACK_GLYPH else key
end

const function probe()
	state = "probing"
	const icon = fonts()
	task.spawn(function()
		state = if renders(icon, PROBE) then "available" else "missing"
		for label, key in shown do
			render(label, key)
		end
	end)
end

--// Icons
const Icons = {}

--- Shows icon `key` in `label` (and keeps it current when the icon font finishes loading).
function Icons.Apply(label: IconLabel, key: string?)
	if state == "unknown" then
		probe()
	end
	const resolved = key or "value"
	shown[label] = resolved
	render(label, resolved)
end

--- Stops tracking a label (before it shows something else, such as a spinner glyph).
function Icons.Clear(label: IconLabel)
	shown[label] = nil
end

--- The Unicode fallback of a key, for places that draw icons inside text.
function Icons.Glyph(key: string?): string
	if key == nil then
		return KEYS.value.Glyph
	end
	const entry = KEYS[key] or KEYS[key:lower()]
	return if entry then entry.Glyph elseif isBuilderName(key) then FALLBACK_GLYPH else key
end

--- True once the icon font is known to render.
function Icons.Available(): boolean
	return state == "available"
end

return table.freeze(Icons)
