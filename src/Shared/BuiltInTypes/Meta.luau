--!strict
--[[
	Types about the shell itself: commands, registered types, stored variables, enums by name, and keybinds.
]]

--// Imports
const ShellDirectory = require("../ShellDirectory")
const TypeBuilder = require("../TypeBuilder")
const Types = require("../Types")

--// Types
type ParseRequest = Types.ParseRequest
type Candidate<T> = Types.Candidate<T>

export type Keybind = {
	--- Keyboard key or gamepad button.
	KeyCode: Enum.KeyCode?,
	--- Mouse button input type.
	InputType: Enum.UserInputType?,
	Ctrl: boolean,
	Shift: boolean,
	Alt: boolean,
	--- Canonical text, e.g. "Ctrl+Shift+K".
	Text: string,
}

--// Constants
const MOUSE_INPUTS: { [string]: string } = {
	mousebutton1 = "MouseButton1",
	mousebutton2 = "MouseButton2",
	mousebutton3 = "MouseButton3",
	lmb = "MouseButton1",
	rmb = "MouseButton2",
	mmb = "MouseButton3",
}

--// Helpers

const function commandCandidates(request: Types.CandidateRequest): { read Candidate<Types.Command> }
	const candidates: { Candidate<Types.Command> } = {}
	const shell = ShellDirectory.Get(request.Shell)
	if shell == nil then
		return candidates
	end
	for _, command in shell.Registry:GetCommands() do
		if not command.Hidden then
			table.insert(candidates, {
				Key = command.Name,
				Value = command,
				Aliases = command.Aliases,
				Description = command.Description,
				Detail = command.Group,
				Icon = "command",
			})
		end
	end
	table.sort(candidates, function(a: Candidate<Types.Command>, b: Candidate<Types.Command>): boolean
		return a.Key < b.Key
	end)
	return candidates
end

const function typeCandidates(request: Types.CandidateRequest): { read Candidate<Types.Type<unknown>> }
	const candidates: { Candidate<Types.Type<unknown>> } = {}
	const shell = ShellDirectory.Get(request.Shell)
	if shell == nil then
		return candidates
	end
	for _, valueType in shell.Registry:GetTypes() do
		table.insert(candidates, { Key = valueType.Name, Value = valueType, Description = valueType.Description })
	end
	table.sort(candidates, function(a: Candidate<Types.Type<unknown>>, b: Candidate<Types.Type<unknown>>): boolean
		return a.Key < b.Key
	end)
	return candidates
end

const function variableCandidates(request: Types.CandidateRequest): { read Candidate<string> }
	const candidates: { Candidate<string> } = {}
	const shell = ShellDirectory.Get(request.Shell)
	if shell == nil then
		return candidates
	end
	for name, value in shell:GetSession(request.Executor).Variables do
		table.insert(candidates, { Key = name, Value = name, Detail = value })
	end
	table.sort(candidates, function(a: Candidate<string>, b: Candidate<string>): boolean
		return a.Key < b.Key
	end)
	return candidates
end

const function parseKeybind(text: string): (Keybind?, string?)
	local ctrl, shift, alt = false, false, false
	const parts: { string } = {}
	for piece in text:gmatch("[^%+]+") do
		table.insert(parts, piece)
	end
	if #parts == 0 then
		return nil, "Expected a key such as F5 or Ctrl+Shift+K"
	end
	for index = 1, #parts - 1 do
		const modifier = parts[index]:lower()
		if modifier == "ctrl" or modifier == "control" or modifier == "cmd" then
			ctrl = true
		elseif modifier == "shift" then
			shift = true
		elseif modifier == "alt" or modifier == "option" then
			alt = true
		else
			return nil, `Unknown modifier '{parts[index]}' (use Ctrl, Shift or Alt)`
		end
	end
	const keyName = parts[#parts]
	const prefix = (if ctrl then "Ctrl+" else "") .. (if shift then "Shift+" else "") .. (if alt then "Alt+" else "")
	const mouse = MOUSE_INPUTS[keyName:lower()]
	if mouse then
		for _, item in Enum.UserInputType:GetEnumItems() do
			if item.Name == mouse then
				return { InputType = item, Ctrl = ctrl, Shift = shift, Alt = alt, Text = prefix .. item.Name }, nil
			end
		end
	end
	const lowered = keyName:lower()
	for _, item in Enum.KeyCode:GetEnumItems() do
		if item.Name:lower() == lowered then
			return { KeyCode = item, Ctrl = ctrl, Shift = shift, Alt = alt, Text = prefix .. item.Name }, nil
		end
	end
	return nil, `Unknown key '{keyName}'`
end

--// Types

const CommandType = TypeBuilder.Enumerable({
	Name = "command",
	Description = "A command name or alias",
	Candidates = commandCandidates,
	Color = "type.command",
	Icon = "command",
})

const TypeName = TypeBuilder.Enumerable({
	Name = "type",
	Description = "A registered type",
	Candidates = typeCandidates,
	Color = "type.command",
	Icon = "type",
})

const StoredKey = TypeBuilder.Custom({
	Name = "variable",
	Description = "A variable name (set with `set`)",
	Parse = function(request: ParseRequest): Types.ParseResult<string>
		const name = request.Text:gsub("^%$", "")
		if not name:match("^[%a_][%w_]*$") then
			return { Ok = false, Error = "Variable names use letters, digits and _", Span = request.Span }
		end
		return { Ok = true, Value = name, Display = "$" .. name }
	end,
	Complete = function(request: Types.CompleteRequest): { Types.Suggestion }
		const suggestions: { Types.Suggestion } = {}
		for _, candidate in variableCandidates(request) do
			if candidate.Key:lower():sub(1, #request.Text) == request.Text:lower() then
				table.insert(suggestions, {
					Text = candidate.Key,
					Display = "$" .. candidate.Key,
					Detail = candidate.Detail,
					Kind = "variable",
					Score = 0,
					MatchRanges = {},
				})
			end
		end
		return suggestions
	end,
	Color = "type.variable",
	Icon = "variable",
})

const KeybindType = TypeBuilder.Custom({
	Name = "keybind",
	Description = "A key with optional modifiers: F5, Ctrl+Shift+K, MouseButton2, ButtonX",
	Examples = { "F5", "Ctrl+Shift+K", "ButtonY" },
	Parse = function(request: ParseRequest): Types.ParseResult<Keybind>
		const keybind, err = parseKeybind(request.Text)
		if keybind == nil then
			return { Ok = false, Error = err or "Invalid key", Span = request.Span }
		end
		return { Ok = true, Value = keybind, Display = keybind.Text }
	end,
	Suggestions = {
		"F1",
		"F2",
		"F3",
		"F4",
		"F5",
		"F6",
		"F7",
		"F8",
		"F9",
		"Ctrl+Shift+",
		"MouseButton2",
		"ButtonX",
		"ButtonY",
	},
	Color = "type.string",
	Icon = "key",
})

const Material = TypeBuilder.FromEnumLazy({
	Name = "material",
	Enum = function()
		return Enum.Material
	end,
})

const KeyCode = TypeBuilder.FromEnumLazy({
	Name = "keycode",
	Enum = function()
		return Enum.KeyCode
	end,
})

--- Cached `enum:<Name>` types.
const enumTypes: { [string]: Types.Type<EnumItem> } = {}

--- Any Roblox enum by name: `EnumByName("HumanoidStateType")` (registered as `enum:HumanoidStateType`).
const function EnumByName(enumName: string): Types.Type<EnumItem>
	const existing = enumTypes[enumName]
	if existing then
		return existing
	end
	const created = TypeBuilder.Enumerable({
		Name = "enum:" .. enumName,
		Description = `A value of Enum.{enumName}`,
		Candidates = function(): { read Candidate<EnumItem> }
			const candidates: { Candidate<EnumItem> } = {}
			for _, enumObject in Enum:GetEnums() do
				if tostring(enumObject) == enumName then
					for _, item in enumObject:GetEnumItems() do
						table.insert(candidates, { Key = item.Name, Value = item, Detail = tostring(item.Value) })
					end
					break
				end
			end
			return candidates
		end,
		Color = "type.enum",
		Icon = "enum",
	})
	enumTypes[enumName] = created
	return created
end

const MetaTypes = {
	Command = CommandType,
	Commands = TypeBuilder.List(CommandType, { Name = "commands" }),
	TypeName = TypeName,
	StoredKey = StoredKey,
	Keybind = KeybindType,
	Material = Material,
	KeyCode = KeyCode,
	EnumByName = EnumByName,
	ParseKeybind = parseKeybind,
}

return table.freeze(MetaTypes)
