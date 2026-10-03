--!strict
--[[
	The smallest useful command. Put modules like this in a folder and register it on both sides:

		server.Registry:RegisterCommandsIn(ReplicatedStorage.Commands)
		client.Registry:RegisterCommandsIn(ReplicatedStorage.Commands)

	`args` is fully typed: `args.who` is `{ Player }`, `args.times` is `number`.
]]

const RoShell = require(game:GetService("ReplicatedStorage").RoShell)

return RoShell.Command({
	Name = "hello",
	Description = "Greets players",
	Group = "Fun",
	Examples = { "hello me", "hello * 3", "hello %Red" },
	Args = {
		{ who = RoShell.Arg(RoShell.Types.Players, { Description = "Who to greet" }) },
		{ times = RoShell.Default(RoShell.Types.Integer, 1) },
	},
}):Run(function(ctx, args)
	for _, player in args.who do
		for _ = 1, args.times do
			ctx:Reply(`Hello, {player.DisplayName}!`)
		end
	end
	return ctx:Success(`Greeted {#args.who} player(s)`)
end)
