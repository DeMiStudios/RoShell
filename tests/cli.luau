--!strict
--[[
	Headless test entry: `luau tests/cli.luau`.
]]

const Runner = require("./Runner")
const Specs = require("./Specs")

const summary = Runner.Run(Specs, { Verbose = false })
if summary.Failed > 0 then
	error(`{summary.Failed} test(s) failed`, 0)
end
