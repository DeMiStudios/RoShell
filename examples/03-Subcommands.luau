--!strict
--[[
	Subcommands, flags, named arguments, confirmations, dry runs and undo:

		ban add Bob --reason "spamming" --days 3
		ban add Bob,Alice -s              (silent)
		ban remove Bob
		ban list
		ban clear --dry                   (preview)
		ban clear --yes                   (skip the confirmation)
		undo
]]

const RoShell = require(game:GetService("ReplicatedStorage").RoShell)

type Ban = {
	UserId: number,
	Name: string,
	Reason: string,
	Until: number,
}

-- In-memory for the example; real games keep bans in a DataStore (see `ctx:GetStore`).
const bans: { [number]: Ban } = {}

const add = RoShell.Command({
	Name = "add",
	Description = "Bans players",
	Args = {
		{ targets = RoShell.Arg(RoShell.Types.Players) },
		{ reason = RoShell.Default(RoShell.Types.String, "No reason given", { Named = true }) },
		{ days = RoShell.Default(RoShell.Types.Integer, 1, { Named = true, Short = "d" }) },
		{ silent = RoShell.Flag({ Short = "s", Description = "Don't announce" }) },
	},
}):Run(function(ctx, args)
	const added: { number } = {}
	for _, player in args.targets do
		bans[player.UserId] = {
			UserId = player.UserId,
			Name = player.Name,
			Reason = args.reason,
			Until = os.time() + args.days * 86400,
		}
		table.insert(added, player.UserId)
		player:Kick(`Banned for {args.days} day(s): {args.reason}`)
	end
	ctx:Undoable({
		Description = "ban add",
		Undo = function()
			for _, userId in added do
				bans[userId] = nil
			end
		end,
	})
	if not args.silent then
		ctx:Broadcast(`{#added} player(s) were banned`, { Level = "warning" })
	end
	return ctx:Success(`Banned {#added} player(s) for {args.days} day(s)`)
end)

const remove = RoShell.Command({
	Name = "remove",
	Description = "Lifts a ban",
	Args = { { userId = RoShell.Arg(RoShell.Types.UserId) } },
}):Run(function(ctx, args)
	if bans[args.userId] == nil then
		return ctx:Warn("That user is not banned")
	end
	bans[args.userId] = nil
	return ctx:Success("Ban lifted")
end)

const list = RoShell.Command({ Name = "list", Description = "Lists bans", Args = {} }):Run(function(ctx)
	const rows: { { string } } = {}
	for _, ban in bans do
		table.insert(rows, { ban.Name, ban.Reason, os.date("%Y-%m-%d", ban.Until) })
	end
	return ctx:Table({ Columns = { "Player", "Reason", "Until" }, Rows = rows })
end)

const clear = RoShell.Command({
	Name = "clear",
	Description = "Removes every ban",
	Destructive = true,
	SupportsDryRun = true,
	Args = {},
}):Preview(function()
	local count = 0
	for _ in bans do
		count += 1
	end
	return { `Would lift {count} ban(s)` }
end):Run(function(ctx)
	table.clear(bans)
	return ctx:Success("All bans lifted")
end)

return RoShell.Command({
	Name = "ban",
	Description = "Manages bans",
	Group = "Admin",
	Subcommands = { add, remove, list, clear },
	Args = {},
})
