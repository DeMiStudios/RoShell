--!strict
--[[
	Commands whose code stays on the server: the server describes them per player, the description crosses the
	network boundary, and a client registers stand-ins that complete, check and forward like real commands.
--]]

--// Imports
const BuiltInTypes = require("../../src/Shared/BuiltInTypes")
const Command = require("../../src/Shared/Command")
const Completion = require("../../src/Shared/Completion")
const FakeWorld = require("../support/FakeWorld")
const Manifest = require("../../src/Shared/Manifest")
const Net = require("../../src/Shared/Net")
const Permissions = require("../../src/Shared/Permissions")
const Platform = require("../../src/Shared/Platform")
const Runner = require("../Runner")
const Shell = require("../../src/Shared/Shell")
const TypeBuilder = require("../../src/Shared/TypeBuilder")
const Types = require("../../src/Shared/Types")

--// Constants
const STRICT: Types.ShellOptions = { StudioBypass = false }

--// Functions
-- Server-only types and commands (a fresh set per server, as each test registers them on its own shell).
const function serverCommands(): { Types.Command }
	const Resource = TypeBuilder.Dynamic({
		Name = "resource",
		Description = "A resource in the vault",
		Candidates = function(): { Types.Candidate<string> }
			return {
				{ Key = "gold", Value = "gold", Detail = "25" },
				{ Key = "silver", Value = "silver", Aliases = { "ag" } },
				{ Key = "secret", Value = "secret", Hidden = true },
			}
		end,
	})
	const Note = TypeBuilder.String({ Name = "note", Suggestions = { "urgent", "later" } })

	const deposit = Command.new({
		Name = "deposit",
		Description = "Adds resources",
		Args = {
			{ resources = Command.Arg(TypeBuilder.List(Resource, { Name = "resources" })) },
			{ amount = Command.Default(BuiltInTypes.Types.Integer, 1, { Short = "n" }) },
			{ quiet = Command.Flag({ Short = "q" }) },
			{ note = Command.Optional(Note, { Named = true }) },
		},
	}):Run(function(_ctx, args)
		return `deposited {table.concat(args.resources, ",")} x{args.amount}`
	end)

	const vault = Command.new({
		Name = "vault",
		Aliases = { "bank" },
		Description = "The vault",
		Group = "Economy",
		Examples = { "vault deposit gold 5" },
		Args = {},
		Subcommands = { deposit },
	}):Run(function()
		return "balances"
	end)

	const ping = Command.new({
		Name = "ping",
		Group = "Staff",
		Args = { { who = Command.Arg(BuiltInTypes.Types.Players) } },
	}):Run(function()
		return "pong"
	end)

	const clientOnly = Command.new({ Name = "localfx", Args = {} }):ClientRun(function()
		return "fx"
	end)
	return { vault, ping, clientOnly }
end

const function serverShell(platform: Types.PlatformInfo, options: Types.ShellOptions?): Types.Shell
	const shell = Shell.new({ IsServer = true, IsClient = false, Platform = platform, Options = options })
	shell.Registry:RegisterDefaultCommands()
	shell.Registry:RegisterCommands(serverCommands())
	shell.Registry:RegisterCommand(Command.Alias("hi", "echo hi"))
	return shell
end

const function clientShell(platform: Types.PlatformInfo): Types.Shell
	const shell = Shell.new({ IsServer = false, IsClient = true, Platform = platform })
	shell.Registry:RegisterDefaultCommands()
	return shell
end

-- What a client reads from the server's description of `player`'s commands (as it crosses the network).
const function received(shell: Types.Shell, player: Player?): { Net.CommandInfo }
	return Net.ReadManifest(Manifest.Describe(shell, player))
end

const function find(infos: { Net.CommandInfo }, name: string): Net.CommandInfo?
	for _, info in infos do
		if info.Name == name then
			return info
		end
	end
	return nil
end

const function names(infos: { Net.CommandInfo }): { string }
	const list: { string } = {}
	for _, info in infos do
		table.insert(list, info.Name)
	end
	table.sort(list)
	return list
end

const function suggestionTexts(shell: Types.Shell, text: string): { string }
	const list: { string } = {}
	for _, suggestion in Completion.Query({ Shell = shell, Text = text, Cursor = #text + 1 }).Suggestions do
		table.insert(list, suggestion.Text)
	end
	return list
end

-- A transport that records what the client sends and answers like a server would.
const function recordingTransport(sent: { Types.RemoteRunRequest }): Types.Transport
	return {
		RunRemote = function(
			_self: Types.Transport,
			request: Types.RemoteRunRequest,
			_token: Types.CancelToken,
			_onBlock: (block: Types.Block) -> (),
			_onPrompt: ((prompt: Types.PromptRequest) -> Types.PromptAnswer)?
		): Types.CommandResult
			table.insert(sent, request)
			return table.freeze({
				Ok = true,
				Command = "vault",
				Message = nil,
				Value = nil,
				Blocks = {},
				Duration = 0,
				Cancelled = false,
			})
		end,
	}
end

return function(t: Runner.Api)
	t.describe(
		"Describing commands",
		function()
			t.it("describes the server's own commands, not the built-ins, aliases or client-only ones", function()
				const infos = received(serverShell(Platform.Headless().Platform), nil)
				t.expect(names(infos)):toEqual({ "ping", "vault" })
			end)

			t.it(
				"names built-in types and carries what custom types show",
				function()
					const vault = find(received(serverShell(Platform.Headless().Platform), nil), "vault")
					t.expect(vault ~= nil):toBe(true)
					if vault == nil then
						return
					end
					t.expect(vault.Aliases):toEqual({ "bank" })
					t.expect(vault.Group):toBe("Economy")
					t.expect(vault.Runs):toBe(true)
					t.expect(#vault.Subcommands):toBe(1)

					const deposit = vault.Subcommands[1]
					t.expect(deposit.Name):toBe("deposit")
					const resources = deposit.Args[1].Type
					t.expect(resources.Kind):toBe("list")
					t.expect(resources.BuiltIn):toBe(false)
					const element = resources.Element
					t.expect(element ~= nil):toBe(true)
					if element then
						const candidates = element.Candidates or {}
						-- Hidden candidates stay on the server.
						t.expect(#candidates):toBe(2)
						t.expect(candidates[1].Key):toBe("gold")
						t.expect(candidates[1].Detail):toBe("25")
						t.expect(candidates[2].Aliases):toEqual({ "ag" })
					end

					const amount = deposit.Args[2]
					t.expect(amount.Kind):toBe("default")
					t.expect(amount.DefaultDisplay):toBe("1")
					t.expect(amount.Type.BuiltIn):toBe(true)
					t.expect(amount.Options.Short):toBe("n")
					t.expect(deposit.Args[3].Kind):toBe("flag")

					const suggestions = deposit.Args[4].Type.Suggestions or {}
					t.expect(#suggestions):toBe(2)
					t.expect(deposit.Args[4].Options.Named):toBe(true)
				end
			)

			t.it(
				"describes types whose values have to wait as free text, without waiting",
				function()
					const controller = Platform.Headless()
					const shell = Shell.new({ IsServer = true, IsClient = false, Platform = controller.Platform })
					local asked = 0
					const Slow = TypeBuilder.Dynamic({
						Name = "slow",
						Candidates = function(request: Types.CandidateRequest): { Types.Candidate<string> }
							asked += 1
							request.Platform.Wait(5)
							return { { Key = "late", Value = "late" } }
						end,
					})
					shell.Registry:RegisterCommand(
						Command.new({ Name = "fetch", Args = { { what = Command.Arg(Slow) } } }):Run(function()
							return nil
						end)
					)
					const fetch = find(received(shell, nil), "fetch")
					t.expect(asked):toBe(1)
					t.expect(fetch ~= nil and fetch.Args[1].Type.Candidates):toBeNil()
					-- The abandoned wait never finishes into anything.
					controller:Advance(10)
				end
			)

			t.it("describes only what the player may run", function()
				const world = FakeWorld.new({}, { "Bob", "Alice" })
				const shell = serverShell(world.Controller.Platform, STRICT)
				const bob, alice = world.Players.Bob, world.Players.Alice
				t.expect(names(received(shell, bob))):toEqual({})

				shell.Permissions:SetGroup("Staff", Permissions.Users({ bob.UserId }))
				t.expect(names(received(shell, bob))):toEqual({ "ping" })
				t.expect(names(received(shell, alice))):toEqual({})

				shell.Permissions:SetAdmins(Permissions.Users({ alice.UserId }))
				t.expect(names(received(shell, alice))):toEqual({ "ping", "vault" })
			end)
		end
	)

	t.describe("The network boundary", function()
		t.it("drops malformed entries and commands with unreadable arguments", function()
			t.expect(#Net.ReadManifest(nil)):toBe(0)
			t.expect(#Net.ReadManifest("vault")):toBe(0)
			const infos = Net.ReadManifest({
				{ Name = "ok", Args = {} },
				{ Name = 5 },
				{ Name = "badkind", Args = { { Name = "x", Kind = "weird", Type = { Name = "t", Kind = "custom" } } } },
				{ Name = "notype", Args = { { Name = "x", Kind = "required" } } },
				"junk",
			})
			t.expect(names(infos)):toEqual({ "ok" })
			t.expect(infos[1].Runs):toBe(false)
			t.expect(infos[1].Description):toBe("")
		end)

		t.it("bounds what it reads", function()
			const candidates: { { Key: string } } = {}
			for index = 1, 2000 do
				table.insert(candidates, { Key = `v{index}` })
			end
			const infos = Net.ReadManifest({
				{
					Name = "big",
					Description = string.rep("d", 5000),
					Args = {
						{
							Name = "x",
							Kind = "required",
							Type = { Name = "t", Kind = "enumerable", Candidates = candidates },
						},
					},
				},
			})
			t.expect(#infos):toBe(1)
			t.expect(#infos[1].Description):toBe(0)
			const kept = infos[1].Args[1].Type.Candidates or {}
			t.expect(#kept):toBe(500)
		end)
	end)

	t.describe(
		"Stand-ins on the client",
		function()
			t.it(
				"complete and check like the real commands",
				function()
					const platform = Platform.Headless().Platform
					const server = serverShell(platform)
					const client = clientShell(platform)
					Manifest.Apply(client, received(server, nil))

					const vault = client.Registry:GetCommand("bank")
					t.expect(vault ~= nil and vault.Name):toBe("vault")
					t.expect(vault ~= nil and vault._remote):toBe(true)
					t.expect(suggestionTexts(client, "vault deposit go")[1]):toBe("gold")
					t.expect(suggestionTexts(client, "vault deposit gold 2 --note ")):toContain("urgent")

					-- Lists, fuzzy matches and aliases of the server's values work on the client.
					t.expect(client.Dispatcher:Evaluate({ Text = "vault deposit gold,ag 3" }).Ok):toBe(true)
					t.expect(client.Dispatcher:Evaluate({ Text = "vault deposit ~silv" }).Ok):toBe(true)
					t.expect(client.Dispatcher:Evaluate({ Text = "vault deposit secret" }).Ok):toBe(false)
					t.expect(client.Dispatcher:Evaluate({ Text = "vault deposit" }).Ok):toBe(false)
					-- The built-in type is the client's own.
					t.expect(client.Dispatcher:Evaluate({ Text = "vault deposit gold -n x" }).Ok):toBe(false)
				end
			)

			t.it(
				"send the line to the server",
				function()
					const platform = Platform.Headless().Platform
					const server = serverShell(platform)
					const client = clientShell(platform)
					const sent: { Types.RemoteRunRequest } = {}
					client._transport = recordingTransport(sent)
					Manifest.Apply(client, received(server, nil))

					const result = client.Dispatcher:Run({ Text = "bank deposit gold 3 -q" })
					t.expect(result.Ok):toBe(true)
					t.expect(#sent):toBe(1)
					-- The server resolves aliases itself, so the line goes as typed.
					t.expect(sent[1].Text):toBe("bank deposit gold 3 -q")
				end
			)

			t.it("are replaced by newer descriptions and never replace the client's own commands", function()
				const platform = Platform.Headless().Platform
				const server = serverShell(platform)
				const client = clientShell(platform)
				const own = Command.new({ Name = "ping", Description = "The client's own", Args = {} }):ClientRun(function()
					return "local pong"
				end)
				client.Registry:RegisterCommand(own)

				t.expect(Manifest.Apply(client, received(server, nil))):toEqual({ "vault" })
				t.expect(client.Registry:GetCommand("ping")):toBe(own)

				server.Registry:UnregisterCommand("vault")
				t.expect(Manifest.Apply(client, received(server, nil))):toEqual({})
				t.expect(client.Registry:GetCommand("vault")):toBeNil()
				t.expect(client.Registry:GetCommand("bank")):toBeNil()
			end)
		end
	)
end
