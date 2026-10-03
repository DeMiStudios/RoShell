--!strict
--[[
	A production server setup: DataStore-backed user data, a combined audit sink (memory + DataStore + webhook),
	role-based permissions, global hooks and middleware, plugin registration.

	Call from a server Script: `require(path.to.this)()`.
]]

const HttpService = game:GetService("HttpService")
const ReplicatedStorage = game:GetService("ReplicatedStorage")

const RoShell = require(ReplicatedStorage.RoShell)
const Plugin = require("./06-Plugin")

--- An audit sink that posts every command to a webhook (e.g. a moderation channel). Failures never block commands.
const function webhookSink(url: string): RoShell.AuditSink
	return {
		Write = function(_self: RoShell.AuditSink, entry)
			task.spawn(pcall, function()
				HttpService:PostAsync(
					url,
					HttpService:JSONEncode({
						content = `**{entry.Executor}** ran \`{entry.Raw}\` ({if entry.Ok then "ok" else "failed"})`,
					})
				)
			end)
		end,
	}
end

return function()
	const server = RoShell.Server.new({
		Storage = RoShell.Storage.DataStore("RoShellUserData"),
		Audit = RoShell.Audit.Fanout({
			RoShell.Audit.Memory(500),
			RoShell.Audit.DataStore("RoShellAudit"),
			webhookSink("https://example.com/webhook"),
		}),
		RateLimit = { Burst = 30, PerSecond = 8 },
	})

	-- Roles map to permission rules; command groups map to roles.
	const permissions = server.Permissions
	permissions:DefineRole("Moderator", RoShell.Permissions.Group(1234567, 100))
	permissions:DefineRole(
		"Admin",
		RoShell.Permissions.Any({
			RoShell.Permissions.Group(1234567, 250),
			RoShell.Permissions.Users({ 1, 156 }),
		})
	)
	permissions:SetGroup("Admin", RoShell.Permissions.Role("Admin"))
	permissions:SetGroup("Debug", RoShell.Permissions.Role("Admin"))
	permissions:SetGroup("Schedule", RoShell.Permissions.Role("Moderator"))
	permissions:SetGroup("Fun", RoShell.Permissions.Everyone())

	-- Global hooks: block commands during a cutscene, log failures.
	server.Registry:RegisterHooks({
		BeforeRun = function(ctx): string?
			if workspace:GetAttribute("Cutscene") == true and ctx.Command.Group ~= "Admin" then
				return "Commands are disabled during cutscenes"
			end
			return nil
		end,
		OnError = function(ctx, message: string)
			warn(`[Commands] {ctx.Command.Name} failed: {message}`)
		end,
	})

	-- Middleware wraps every execution (here: timing).
	server.Registry:RegisterMiddleware(function(ctx, nextHandler)
		const started = os.clock()
		const result = nextHandler()
		ctx:Log(`{ctx.Command.Name} took {math.floor((os.clock() - started) * 1000)} ms`)
		return result
	end)

	server.Registry:RegisterDefaultCommands()
	server.Registry:RegisterPlugin(Plugin)
	server:Start()
	return server
end
