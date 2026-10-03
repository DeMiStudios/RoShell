--!strict
-- Fixture for RegisterHooksIn: blocks the command named "blocked".
const Registry = require("../../../src/Shared/Registry")

return Registry.Hooks({
	BeforeRun = function(ctx): string?
		if ctx.Command.Name == "blocked" then
			return "Blocked by fixture hook"
		end
		return nil
	end,
})
