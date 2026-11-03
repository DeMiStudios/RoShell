--!strict
--[[
	A plugin bundles commands, types, hooks and middleware so they can be shared between games:

		shell.Registry:RegisterPlugin(require(path.to.this))   -- on the server, and on clients for client parts

	Client-side themes ship the same way (`RoShell.Theme.Create` at require time registers them by name).
--]]

--// Services
const ReplicatedStorage = game:GetService("ReplicatedStorage")

--// Imports
const RoShell = require(ReplicatedStorage.RoShell)

--// Themes
-- Registers the "Sunset" theme for `theme Sunset` / `config theme Sunset`.
RoShell.Theme.Create({
	Name = "Sunset",
	Base = "Midnight",
	Overrides = {
		Accent = "#FF9E64",
		AccentHover = "#FFB787",
		BorderFocus = "#FF9E64",
		Syntax = { Command = "#FF9E64", String = "#9ECE6A" },
	},
})

--// Argument Types
const Weather = RoShell.Type.Choice<<"sunny" | "rain" | "snow">>({
	Name = "weather",
	Choices = { "sunny", "rain", "snow" },
})

--// Commands
const forecast = RoShell.Command({
	Name = "forecast",
	Icon = "cloud",
	Description = "Announces tomorrow's weather",
	Group = "Fun",
	Args = { { weather = RoShell.Arg(Weather) } },
}):Run(function(ctx, args)
	ctx:Broadcast(`Tomorrow: {args.weather}`)
	return ctx:Success("Announced")
end)

--// Plugin
return RoShell.Plugin({
	Name = "Weather",
	Commands = { forecast },
	Types = { Weather },
	Hooks = {
		AfterRun = function(ctx, result)
			if ctx.Command.Name == "forecast" and result.Ok then
				workspace:SetAttribute("LastForecast", os.time())
			end
		end,
	},
})
