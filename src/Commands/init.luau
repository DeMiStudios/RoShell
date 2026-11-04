--!strict
--[[
	Built-in commands. Each is written with the typed API and doubles as an example of idiomatic use.

	Groups and default permissions:
	- Help, Utility: everyone (they only affect the executor's own console, or are read-only).
	- Admin, Debug, Schedule: denied by default (except in Studio); grant with `Permissions:SetGroup(group, ...)`.
--]]

const Admin = require(script.Admin)
const Debug = require(script.Debug)
const Help = require(script.Help)
const Schedule = require(script.Schedule)
const Types = require(script.Parent.Shared.Types)
const Utility = require(script.Utility)

const commands: { Types.Command } = {}
for _, group in { Help, Utility, Admin, Debug, Schedule } do
	for _, command in group do
		table.insert(commands, command)
	end
end

return commands
