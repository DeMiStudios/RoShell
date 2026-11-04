--!strict
--[[
	Headless test entry: `bash scripts/test.sh`, which runs this file under the Luau CLI through the headless loader
	(scripts/headless.py and scripts/Headless.luau), so the instance requires resolve as they do in Studio.
--]]

const Runner = require(script.Parent.Runner)
const Specs = require(script.Parent.Specs)

const summary = Runner.Run(Specs, { Verbose = false })
if summary.Failed > 0 then
	error(`{summary.Failed} test(s) failed`, 0)
end
