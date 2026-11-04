--!strict
--[[
	Prints the built-in command and type reference as Markdown
	(`bash scripts/run.sh scripts/reference.luau > docs/Reference.md`).
	The same generator is available at runtime as `RoShell.Docs.Markdown(registry)`.
--]]

const Docs = require(script.Parent.Parent.src.Shared.Docs)
const Test = require(script.Parent.Parent.src.Shared.Test)

const harness = Test.new({ Defaults = true })
print(Docs.Markdown(harness.Shell.Registry))
