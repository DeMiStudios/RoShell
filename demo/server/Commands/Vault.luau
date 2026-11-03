--!strict
--[[
	Demo: server-private commands. This folder sits under the server Script, so clients never receive its code.
	Each player gets a description of the commands they may run instead, and the console completes, highlights and
	checks them like any other (the `resource` values below come from the server).

		vault                        (the vault's balances)
		vault deposit gold 25
		vault withdraw ~gem 3
		vault withdraw gold,silver 5
		vault reset                  (asks first; --yes skips it)
--]]

--// Services
const ReplicatedStorage = game:GetService("ReplicatedStorage")

--// Imports
const RoShell = require(ReplicatedStorage.RoShell)

--// Constants
const RESOURCES = table.freeze({ "gold", "silver", "gems", "crystals", "relics" })

--// Globals
const balances: { [string]: number } = {}

--// Functions
const function balanceOf(resource: string): number
	return balances[resource] or 0
end

const function summary(): { string }
	const lines: { string } = {}
	for _, resource in RESOURCES do
		table.insert(lines, `{resource}: {balanceOf(resource)}`)
	end
	return lines
end

--// Types
-- A server-only type: its values (with their balances as details) reach clients through the command description.
const Resource = RoShell.Type.Dynamic({
	Name = "resource",
	Description = "A resource kept in the server's vault",
	Candidates = function(): { RoShell.Candidate<string> }
		const candidates: { RoShell.Candidate<string> } = {}
		for _, resource in RESOURCES do
			table.insert(candidates, { Key = resource, Value = resource, Detail = tostring(balanceOf(resource)) })
		end
		return candidates
	end,
	Icon = "diamond-gem",
})

const Resources = RoShell.Type.List(Resource, { Name = "resources" })
const Amount = RoShell.Type.Integer({ Name = "amount", Min = 1, Max = 1000000 })

--// Commands
const deposit = RoShell.Command({
	Name = "deposit",
	Icon = "circle-plus",
	Description = "Adds resources to the vault",
	Args = {
		{ resources = RoShell.Arg(Resources, { Description = "What to add (lists, globs, ~fuzzy)" }) },
		{ amount = RoShell.Arg(Amount) },
	},
}):Run(function(ctx, args)
	for _, resource in args.resources do
		balances[resource] = balanceOf(resource) + args.amount
	end
	return ctx:Success(`Deposited {args.amount} {table.concat(args.resources, ", ")}`)
end)

const withdraw = RoShell.Command({
	Name = "withdraw",
	Icon = "circle-minus",
	Description = "Takes resources out of the vault",
	Args = {
		{ resources = RoShell.Arg(Resources, { Description = "What to take (lists, globs, ~fuzzy)" }) },
		{ amount = RoShell.Arg(Amount) },
	},
}):Validate(function(_ctx, args)
	for _, resource in args.resources do
		if balanceOf(resource) < args.amount then
			return false, `The vault has only {balanceOf(resource)} {resource}`
		end
	end
	return true, nil
end):Run(function(ctx, args)
	for _, resource in args.resources do
		balances[resource] = balanceOf(resource) - args.amount
	end
	return ctx:Success(`Withdrew {args.amount} {table.concat(args.resources, ", ")}`)
end)

const reset = RoShell.Command({
	Name = "reset",
	Icon = "trash",
	Description = "Empties the vault",
	Destructive = true,
	SupportsDryRun = true,
	Args = {},
}):Preview(function()
	return summary()
end):Run(function(ctx)
	table.clear(balances)
	return ctx:Success("The vault is empty")
end)

return RoShell.Command({
	Name = "vault",
	Icon = "lock",
	Description = "A vault whose code stays on the server",
	Group = "Demo",
	Args = {},
	Subcommands = { deposit, withdraw, reset },
}):Run(function(ctx)
	return ctx:List(summary(), "Vault")
end)
