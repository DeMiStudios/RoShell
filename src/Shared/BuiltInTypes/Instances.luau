--!strict
--[[
	DataModel types.

	`instance` parses paths such as `workspace.Map.Door`, `Workspace["New Map"].Door`, `game.Lighting` or `.`/`me`
	(your character); completion walks the children of the path typed so far. `instances` also accepts `*`
	(children), `**` (descendants) and globs in the last segment (`workspace.Map.Door*`). `class`, `tag`,
	`remote` and `attribute` complete from the live game.
]]

--// Imports
const Fuzzy = require("../Fuzzy")
const Selector = require("../Selector")
const TypeBuilder = require("../TypeBuilder")
const Types = require("../Types")

--// Types
type ParseRequest = Types.ParseRequest
type CompleteRequest = Types.CompleteRequest

--// Constants
const ROOT_NAMES = {
	"game",
	"workspace",
	"Players",
	"Lighting",
	"ReplicatedStorage",
	"ReplicatedFirst",
	"ServerScriptService",
	"ServerStorage",
	"StarterGui",
	"StarterPack",
	"StarterPlayer",
	"Teams",
	"SoundService",
	"TextChatService",
	"MaterialService",
}
const COMMON_CLASSES = {
	"Part",
	"MeshPart",
	"WedgePart",
	"TrussPart",
	"SpawnLocation",
	"Seat",
	"VehicleSeat",
	"Model",
	"Folder",
	"Attachment",
	"Weld",
	"WeldConstraint",
	"Motor6D",
	"Humanoid",
	"Tool",
	"Accessory",
	"Decal",
	"Texture",
	"SurfaceGui",
	"BillboardGui",
	"ScreenGui",
	"Frame",
	"TextLabel",
	"TextButton",
	"TextBox",
	"ImageLabel",
	"ImageButton",
	"ScrollingFrame",
	"UICorner",
	"UIStroke",
	"UIGradient",
	"UIListLayout",
	"UIPadding",
	"Sound",
	"ParticleEmitter",
	"Beam",
	"Trail",
	"Fire",
	"Smoke",
	"Sparkles",
	"PointLight",
	"SpotLight",
	"SurfaceLight",
	"Highlight",
	"ProximityPrompt",
	"ClickDetector",
	"DragDetector",
	"Script",
	"LocalScript",
	"ModuleScript",
	"RemoteEvent",
	"RemoteFunction",
	"UnreliableRemoteEvent",
	"BindableEvent",
	"BindableFunction",
	"StringValue",
	"NumberValue",
	"IntValue",
	"BoolValue",
	"ObjectValue",
	"Vector3Value",
	"CFrameValue",
	"Color3Value",
	"Configuration",
	"Camera",
	"Team",
	"Animation",
	"Animator",
	"AnimationController",
}

--// Helpers

const function identity(text: string): string
	return text
end

const function fail(request: ParseRequest, message: string): Types.ParseError
	return { Ok = false, Error = message, Span = request.Span, Progress = 0 }
end

const function isIdentifier(name: string): boolean
	return name:match("^[%a_][%w_]*$") ~= nil
end

--- Formats a child step of a path.
const function step(name: string): string
	if isIdentifier(name) then
		return "." .. name
	end
	return '["' .. name:gsub('"', '\\"') .. '"]'
end

--- Splits a path into its root and child names. Returns nil and a message on malformed input.
const function splitPath(text: string): ({ string }?, string?)
	const segments: { string } = {}
	local position = 1
	const length = #text
	const rootName = text:match("^([^%.%[]+)")
	if rootName == nil then
		if text:sub(1, 1) == "." then
			table.insert(segments, ".")
			position = 2
		else
			return nil, "Expected a path such as workspace.Part"
		end
	else
		table.insert(segments, rootName)
		position = #rootName + 1
	end
	while position <= length do
		const char = text:sub(position, position)
		if char == "." then
			const name = text:match("^([^%.%[]*)", position + 1) or ""
			table.insert(segments, name)
			position += 1 + #name
		elseif char == "[" then
			const quote = text:sub(position + 1, position + 1)
			if quote ~= '"' and quote ~= "'" then
				return nil, "Expected a quoted name inside [ ]"
			end
			const closing = text:find(quote .. "]", position + 2, true)
			if closing == nil then
				return nil, "Unclosed [ ] in path"
			end
			table.insert(segments, (text:sub(position + 2, closing - 1):gsub('\\"', '"')))
			position = closing + 2
		else
			return nil, `Unexpected '{char}' in path`
		end
	end
	return segments, nil
end

const function findChild(parent: Instance, name: string): Instance?
	const exact = parent:FindFirstChild(name)
	if exact then
		return exact
	end
	const lowered = name:lower()
	for _, child in parent:GetChildren() do
		if child.Name:lower() == lowered then
			return child
		end
	end
	return nil
end

const function resolveRoot(name: string, request: Types.CandidateRequest): Instance?
	const lowered = name:lower()
	if lowered == "game" then
		return game
	elseif lowered == "workspace" then
		return workspace
	elseif lowered == "." or lowered == "me" or lowered == "@me" then
		const executor = request.Executor
		return if executor then executor.Character else nil
	end
	const ok, service = pcall(function(): Instance?
		return game:FindService(name)
	end)
	if ok and service then
		return service
	end
	return findChild(game, name)
end

--- Resolves every segment; returns the instance, or nil and a message naming the failing segment.
const function resolvePath(segments: { string }, request: Types.CandidateRequest): (Instance?, string?)
	local current = resolveRoot(segments[1], request)
	if current == nil then
		return nil, `Unknown root '{segments[1]}'`
	end
	local path = segments[1]
	for index = 2, #segments do
		const name = segments[index]
		const child = findChild(current, name)
		if child == nil then
			const names: { string } = {}
			for _, item in current:GetChildren() do
				table.insert(names, item.Name)
			end
			const suggestion = Fuzzy.Suggest(name, names)
			return nil, `'{path}' has no child '{name}'{if suggestion then `. Did you mean '{suggestion}'?` else ""}`
		end
		current = child
		path ..= step(name)
	end
	return current, nil
end

--- Completes the last segment of a path.
const function completePath(request: CompleteRequest): { Types.Suggestion }
	const text = request.Text
	const suggestions: { Types.Suggestion } = {}
	-- Position of the last separator outside quotes.
	local separator = 0
	local inQuote = false
	for position = 1, #text do
		const char = text:sub(position, position)
		if char == '"' then
			inQuote = not inQuote
		elseif not inQuote and (char == "." or char == "[") and position > 1 then
			separator = position
		end
	end
	if separator == 0 then
		for _, result in Fuzzy.Filter(text, ROOT_NAMES, identity, request.Limit) do
			table.insert(suggestions, {
				Text = result.Item,
				Display = result.Item,
				Kind = "instance",
				Score = result.Score,
				MatchRanges = result.Ranges,
				Partial = true,
			})
		end
		return suggestions
	end
	const parentText = text:sub(1, separator - 1)
	const partial = text:sub(separator + 1):gsub("^[\"']", "")
	const segments = splitPath(parentText)
	if segments == nil then
		return suggestions
	end
	const parent = resolvePath(segments, request)
	if parent == nil then
		return suggestions
	end
	const children = parent:GetChildren()
	const names: { string } = {}
	const classes: { [string]: string } = {}
	for _, child in children do
		if classes[child.Name] == nil then
			table.insert(names, child.Name)
			classes[child.Name] = child.ClassName
		end
	end
	for _, result in Fuzzy.Filter(partial, names, identity, request.Limit) do
		table.insert(suggestions, {
			Text = parentText .. step(result.Item),
			Display = result.Item,
			Detail = classes[result.Item],
			Kind = "instance",
			Score = result.Score,
			MatchRanges = result.Ranges,
			Partial = true,
		})
	end
	return suggestions
end

const function stringSuggestions(request: CompleteRequest, items: { string }, kind: string): { Types.Suggestion }
	const suggestions: { Types.Suggestion } = {}
	for _, result in Fuzzy.Filter(request.Text, items, identity, request.Limit) do
		table.insert(suggestions, {
			Text = result.Item,
			Display = result.Item,
			Kind = kind,
			Score = result.Score,
			MatchRanges = result.Ranges,
		})
	end
	return suggestions
end

const function allTags(): { string }
	const ok, tags = pcall(function(): { string }
		return game:GetService("CollectionService"):GetAllTags()
	end)
	return if ok then tags else {}
end

--// Types

const InstanceType = TypeBuilder.Custom({
	Name = "instance",
	Description = "An instance path: workspace.Map.Door, Workspace[\"New Map\"].Door, or . for your character",
	Examples = { "workspace.Baseplate", ".", 'workspace["My Model"]' },
	Parse = function(request: ParseRequest): Types.ParseResult<Instance>
		const segments, err = splitPath(request.Text)
		if segments == nil then
			return fail(request, err or "Invalid path")
		end
		const instance, resolveError = resolvePath(segments, request)
		if instance == nil then
			return fail(request, resolveError or "Not found")
		end
		return { Ok = true, Value = instance, Display = instance:GetFullName() }
	end,
	Complete = completePath,
	Default = function(request: ParseRequest): Instance?
		const executor = request.Executor
		return if executor then executor.Character else nil
	end,
	Color = "type.instance",
	Icon = "instance",
})

const Instances = TypeBuilder.Custom({
	Name = "instances",
	Description = "Instance paths; the last segment may be * (children), ** (descendants) or a glob",
	Examples = { "workspace.Map.*", "workspace.Map.Door*", "workspace.A,workspace.B" },
	Parse = function(request: ParseRequest): Types.ParseResult<{ Instance }>
		const found: { Instance } = {}
		const seen: { [Instance]: true } = {}
		const function add(instance: Instance)
			if not seen[instance] then
				seen[instance] = true
				table.insert(found, instance)
			end
		end
		for path in request.Text:gmatch("[^,]+") do
			const parentText, last = path:match("^(.*)%.([^%.%[]*)$")
			if parentText and last and (last == "*" or last == "**" or Selector.IsGlob(last)) then
				const segments, err = splitPath(parentText)
				if segments == nil then
					return fail(request, err or "Invalid path")
				end
				const parent, resolveError = resolvePath(segments, request)
				if parent == nil then
					return fail(request, resolveError or "Not found")
				end
				if last == "**" then
					for _, descendant in parent:GetDescendants() do
						add(descendant)
					end
				else
					const pattern = if last == "*" then nil else Selector.GlobToPattern(last:lower())
					for _, child in parent:GetChildren() do
						if pattern == nil or child.Name:lower():find(pattern) then
							add(child)
						end
					end
				end
			else
				const segments, err = splitPath(path)
				if segments == nil then
					return fail(request, err or "Invalid path")
				end
				const instance, resolveError = resolvePath(segments, request)
				if instance == nil then
					return fail(request, resolveError or "Not found")
				end
				add(instance)
			end
		end
		return { Ok = true, Value = found, Display = `{#found} instance(s)` }
	end,
	Complete = function(request: CompleteRequest): { Types.Suggestion }
		const head = request.Text:match("^(.*,)") or ""
		const inner = completePath({
			Text = request.Text:sub(#head + 1),
			Quoted = request.Quoted,
			Executor = request.Executor,
			Shell = request.Shell,
			Platform = request.Platform,
			Limit = request.Limit,
		})
		for _, suggestion in inner do
			suggestion.Text = head .. suggestion.Text
		end
		return inner
	end,
	Color = "type.instance",
	Icon = "instance",
})

const Class = TypeBuilder.Enumerable({
	Name = "class",
	Description = "A ClassName",
	Examples = { "Part", "Model" },
	Candidates = function(): { read Types.Candidate<string> }
		const candidates: { Types.Candidate<string> } = {}
		for _, name in COMMON_CLASSES do
			table.insert(candidates, { Key = name, Value = name })
		end
		return candidates
	end,
	CaseSensitive = false,
	Color = "type.instance",
	Icon = "class",
})

const Tag = TypeBuilder.Custom({
	Name = "tag",
	Description = "A CollectionService tag (existing tags are suggested)",
	Parse = function(request: ParseRequest): Types.ParseResult<string>
		if request.Text == "" or #request.Text > 100 then
			return fail(request, "Expected a tag name")
		end
		return { Ok = true, Value = request.Text, Display = request.Text }
	end,
	Complete = function(request: CompleteRequest): { Types.Suggestion }
		return stringSuggestions(request, allTags(), "tag")
	end,
	Color = "type.string",
	Icon = "tag",
})

const Remote = TypeBuilder.Enumerable({
	Name = "remote",
	Description = "A RemoteEvent or RemoteFunction",
	Candidates = function(): { read Types.Candidate<Instance> }
		const candidates: { Types.Candidate<Instance> } = {}
		for _, container in { game:GetService("ReplicatedStorage"), workspace } do
			for _, descendant in container:GetDescendants() do
				if descendant:IsA("RemoteEvent")
					or descendant:IsA("RemoteFunction")
					or descendant:IsA("UnreliableRemoteEvent") then
					table.insert(candidates, {
						Key = descendant.Name,
						Value = descendant,
						Detail = descendant:GetFullName(),
					})
				end
			end
		end
		return candidates
	end,
	Color = "type.instance",
	Icon = "remote",
})

const Attribute = TypeBuilder.String({
	Name = "attribute",
	Description = "An attribute name",
	Pattern = "^[%a_][%w_]*$",
	PatternMessage = "Attribute names use letters, digits and _ (and cannot start with a digit)",
	MaxLength = 100,
})

const InstanceTypes = {
	Instance = InstanceType,
	Instances = Instances,
	Class = Class,
	Tag = Tag,
	Remote = Remote,
	Attribute = Attribute,
	SplitPath = splitPath,
}

return table.freeze(InstanceTypes)
