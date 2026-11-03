--!strict
--[[
	The smallest useful command. Put modules like this in a folder and name it on the server (ServerStorage keeps
	the code private; players still get completion for the commands they may run):

		RoShell.new({ Commands = ServerStorage.Commands }):Start()

	`args` is fully typed: `args.who` is `{ Player }`, `args.times` is `number`.
--]]

--// Services
const ReplicatedStorage = game:GetService("ReplicatedStorage")

--// Imports
const RoShell = require(ReplicatedStorage.RoShell)

--// Command
return RoShell.Command({
	Name = "hello",
	Icon = "star",
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
