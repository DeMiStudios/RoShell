--!strict
--[[
	Demo: world commands — spawning loot, painting characters, a cancellable countdown with live progress, a
	prompt-driven poll, and client-only commands that never touch the network.

		spawnloot ~embers,~frost 5
		clearloot            (asks for confirmation; --yes skips it)
		paint me #ff8800
		countdown 10s        (Ctrl+C cancels)
		poll "Best weapon?" Sword,Bow,Shield
		weather night        (client only)
]]

--// Imports
const DemoTypes = require("../DemoTypes")
const Items = require("../Items")
const RoShell = require(game:GetService("ReplicatedStorage").RoShell)

--// Constants
const LOOT_FOLDER = "RoShellLoot"
const WEATHER: {
	[string]: { ClockTime: number, Brightness: number, FogEnd: number },
} = {
	clear = { ClockTime = 14, Brightness = 2, FogEnd = 100000 },
	dusk = { ClockTime = 18.2, Brightness = 1.4, FogEnd = 2000 },
	night = { ClockTime = 0, Brightness = 0.6, FogEnd = 1200 },
	storm = { ClockTime = 15, Brightness = 0.8, FogEnd = 250 },
}

--// Helpers

const function lootFolder(): Folder
	const existing = workspace:FindFirstChild(LOOT_FOLDER)
	if existing and existing:IsA("Folder") then
		return existing
	end
	const folder = Instance.new("Folder")
	folder.Name = LOOT_FOLDER
	folder.Parent = workspace
	return folder
end

const function origin(player: Player?): Vector3
	const character = if player then player.Character else nil
	const root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	if root and root:IsA("BasePart") then
		return root.Position + root.CFrame.LookVector * 8
	end
	return Vector3.new(0, 10, 0)
end

const function spawnItem(item: Items.Item, position: Vector3): BasePart
	const part = Instance.new("Part")
	part.Name = item.Name
	part.Shape = Enum.PartType.Ball
	part.Size = Vector3.new(1.6, 1.6, 1.6)
	part.Material = Enum.Material.Neon
	part.Color = item.Color
	part.Position = position
	part:SetAttribute("ItemId", item.Id)
	part.Parent = lootFolder()
	return part
end

--// Commands
const spawnloot = RoShell.Command({
	Name = "spawnloot",
	Description = "Spawns glowing loot in front of you",
	Group = "Demo",
	SupportsDryRun = true,
	Args = {
		{ items = RoShell.Arg(DemoTypes.Items, { Description = "Items to spawn (lists, globs, ~fuzzy)" }) },
		{ count = RoShell.Default(RoShell.Types.Integer, 1, { Description = "Copies of each" }) },
		{ radius = RoShell.Default(RoShell.Types.Number, 6, { Named = true, Description = "Scatter radius" }) },
	},
}):Preview(function(_ctx, args)
	const lines: { string } = {}
	for _, item in args.items do
		table.insert(lines, `{args.count}× {item.Name}`)
	end
	return lines
end):Run(function(ctx, args)
	const center = origin(ctx.Executor)
	const random = Random.new()
	const spawned: { BasePart } = {}
	for _, item in args.items do
		for _ = 1, args.count do
			const offset = Vector3.new(random:NextNumber(-1, 1), 0, random:NextNumber(-1, 1)) * args.radius
			table.insert(spawned, spawnItem(item, center + offset + Vector3.new(0, 3, 0)))
		end
	end
	ctx:Undoable({
		Description = "spawnloot",
		Undo = function()
			for _, part in spawned do
				part:Destroy()
			end
		end,
	})
	return ctx:Success(`Spawned {#spawned} loot`)
end)

const clearloot = RoShell.Command({
	Name = "clearloot",
	Description = "Removes all spawned loot",
	Group = "Demo",
	Destructive = true,
	SupportsDryRun = true,
	Args = {},
}):Preview(function()
	const folder = workspace:FindFirstChild(LOOT_FOLDER)
	return { `Would remove {if folder then #folder:GetChildren() else 0} loot` }
end):Run(function(ctx)
	const folder = workspace:FindFirstChild(LOOT_FOLDER)
	const count = if folder then #folder:GetChildren() else 0
	if folder then
		folder:Destroy()
	end
	return ctx:Success(`Removed {count} loot`)
end)

const paint = RoShell.Command({
	Name = "paint",
	Description = "Paints players' characters",
	Group = "Demo",
	Args = {
		{ targets = RoShell.Arg(RoShell.Types.Players) },
		{ color = RoShell.Arg(RoShell.Types.Color3, { Description = "A color name, #hex or r,g,b" }) },
	},
}):Run(function(ctx, args)
	const previous: { [BasePart]: Color3 } = {}
	for _, player in args.targets do
		const character = player.Character
		if character then
			for _, descendant in character:GetDescendants() do
				if descendant:IsA("BasePart") and descendant.Name ~= "HumanoidRootPart" then
					previous[descendant] = descendant.Color
					descendant.Color = args.color
				end
			end
		end
	end
	ctx:Undoable({
		Description = "paint",
		Undo = function()
			for part, color in previous do
				part.Color = color
			end
		end,
	})
	ctx:Color(args.color, `#{args.color:ToHex():upper()}`)
	return ctx:Success(`Painted {#args.targets} player(s)`)
end)

const countdown = RoShell.Command({
	Name = "countdown",
	Description = "Counts down with live progress (Ctrl+C cancels)",
	Group = "Demo",
	Args = {
		{ duration = RoShell.Arg(RoShell.Types.Duration) },
	},
}):Run(function(ctx, args)
	const total = math.max(args.duration, 0.1)
	const started = os.clock()
	while true do
		ctx:CheckCancelled()
		const elapsed = os.clock() - started
		if elapsed >= total then
			break
		end
		ctx:Progress({ Label = `{math.ceil(total - elapsed)}s left`, Fraction = elapsed / total })
		task.wait(0.2)
	end
	ctx:Progress({ Label = "Done", Fraction = 1 })
	return ctx:Success("Liftoff!")
end)

const poll = RoShell.Command({
	Name = "poll",
	Description = "Asks you to pick one of several options",
	Group = "Demo",
	Args = {
		{ question = RoShell.Arg(RoShell.Types.String) },
		{ options = RoShell.Arg(RoShell.Types.Strings, { Description = "Comma-separated options" }) },
	},
}):Run(function(ctx, args)
	const answer = ctx:Choose(args.question, args.options)
	if answer == nil then
		return ctx:Warn("No answer")
	end
	return ctx:Success(`You picked {answer}`)
end)

const weather = RoShell.Command({
	Name = "weather",
	Description = "Changes the sky on your screen only (client command)",
	Group = "Demo",
	Args = {
		{ preset = RoShell.Arg(DemoTypes.Weather) },
	},
}):ClientRun(function(ctx, args)
	const preset = WEATHER[args.preset]
	const Lighting = game:GetService("Lighting")
	game:GetService("TweenService"):Create(Lighting, TweenInfo.new(1.2), {
		ClockTime = preset.ClockTime,
		Brightness = preset.Brightness,
		FogEnd = preset.FogEnd,
	}):Play()
	return ctx:Success(`Weather set to {args.preset}`)
end)

const fov = RoShell.Command({
	Name = "fov",
	Description = "Sets your camera's field of view (client command)",
	Group = "Demo",
	Args = {
		{ degrees = RoShell.Arg(RoShell.Type.Number({ Name = "degrees", Min = 30, Max = 120 })) },
	},
}):ClientRun(function(ctx, args)
	const camera = workspace.CurrentCamera
	if camera then
		game:GetService("TweenService"):Create(camera, TweenInfo.new(0.4), { FieldOfView = args.degrees }):Play()
	end
	return ctx:Success(`Field of view: {args.degrees}°`)
end)

return { spawnloot, clearloot, paint, countdown, poll, weather, fov }
