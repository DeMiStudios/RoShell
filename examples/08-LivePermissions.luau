--!strict
--[[
	Who may use RoShell, edited live from the Creator Hub with ConfigService: no script changes, no new server.

	The experience config has a "Permissions" key: user ids, each with the permissions they have.

		{
			"156":     { "RoShell": true },
			"1234567": { "Moderator": true },
		}

	"RoShell" makes a player an admin (every command). Every other name is a role, which commands and command groups
	use like any other rule:

		shell.Permissions:SetGroup("Moderation", RoShell.Permissions.Role("Moderator"))
		RoShell.Command({ Name = "warn", Permissions = RoShell.Permissions.Role("Moderator"), ... })

	When the config is published, each server refreshes its snapshot and swaps the rules in place
	(`SetAdmins`, `DefineRole`). The next command anyone runs is checked against the new rules, and the server sends
	every player their new command list, so their console gains or loses commands without rejoining.

	Call from a server Script: `require(path.to.this)()`.
--]]

--// Services
const ConfigService = game:GetService("ConfigService")
const ReplicatedStorage = game:GetService("ReplicatedStorage")

--// Imports
const RoShell = require(ReplicatedStorage.RoShell)

--// Constants
const CONFIG_KEY = "Permissions"
--- The permission that grants every command. Any other name is a role.
const ADMIN = "RoShell"
--- Roles commands may reference. Listing them keeps a typo in the config from creating a role nothing uses.
const ROLES = { "Moderator" }

--// Functions
--- The user ids holding each permission, read from the config value. Anything malformed is reported and skipped.
const function readGrants(value: unknown): { [string]: { number } }
	const grants: { [string]: { number } } = {}
	if value == nil then
		return grants
	elseif typeof(value) ~= "table" then
		warn(`[RoShell] config "{CONFIG_KEY}" should be a table, got {typeof(value)}`)
		return grants
	end
	for key, permissions in value do
		const userId = tonumber(key)
		if userId == nil or userId ~= userId or userId % 1 ~= 0 then
			warn(`[RoShell] config "{CONFIG_KEY}": "{key}" is not a user id`)
			continue
		elseif typeof(permissions) ~= "table" then
			warn(`[RoShell] config "{CONFIG_KEY}" for {userId}: expected a table of permissions`)
			continue
		end
		for name, granted in permissions do
			if typeof(name) ~= "string" or (name ~= ADMIN and table.find(ROLES, name) == nil) then
				warn(`[RoShell] config "{CONFIG_KEY}" for {userId}: unknown permission "{name}"`)
			elseif typeof(granted) ~= "boolean" then
				warn(`[RoShell] config "{CONFIG_KEY}" for {userId}: "{name}" should be true or false`)
			elseif granted then
				grants[name] = grants[name] or {}
				table.insert(grants[name], userId)
			end
		end
	end
	return grants
end

--- Replaces the admins and roles with what the config says now.
const function apply(shell: RoShell.RoShell, value: unknown)
	const grants = readGrants(value)
	shell.Permissions:SetAdmins(RoShell.Permissions.Users(grants[ADMIN] or {}))
	for _, role in ROLES do
		shell.Permissions:DefineRole(role, RoShell.Permissions.Users(grants[role] or {}))
	end
end

--- Loads the config, retrying while ConfigService is unreachable. Until it loads, nobody but Studio testers has
--- access (permissions are default deny).
const function loadSnapshot(): ConfigSnapshot
	local delay = 1
	while true do
		const ok, result = pcall(ConfigService.GetConfigAsync, ConfigService)
		if ok then
			return result
		end
		warn(`[RoShell] could not load the experience config, retrying in {delay}s: {result}`)
		task.wait(delay)
		delay = math.min(delay * 2, 60)
	end
end

--// Live Permissions
return function(): RoShell.RoShell
	const shell = RoShell.new({ Commands = ReplicatedStorage:FindFirstChild("Commands") })
	shell.Permissions:SetGroup("Moderation", RoShell.Permissions.Role("Moderator"))
	shell:Start()

	task.spawn(
		function()
			const snapshot = loadSnapshot()
			apply(shell, snapshot:GetValue(CONFIG_KEY))
			-- Fires after `Refresh` when the value changed.
			snapshot:GetValueChangedSignal(CONFIG_KEY):Connect(function()
				apply(shell, snapshot:GetValue(CONFIG_KEY))
			end)
			-- A newer config was published: take it (this also fires after a dropped connection comes back).
			snapshot.UpdateAvailable:Connect(function()
				snapshot:Refresh()
			end)
		end
	)

	return shell
end
