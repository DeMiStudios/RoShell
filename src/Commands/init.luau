--!strict
--[[
	Built-in commands. Each is written with the typed API and doubles as an example of idiomatic use.

	Groups and default permissions:
	- Help, Utility: everyone (they only affect the executor's own console, or are read-only).
	- Admin, Debug, Schedule: denied by default (except in Studio); grant with `Permissions:SetGroup(group, ...)`.
]]

const Admin = require("@self/Admin")
const Debug = require("@self/Debug")
const Help = require("@self/Help")
const Schedule = require("@self/Schedule")
const Types = require("./Shared/Types")
const Utility = require("@self/Utility")

const commands: { Types.Command } = {}
for _, group in { Help, Utility, Admin, Debug, Schedule } do
	for _, command in group do
		table.insert(commands, command)
	end
end

return commands
