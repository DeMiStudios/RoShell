--!strict
--[[
	Moderation and player commands (group "Admin"). These are denied by default: grant them with
	`server.Permissions:SetGroup("Admin", RoShell.Permissions.Allow({ ... }))`.
]]

--// Imports
const BuiltInTypes = require("../Shared/BuiltInTypes")
const Command = require("../Shared/Command")
const Types = require("../Shared/Types")
const Util = require("../Shared/Util")

--// Types
type Context = Types.Context

--// Constants
const T = BuiltInTypes.Types
const SPEED = BuiltInTypes.Types.Numbers

--// Helpers

const function humanoidOf(player: Player): Humanoid?
	const character = player.Character
	return if character then character:FindFirstChildOfClass("Humanoid") else nil
end

const function rootOf(player: Player): BasePart?
	const character = player.Character
	if character == nil then
		return nil
	end
	const root = character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root
	end
	return character.PrimaryPart
end

const function names(players: { Player }): string
	const list: { string } = {}
	for _, player in players do
		table.insert(list, player.Name)
	end
	return Util.Truncate(table.concat(list, ", "), 80)
end

--- Moves players and registers an undo that puts them back.
const function teleport(ctx: Context, players: { Player }, destination: CFrame, description: string): number
	const previous: { [Player]: CFrame } = {}
	local moved = 0
	for index, player in players do
		const character = player.Character
		if character then
			previous[player] = character:GetPivot()
			-- Spread several players out a little so they don't stack.
			const offset = Vector3.new(((index - 1) % 4) * 3, 0, ((index - 1) // 4) * 3)
			character:PivotTo(destination + offset)
			moved += 1
		end
	end
	if moved > 0 then
		ctx:Undoable({
			Description = description,
			Undo = function()
				for player, pivot in previous do
					const character = player.Character
					if character then
						character:PivotTo(pivot)
					end
				end
			end,
		})
	end
	return moved
end

const function standingCFrame(player: Player): CFrame?
	const root = rootOf(player)
	return if root then root.CFrame * CFrame.new(0, 0, -4) else nil
end

--// Commands

const kick = Command.new({
	Name = "kick",
	Icon = "circle-minus",
	Description = "Kicks players from the server",
	Group = "Admin",
	Examples = { "kick Bob", 'kick *-Bob --reason "AFK"' },
	Args = {
		{ targets = Command.Arg(T.Players, { RequireConfirmAbove = 3, Pipe = true }) },
		{ reason = Command.Default(T.String, "Kicked by a moderator", { Short = "r" }) },
	},
}):Run(function(ctx, args)
	const kicked: { Player } = {}
	for _, player in args.targets do
		if player ~= ctx.Executor then
			player:Kick(args.reason)
			table.insert(kicked, player)
		end
	end
	if #kicked == 0 then
		return ctx:Warn("Nobody was kicked (you cannot kick yourself)")
	end
	ctx:Log(`kicked {names(kicked)}: {args.reason}`)
	return ctx:Success(`Kicked {names(kicked)}`)
end)

const kill = Command.new({
	Name = "kill",
	Icon = "sword",
	Description = "Kills players' characters",
	Group = "Admin",
	Args = { { targets = Command.Arg(T.Players, { RequireConfirmAbove = 5, Pipe = true }) } },
}):Run(function(ctx, args)
	local count = 0
	for _, player in args.targets do
		const humanoid = humanoidOf(player)
		if humanoid then
			humanoid.Health = 0
			count += 1
		end
	end
	return ctx:Success(`Killed {count} player(s)`)
end)

const respawn = Command.new({
	Name = "respawn",
	Icon = "circle-plus",
	Aliases = { "re", "refresh" },
	Description = "Respawns players",
	Group = "Admin",
	Args = {
		{
			targets = Command.DefaultFn(T.Players, function(request: Types.ParseRequest): { Player }
				return if request.Executor then { request.Executor } else {}
			end, "you", { Pipe = true }),
		},
	},
}):Run(function(ctx, args)
	for _, player in args.targets do
		task.spawn(function()
			player:LoadCharacterAsync()
		end)
	end
	return ctx:Success(`Respawning {names(args.targets)}`)
end)

const teleportCommand = Command.new({
	Name = "teleport",
	Icon = "location-pin",
	Aliases = { "tp" },
	Description = "Teleports players to another player (undoable)",
	Group = "Admin",
	Examples = { "tp Bob Alice", "tp * .", "tp %Red ${players ?}" },
	Args = { { targets = Command.Arg(T.Players, { Pipe = true }) }, { destination = Command.Arg(T.Player) } },
}):Run(function(ctx, args)
	const destination = standingCFrame(args.destination)
	if destination == nil then
		return ctx:Error(`{args.destination.Name} has no character`)
	end
	const moved = teleport(ctx, args.targets, destination, `teleport to {args.destination.Name}`)
	return ctx:Success(`Teleported {moved} player(s) → {args.destination.Name}`)
end)

const to = Command.new({
	Name = "to",
	Icon = "compass",
	Aliases = { "goto" },
	Description = "Teleports you to a player (undoable)",
	Group = "Admin",
	Args = { { target = Command.Arg(T.Player) } },
}):Run(function(ctx, args)
	const executor = ctx.Executor
	const destination = standingCFrame(args.target)
	if executor == nil or destination == nil then
		return ctx:Error("Both you and the target need a character")
	end
	teleport(ctx, { executor }, destination, `go to {args.target.Name}`)
	return ctx:Success(`Teleported to {args.target.Name}`)
end)

const bring = Command.new({
	Name = "bring",
	Icon = "person",
	Description = "Brings players to you (undoable)",
	Group = "Admin",
	Args = { { targets = Command.Arg(T.Players, { Pipe = true }) } },
}):Run(function(ctx, args)
	const executor = ctx.Executor
	const destination = if executor then standingCFrame(executor) else nil
	if destination == nil then
		return ctx:Error("You need a character")
	end
	const moved = teleport(ctx, args.targets, destination, "bring")
	return ctx:Success(`Brought {moved} player(s)`)
end)

const heal = Command.new({
	Name = "heal",
	Icon = "heart",
	Description = "Restores players' health",
	Group = "Admin",
	Args = {
		{
			targets = Command.DefaultFn(T.Players, function(request: Types.ParseRequest): { Player }
				return if request.Executor then { request.Executor } else {}
			end, "you", { Pipe = true }),
		},
	},
}):Run(function(ctx, args)
	local count = 0
	for _, player in args.targets do
		const humanoid = humanoidOf(player)
		if humanoid then
			humanoid.Health = humanoid.MaxHealth
			count += 1
		end
	end
	return ctx:Success(`Healed {count} player(s)`)
end)

const speed = Command.new({
	Name = "speed",
	Icon = "person-running",
	Aliases = { "setspeed", "walkspeed" },
	Description = "Sets walk speed; several values (or a range) are assigned in turn (undoable)",
	Group = "Admin",
	Examples = { "speed . 32", "setspeed Bo* 16..32/8" },
	Args = {
		{ targets = Command.Arg(T.Players, { Pipe = true }) },
		{ speeds = Command.Arg(SPEED, { Description = "Speed(s): 16, 16,24 or 16..32/8" }) },
	},
}):Run(function(ctx, args)
	if #args.speeds == 0 then
		return ctx:Error("Give at least one speed")
	end
	const previous: { [Humanoid]: number } = {}
	const assigned: { string } = {}
	for index, player in args.targets do
		const humanoid = humanoidOf(player)
		if humanoid then
			const value = args.speeds[(index - 1) % #args.speeds + 1]
			previous[humanoid] = humanoid.WalkSpeed
			humanoid.WalkSpeed = value
			table.insert(assigned, `{player.Name}={Util.FormatNumber(value)}`)
		end
	end
	ctx:Undoable({
		Description = "speed change",
		Undo = function()
			for humanoid, value in previous do
				if humanoid.Parent then
					humanoid.WalkSpeed = value
				end
			end
		end,
	})
	return ctx:Success(`Walk speed: {Util.Truncate(table.concat(assigned, ", "), 120)}`)
end)

const freeze = Command.new({
	Name = "freeze",
	Icon = "lock-closed",
	Description = "Freezes players in place",
	Group = "Admin",
	Args = { { targets = Command.Arg(T.Players, { Pipe = true }) } },
}):Run(function(ctx, args)
	for _, player in args.targets do
		const root = rootOf(player)
		if root then
			root.Anchored = true
		end
	end
	return ctx:Success(`Froze {names(args.targets)}`)
end)

const thaw = Command.new({
	Name = "thaw",
	Icon = "sun",
	Aliases = { "unfreeze" },
	Description = "Unfreezes players",
	Group = "Admin",
	Args = { { targets = Command.Arg(T.Players, { Pipe = true }) } },
}):Run(function(ctx, args)
	for _, player in args.targets do
		const root = rootOf(player)
		if root then
			root.Anchored = false
		end
	end
	return ctx:Success(`Thawed {names(args.targets)}`)
end)

const announce = Command.new({
	Name = "announce",
	Icon = "speaker-high",
	Aliases = { "m", "broadcast" },
	Description = "Shows a message to everyone (every server with --global)",
	Group = "Admin",
	Examples = { "announce Loot dropped!", "announce Restarting soon --global" },
	Args = {
		{ message = Command.Arg(T.String) },
		{ global = Command.Flag({ Short = "g", Description = "Send to every server" }) },
	},
}):Run(function(ctx, args)
	const ok, problem = ctx:Broadcast(args.message, {
		Scope = if args.global then "global" else "server",
		Level = "info",
	})
	if not ok then
		return ctx:Warn(`Announced in this server only: {problem}`)
	end
	return ctx:Success(if args.global then "Announced to every server" else "Announced")
end)

const shutdown = Command.new({
	Name = "shutdown",
	Icon = "circle-x",
	Description = "Kicks everyone and closes the server, after an optional countdown",
	Group = "Admin",
	Destructive = true,
	SupportsDryRun = true,
	-- The countdown may be long; it is cancellable with Ctrl+C / `cancel` instead of timing out.
	Timeout = 0,
	Examples = { "shutdown", 'shutdown "Updating!" --delay 30s', "in 5m shutdown" },
	Args = {
		{ reason = Command.Default(T.String, "The server is restarting", { Description = "Shown to everyone" }) },
		{ delay = Command.Default(T.Duration, 0, { Named = true, Short = "d", Description = "Countdown first" }) },
	},
}):Preview(function(ctx, args)
	const count = #ctx.Shell.Platform.GetPlayers()
	const when = if args.delay > 0 then ` in {Util.FormatDuration(args.delay)}` else ""
	return { `Would kick {count} player(s){when}: {args.reason}` }
end):Run(
	function(ctx, args)
		const platform = ctx.Shell.Platform
		if args.delay > 0 then
			ctx:Broadcast(`Server shutting down in {Util.FormatDuration(args.delay)}: {args.reason}`, {
				Level = "warning",
			})
			const finish = platform.Clock() + args.delay
			while platform.Clock() < finish do
				ctx:CheckCancelled()
				platform.Wait(math.min(1, finish - platform.Clock()))
			end
		end
		-- Refuse new joins (engine only; headless tests have no Players service).
		pcall(function()
			game:GetService("Players").PlayerAdded:Connect(function(player: Player)
				player:Kick(args.reason)
			end)
		end)
		const everyone = platform.GetPlayers()
		for _, player in everyone do
			player:Kick(args.reason)
		end
		ctx:Log(`shutdown: {args.reason}`)
		return ctx:Success(`Shut down ({#everyone} player(s) kicked)`)
	end
)

const players = Command.new({
	Name = "players",
	Icon = "two-people",
	Description = "Lists (and returns) players, optionally filtered by a team",
	Group = "Utility",
	Returns = T.Players,
	Examples = { "players", "players --team Red | kick" },
	Args = {
		{ filter = Command.Default(T.Players, {}, { AllowEmpty = true, Description = "Defaults to everyone" }) },
		{ team = Command.Optional(T.Team, { Named = true, Short = "t" }) },
	},
}):ClientRun(function(ctx, args)
	local list = if #args.filter > 0 then args.filter else ctx.Shell.Platform.GetPlayers()
	const team = args.team
	if team then
		const filtered: { Player } = {}
		for _, player in list do
			if player.Team == team then
				table.insert(filtered, player)
			end
		end
		list = filtered
	end
	const rows: { { string } } = {}
	for _, player in list do
		table.insert(rows, { player.Name, player.DisplayName, if player.Team then player.Team.Name else "—" })
	end
	ctx:Table({ Columns = { "Name", "Display name", "Team" }, Rows = rows })
	return ctx:Value(T.Players, list, `{#list} player(s)`)
end)

return {
	kick,
	kill,
	respawn,
	teleportCommand,
	to,
	bring,
	heal,
	speed,
	freeze,
	thaw,
	announce,
	shutdown,
	players,
} :: { Types.Command }
