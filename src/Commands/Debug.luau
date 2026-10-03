--!strict
--[[
	Debugging and world-inspection commands (group "Debug", denied by default outside Studio).
]]

--// Imports
const BuiltInTypes = require("../Shared/BuiltInTypes")
const Command = require("../Shared/Command")
const Keys = require("../Shared/Keys")
const TypeBuilder = require("../Shared/TypeBuilder")
const Types = require("../Shared/Types")
const Util = require("../Shared/Util")

--// Types
type Context = Types.Context

type Property = {
	Name: string,
	Class: string,
	Type: Types.Type<unknown>,
	Get: (instance: Instance) -> unknown,
	Set: ((instance: Instance, value: unknown) -> boolean)?,
}

--// Constants
const T = BuiltInTypes.Types

const PROPERTIES: { Property } = {
	{
		Name = "Name",
		Class = "Instance",
		Type = T.String,
		Get = function(instance)
			return instance.Name
		end,
		Set = function(instance, value)
			if type(value) == "string" then
				instance.Name = value
				return true
			end
			return false
		end,
	},
	{
		Name = "ClassName",
		Class = "Instance",
		Type = T.String,
		Get = function(instance)
			return instance.ClassName
		end,
	},
	{
		Name = "Parent",
		Class = "Instance",
		Type = T.Instance,
		Get = function(instance)
			return instance.Parent
		end,
		Set = function(instance, value)
			if typeof(value) == "Instance" then
				instance.Parent = value
				return true
			end
			return false
		end,
	},
	{
		Name = "Position",
		Class = "BasePart",
		Type = T.Vector3,
		Get = function(instance)
			return if instance:IsA("BasePart") then instance.Position else nil
		end,
		Set = function(instance, value)
			if instance:IsA("BasePart") and typeof(value) == "Vector3" then
				instance.Position = value
				return true
			end
			return false
		end,
	},
	{
		Name = "Size",
		Class = "BasePart",
		Type = T.Vector3,
		Get = function(instance)
			return if instance:IsA("BasePart") then instance.Size else nil
		end,
		Set = function(instance, value)
			if instance:IsA("BasePart") and typeof(value) == "Vector3" then
				instance.Size = value
				return true
			end
			return false
		end,
	},
	{
		Name = "Color",
		Class = "BasePart",
		Type = T.Color3,
		Get = function(instance)
			return if instance:IsA("BasePart") then instance.Color else nil
		end,
		Set = function(instance, value)
			if instance:IsA("BasePart") and typeof(value) == "Color3" then
				instance.Color = value
				return true
			end
			return false
		end,
	},
	{
		Name = "Transparency",
		Class = "BasePart",
		Type = TypeBuilder.Number({ Name = "transparency", Min = 0, Max = 1 }),
		Get = function(instance)
			return if instance:IsA("BasePart") then instance.Transparency else nil
		end,
		Set = function(instance, value)
			if instance:IsA("BasePart") and type(value) == "number" then
				instance.Transparency = value
				return true
			end
			return false
		end,
	},
	{
		Name = "Anchored",
		Class = "BasePart",
		Type = T.Boolean,
		Get = function(instance)
			return if instance:IsA("BasePart") then instance.Anchored else nil
		end,
		Set = function(instance, value)
			if instance:IsA("BasePart") and type(value) == "boolean" then
				instance.Anchored = value
				return true
			end
			return false
		end,
	},
	{
		Name = "CanCollide",
		Class = "BasePart",
		Type = T.Boolean,
		Get = function(instance)
			return if instance:IsA("BasePart") then instance.CanCollide else nil
		end,
		Set = function(instance, value)
			if instance:IsA("BasePart") and type(value) == "boolean" then
				instance.CanCollide = value
				return true
			end
			return false
		end,
	},
	{
		Name = "Material",
		Class = "BasePart",
		Type = T.Material,
		Get = function(instance)
			return if instance:IsA("BasePart") then instance.Material else nil
		end,
		Set = function(instance, value)
			if instance:IsA("BasePart") then
				for _, item in Enum.Material:GetEnumItems() do
					if item == value then
						instance.Material = item
						return true
					end
				end
			end
			return false
		end,
	},
	{
		Name = "Health",
		Class = "Humanoid",
		Type = T.Number,
		Get = function(instance)
			return if instance:IsA("Humanoid") then instance.Health else nil
		end,
		Set = function(instance, value)
			if instance:IsA("Humanoid") and type(value) == "number" then
				instance.Health = value
				return true
			end
			return false
		end,
	},
	{
		Name = "WalkSpeed",
		Class = "Humanoid",
		Type = T.Number,
		Get = function(instance)
			return if instance:IsA("Humanoid") then instance.WalkSpeed else nil
		end,
		Set = function(instance, value)
			if instance:IsA("Humanoid") and type(value) == "number" then
				instance.WalkSpeed = value
				return true
			end
			return false
		end,
	},
	{
		Name = "JumpPower",
		Class = "Humanoid",
		Type = T.Number,
		Get = function(instance)
			return if instance:IsA("Humanoid") then instance.JumpPower else nil
		end,
		Set = function(instance, value)
			if instance:IsA("Humanoid") and type(value) == "number" then
				instance.JumpPower = value
				return true
			end
			return false
		end,
	},
	{
		Name = "Visible",
		Class = "GuiObject",
		Type = T.Boolean,
		Get = function(instance)
			return if instance:IsA("GuiObject") then instance.Visible else nil
		end,
		Set = function(instance, value)
			if instance:IsA("GuiObject") and type(value) == "boolean" then
				instance.Visible = value
				return true
			end
			return false
		end,
	},
}

const PROPERTY_NAMES: { string } = {}
for _, property in PROPERTIES do
	table.insert(PROPERTY_NAMES, property.Name)
end

const PropertyName = TypeBuilder.String({
	Name = "property",
	Description = "A property (common ones are suggested) or an attribute name",
	Pattern = "^[%a_][%w_]*$",
	Suggestions = PROPERTY_NAMES,
})

--// Helpers

const function findProperty(instance: Instance, name: string): Property?
	const lowered = name:lower()
	for _, property in PROPERTIES do
		if property.Name:lower() == lowered and instance:IsA(property.Class) then
			return property
		end
	end
	return nil
end

--- Type for a value of an attribute, from its current value.
const function typeForValue(value: unknown): Types.Type<unknown>
	const kind = typeof(value)
	if kind == "number" then
		return T.Number
	elseif kind == "boolean" then
		return T.Boolean
	elseif kind == "Vector3" then
		return T.Vector3
	elseif kind == "Vector2" then
		return T.Vector2
	elseif kind == "Color3" then
		return T.Color3
	elseif kind == "BrickColor" then
		return T.BrickColor
	end
	return T.String
end

--// Commands

const inspect = Command.new({
	Name = "inspect",
	Icon = "magnifying-glass",
	Description = "Shows an instance's properties, attributes and tags; sets a property or attribute (undoable)",
	Group = "Debug",
	Examples = { "inspect workspace.Baseplate", "inspect workspace.Baseplate Transparency 0.5", "inspect . Health" },
	Args = {
		{ instance = Command.Arg(T.Instance) },
		{ property = Command.Optional(PropertyName) },
		{
			value = Command.Dynamic(function(request: Types.DynamicArgRequest): Types.Type<unknown>?
				const instance = request.Previous.instance
				const name = request.Previous.property
				if typeof(instance) ~= "Instance" or type(name) ~= "string" then
					return nil
				end
				const property = findProperty(instance, name)
				if property then
					return property.Type
				end
				return typeForValue(instance:GetAttribute(name))
			end, { Description = "New value (typed from the property)" }),
		},
	},
}):Run(function(ctx, args)
	const instance = args.instance
	const name = args.property
	if name == nil then
		const entries: { { Key: string, Value: string } } = {}
		for _, property in PROPERTIES do
			if instance:IsA(property.Class) then
				table.insert(entries, { Key = property.Name, Value = Util.FormatValue(property.Get(instance)) })
			end
		end
		table.insert(entries, { Key = "Children", Value = tostring(#instance:GetChildren()) })
		ctx:KeyValue(entries, instance:GetFullName())
		const attributes: { { Key: string, Value: string } } = {}
		for key, value in instance:GetAttributes() do
			table.insert(attributes, { Key = key, Value = Util.FormatValue(value) })
		end
		if #attributes > 0 then
			table.sort(attributes, function(a: { Key: string, Value: string }, b: { Key: string, Value: string }): boolean
				return a.Key < b.Key
			end)
			ctx:KeyValue(attributes, "Attributes")
		end
		const tags = game:GetService("CollectionService"):GetTags(instance)
		if #tags > 0 then
			ctx:List(tags, "Tags")
		end
		return ctx:Value(T.Instance, instance, instance:GetFullName())
	end
	const property = findProperty(instance, name)
	const current: unknown = if property then property.Get(instance) else instance:GetAttribute(name)
	if args.value == nil then
		return ctx:Info(`{name} = {Util.FormatValue(current)}`)
	end
	const newValue = args.value
	if property then
		const setter = property.Set
		if setter == nil then
			return ctx:Error(`{property.Name} is read-only`)
		end
		if not setter(instance, newValue) then
			return ctx:Error(`Could not set {property.Name}`)
		end
		ctx:Undoable({
			Description = `{instance.Name}.{property.Name}`,
			Undo = function()
				setter(instance, current)
			end,
			Redo = function()
				setter(instance, newValue)
			end,
		})
	else
		instance:SetAttribute(name, newValue)
		ctx:Undoable({
			Description = `{instance.Name}@{name}`,
			Undo = function()
				instance:SetAttribute(name, current)
			end,
			Redo = function()
				instance:SetAttribute(name, newValue)
			end,
		})
	end
	return ctx:Success(`{instance.Name}.{name}: {Util.FormatValue(current)} → {Util.FormatValue(newValue)}`)
end)

const tags = Command.new({
	Name = "tags",
	Icon = "tag",
	Description = "Lists the CollectionService tags of an instance, or every tag in use",
	Group = "Debug",
	Args = { { instance = Command.Optional(T.Instance) } },
}):Run(function(ctx, args)
	const CollectionService = game:GetService("CollectionService")
	const list = if args.instance then CollectionService:GetTags(args.instance) else CollectionService:GetAllTags()
	if #list == 0 then
		return ctx:Info("No tags")
	end
	table.sort(list)
	return ctx:List(list, if args.instance then args.instance.Name else "Tags in use")
end)

const tag = Command.new({
	Name = "tag",
	Icon = "tag",
	Description = "Adds a CollectionService tag to instances (undoable)",
	Group = "Debug",
	Args = { { instances = Command.Arg(T.Instances) }, { name = Command.Arg(T.Tag) } },
}):Run(function(ctx, args)
	const CollectionService = game:GetService("CollectionService")
	for _, instance in args.instances do
		CollectionService:AddTag(instance, args.name)
	end
	ctx:Undoable({
		Description = `tag {args.name}`,
		Undo = function()
			for _, instance in args.instances do
				CollectionService:RemoveTag(instance, args.name)
			end
		end,
	})
	return ctx:Success(`Tagged {#args.instances} instance(s) with {args.name}`)
end)

const untag = Command.new({
	Name = "untag",
	Icon = "tag",
	Description = "Removes a CollectionService tag from instances",
	Group = "Debug",
	Args = { { instances = Command.Arg(T.Instances) }, { name = Command.Arg(T.Tag) } },
}):Run(function(ctx, args)
	const CollectionService = game:GetService("CollectionService")
	for _, instance in args.instances do
		CollectionService:RemoveTag(instance, args.name)
	end
	return ctx:Success(`Removed {args.name} from {#args.instances} instance(s)`)
end)

const blink = Command.new({
	Name = "blink",
	Icon = "eye",
	Aliases = { "b" },
	Description = "Teleports you to where your mouse points",
	Group = "Debug",
	Args = {},
}):Data(function(): unknown
	const player = game:GetService("Players").LocalPlayer
	return if player then player:GetMouse().Hit.Position else nil
end):Run(function(ctx)
	const target = ctx:GetData()
	const executor = ctx.Executor
	const character = if executor then executor.Character else nil
	if typeof(target) ~= "Vector3" or character == nil then
		return ctx:Error("Point at something with your mouse first")
	end
	const previous = character:GetPivot()
	character:PivotTo(CFrame.new(target + Vector3.new(0, 3, 0)))
	ctx:Undoable({
		Description = "blink",
		Undo = function()
			character:PivotTo(previous)
		end,
	})
	return nil
end)

const position = Command.new({
	Name = "position",
	Icon = "crosshairs",
	Aliases = { "pos" },
	Description = "Returns your position",
	Group = "Debug",
	Returns = T.Vector3,
	Args = {},
}):Run(function(ctx)
	const executor = ctx.Executor
	const character = if executor then executor.Character else nil
	if character == nil then
		return ctx:Error("You have no character")
	end
	const value = character:GetPivot().Position
	return ctx:Value(T.Vector3, value, Util.FormatValue(value))
end)

const audit = Command.new({
	Name = "audit",
	Icon = "shield-check",
	Description = "Shows the most recent commands run on this server",
	Group = "Debug",
	Args = { { count = Command.Default(TypeBuilder.Integer({ Min = 1, Max = 200 }), 20) } },
}):Run(function(ctx, args)
	const sink = ctx:GetEnv(Keys.Audit)
	const recent = if sink and sink.Recent then sink.Recent(sink, args.count) else nil
	if recent == nil then
		return ctx:Error("The audit sink does not keep history")
	end
	const rows: { { string } } = {}
	for _, entry in recent do
		table.insert(rows, {
			DateTime.fromUnixTimestamp(entry.Time):FormatLocalTime("HH:mm:ss", "en-us"),
			entry.Executor,
			Util.Truncate(entry.Raw, 60),
			if entry.Ok then "✓" else "×",
			Util.FormatDuration(entry.Duration),
		})
	end
	return ctx:Table({ Title = "Audit log", Columns = { "Time", "Who", "Command", "", "Took" }, Rows = rows })
end)

const reload = Command.new({
	Name = "reload",
	Icon = "arrow-large-down",
	Description = "Hot-reloads commands registered with RegisterCommandsIn (client and server)",
	Group = "Debug",
	Args = {},
}):ClientRun(
	function(ctx)
		const count = ctx.Shell.Registry:ReloadCommands()
		ctx:Info(`Reloaded {count} client command(s)`)
		-- nil continues on the server.
		return nil
	end
):Run(function(ctx)
	const count = ctx.Shell.Registry:ReloadCommands()
	return ctx:Success(`Reloaded {count} server command(s)`)
end)

return { inspect, tags, tag, untag, blink, position, audit, reload } :: { Types.Command }
