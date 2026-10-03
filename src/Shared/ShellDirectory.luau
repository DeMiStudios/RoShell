--!strict
--[[
	Maps the lightweight `ShellHandle` carried by parse/complete requests back to the full shell. Requests carry a
	handle (not the shell) because generic types cannot reference the recursive `Shell` type; see Types.luau.
]]

--// Imports
const Types = require("./Types")

--// Globals
-- Weak keys: a shell that is garbage collected disappears from the directory.
const shells: { [Types.ShellHandle]: Types.Shell } = setmetatable({}, { __mode = "k" })
local lastId = 0

--// ShellDirectory
const ShellDirectory = {}

--- Allocates a unique shell id.
function ShellDirectory.NextId(): number
	lastId += 1
	return lastId
end

--- Registers a shell so its handle can be resolved.
function ShellDirectory.Register(shell: Types.Shell)
	shells[shell] = shell
end

--- Removes a shell.
function ShellDirectory.Unregister(shell: Types.Shell)
	shells[shell] = nil
end

--- Returns the full shell for a handle.
function ShellDirectory.Get(handle: Types.ShellHandle): Types.Shell?
	return shells[handle]
end

return table.freeze(ShellDirectory)
