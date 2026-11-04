--!strict
--[[
	Commands whose code stays on the server: the server describes them per player, the description crosses the
	network boundary, and a client registers stand-ins that complete, check and forward like real commands.
--]]

--// Imports
const BuiltInTypes = require(script.Parent.Parent.Parent.src.Shared.BuiltInTypes)
const Command = require(script.Parent.Parent.Parent.src.Shared.Command)
const Completion = require(script.Parent.Parent.Parent.src.Shared.Completion)
const FakeWorld = require(script.Parent.Parent.support.FakeWorld)
const Manifest = require(script.Parent.Parent.Parent.src.Shared.Manifest)
const Net = require(script.Parent.Parent.Parent.src.Shared.Net)
const Permissions = require(script.Parent.Parent.Parent.src.Shared.Permissions)
const Platform = require(script.Parent.Parent.Parent.src.Shared.Platform)
const Runner = require(script.Parent.Parent.Runner)
const Shell = require(script.Parent.Parent.Parent.src.Shared.Shell)
const Test = require(script.Parent.Parent.Parent.src.Shared.Test)
const TypeBuilder = require(script.Parent.Parent.Parent.src.Shared.TypeBuilder)
const Types = require(script.Parent.Parent.Parent.src.Shared.Types)

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

-- A client shell that checks permissions (no Studio bypass), as in a live game.
const function strictClient(platform: Types.PlatformInfo): Types.Shell
	const shell = Shell.new({ IsServer = false, IsClient = true, Platform = platform, Options = STRICT })
	shell.Registry:RegisterDefaultCommands()
	return shell
end

-- What a client allows after the server's handshake for `player`: the names the server lets it run.
const function allow(client: Types.Shell, server: Types.Shell, player: Player?)
	const allowed: { [string]: true } = {}
	for _, name in Manifest.Runnable(server, player) do
		allowed[name] = true
	end
	client.Permissions._visibility = allowed
end

-- Hidden root commands kept for typing by name (old chat command names), runnable by the "Staff" group.
const function hiddenCommands(): { Types.Command }
	const setgold = Command.new({
		Name = "setgold",
		Aliases = { "gold" },
		Description = "Sets your gold",
		Group = "Staff",
		Hidden = true,
		Args = { { amount = Command.Arg(BuiltInTypes.Types.Integer) } },
	}):Run(function(_ctx, args)
		return `gold = {args.amount}`
	end)
	const setround = Command.new({ Name = "setround", Group = "Staff", Args = {} }):Run(function()
		return "round set"
	end)
	return { setgold, setround }
end

-- A server-only type with an own value per player (each player's island, keyed by its owner's name). Dave has none.
const function islandCommands(withDefault: boolean): { Types.Command }
	const Island = TypeBuilder.Enumerable({
		Name = "ownedIsland",
		Noun = "island",
		Plural = "islands",
		Candidates = function(): { Types.Candidate<string> }
			return {
				{ Key = "Bob", Value = "island:Bob" },
				{ Key = "Alice", Value = "island:Alice" },
				{ Key = "Carol", Value = "island:Carol" },
			}
		end,
		Default = if withDefault then function(request: Types.ParseRequest): string?
				const executor = request.Executor
				return if executor and executor.Name ~= "Dave" then `island:{executor.Name}` else nil
			end
			else nil,
	})
	const visit = Command.new({ Name = "visit", Args = { { island = Command.Arg(Island) } } }):Run(function()
		return "visited"
	end)
	const gold = Command.new({
		Name = "islandgold",
		Args = {
			{ islands = Command.Arg(TypeBuilder.List(Island)) },
			{ amount = Command.Arg(BuiltInTypes.Types.Integer) },
		},
	}):Run(function()
		return "set"
	end)
	return { visit, gold }
end

-- The value the first argument of `text` resolves to (nil when the line does not check).
const function valueOf(shell: Types.Shell, text: string): unknown
	const evaluation = shell.Dispatcher:Evaluate({ Text = text })
	const command = evaluation.Commands[1]
	if not evaluation.Ok or command == nil then
		return nil
	end
	return command.Args[1].Value
end

-- The error of the first argument of `text`.
const function firstError(shell: Types.Shell, text: string): string?
	const command = shell.Dispatcher:Evaluate({ Text = text }).Commands[1]
	return if command then command.Args[1].Error else nil
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
				Canceled = false,
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

	t.describe(
		"Hidden commands",
		function()
			t.it("run from a client's console when typed by name or alias", function()
				const world = FakeWorld.new({}, { "Bob" })
				const bob = world.Players.Bob
				const server = serverShell(world.Controller.Platform, STRICT)
				server.Registry:RegisterCommands(hiddenCommands())
				server.Permissions:SetGroup("Staff", Permissions.Users({ bob.UserId }))
				world.Controller:SetLocalPlayer(bob)
				const client = strictClient(world.Controller.Platform)
				const sent: { Types.RemoteRunRequest } = {}
				client._transport = recordingTransport(sent)
				Manifest.Apply(client, received(server, bob))
				allow(client, server, bob)

				t.expect(Manifest.Runnable(server, bob)):toContain("setgold")
				t.expect(client.Dispatcher:Run({ Text = "setgold 5" }).Ok):toBe(true)
				t.expect(client.Dispatcher:Run({ Text = "gold 7" }).Ok):toBe(true)
				t.expect(#sent):toBe(2)
				t.expect(sent[1].Text):toBe("setgold 5")
			end)

			t.it(
				"are left out of completion, listings and the palette",
				function()
					const world = FakeWorld.new({}, { "Bob" })
					const bob = world.Players.Bob
					const server = serverShell(world.Controller.Platform, STRICT)
					server.Registry:RegisterCommands(hiddenCommands())
					server.Permissions:SetGroup("Staff", Permissions.Users({ bob.UserId }))
					world.Controller:SetLocalPlayer(bob)
					const client = strictClient(world.Controller.Platform)
					Manifest.Apply(client, received(server, bob))
					allow(client, server, bob)

					const setgold = client.Registry:GetCommand("setgold")
					t.expect(setgold ~= nil and setgold.Hidden):toBe(true)
					t.expect(suggestionTexts(client, "setg")):Not():toContain("setgold")
					t.expect(suggestionTexts(client, "setr")):toContain("setround")
					t.expect(suggestionTexts(client, "help setg")):Not():toContain("setgold")
					t.expect(client.Registry:GetCommandNames(true)):Not():toContain("setgold")
					-- The palette and `help` list the commands a player can see.
					if setgold then
						t.expect(client.Permissions:CanSee(bob, setgold)):toBe(false)
					end

					const harness = Test.new({ Commands = hiddenCommands(), Defaults = true, Client = true })
					t.expect(harness.Run("commands").Output):Not():toContain("setgold")
					t.expect(harness.Run("commands").Output):toContain("setround")
					t.expect(harness.Run("help").Output):Not():toContain("setgold")
					-- Asking for it by name still explains it.
					const explained = harness.Run("help setgold")
					t.expect(explained.Ok):toBe(true)
					t.expect(explained.Output):toContain("Sets your gold")
				end
			)

			t.it(
				"stay refused for players without permission",
				function()
					const world = FakeWorld.new({}, { "Bob", "Alice" })
					const bob, alice = world.Players.Bob, world.Players.Alice
					const server = serverShell(world.Controller.Platform, STRICT)
					server.Registry:RegisterCommands(hiddenCommands())
					server.Permissions:SetGroup("Staff", Permissions.Users({ bob.UserId }))
					world.Controller:SetLocalPlayer(alice)
					const client = strictClient(world.Controller.Platform)
					const sent: { Types.RemoteRunRequest } = {}
					client._transport = recordingTransport(sent)
					Manifest.Apply(client, received(server, alice))
					allow(client, server, alice)

					t.expect(Manifest.Runnable(server, alice)):Not():toContain("setgold")
					t.expect(client.Registry:GetCommand("setgold")):toBeNil()
					t.expect(client.Dispatcher:Run({ Text = "setgold 5" }).Ok):toBe(false)
					t.expect(#sent):toBe(0)
					-- The server refuses it too, whatever a client sends.
					t.expect(server.Dispatcher:Run({ Text = "setgold 5", Executor = alice }).Ok):toBe(false)
					t.expect(server.Dispatcher:Run({ Text = "setgold 5", Executor = bob }).Ok):toBe(true)
				end
			)
		end
	)

	t.describe("The player's own value of a server type", function()
		t.it("resolves . and me to it on the client, and ** to the others", function()
			const world = FakeWorld.new({}, { "Bob", "Alice" })
			const bob = world.Players.Bob
			const server = serverShell(world.Controller.Platform)
			server.Registry:RegisterCommands(islandCommands(true))
			const infos = received(server, bob)
			const visit = find(infos, "visit")
			t.expect(visit ~= nil and visit.Args[1].Type.Self):toBe("Bob")
			t.expect(visit ~= nil and visit.Args[1].Type.HasDefault):toBe(true)

			const client = clientShell(world.Controller.Platform)
			Manifest.Apply(client, infos)
			t.expect(valueOf(client, "visit me")):toBe("Bob")
			t.expect(valueOf(client, "visit .")):toBe("Bob")
			t.expect(valueOf(client, "islandgold me 42")):toEqual({ "Bob" })
			t.expect(valueOf(client, "islandgold ** 42")):toEqual({ "Alice", "Carol" })
			t.expect(valueOf(client, "islandgold me,Carol 42")):toEqual({ "Bob", "Carol" })
		end)

		t.it("does not block the line when the server could not tell", function()
			const world = FakeWorld.new({}, { "Dave" })
			const server = serverShell(world.Controller.Platform)
			server.Registry:RegisterCommands(islandCommands(true))
			const infos = received(server, world.Players.Dave)
			const visit = find(infos, "visit")
			t.expect(visit ~= nil and visit.Args[1].Type.Self):toBeNil()

			const client = clientShell(world.Controller.Platform)
			Manifest.Apply(client, infos)
			t.expect(client.Dispatcher:Evaluate({ Text = "visit me" }).Ok):toBe(true)
			t.expect(client.Dispatcher:Evaluate({ Text = "visit ." }).Ok):toBe(true)
			t.expect(client.Dispatcher:Evaluate({ Text = "islandgold me 42" }).Ok):toBe(true)
			t.expect(valueOf(client, "islandgold ** 42")):toEqual({ "Bob", "Alice", "Carol" })
			t.expect(suggestionTexts(client, "visit ")):Not():toContain("me")
			t.expect(client.Dispatcher:Evaluate({ Text = "visit Nobody" }).Ok):toBe(false)
		end)

		t.it("leaves me meaningless when the type has no own value", function()
			const world = FakeWorld.new({}, { "Bob" })
			const server = serverShell(world.Controller.Platform)
			server.Registry:RegisterCommands(islandCommands(false))
			const client = clientShell(world.Controller.Platform)
			Manifest.Apply(client, received(server, world.Players.Bob))
			t.expect(client.Dispatcher:Evaluate({ Text = "visit me" }).Ok):toBe(false)
		end)

		t.it("names values by the type's noun in a list's errors", function()
			const world = FakeWorld.new({}, { "Bob" })
			const server = serverShell(world.Controller.Platform)
			server.Registry:RegisterCommands(islandCommands(true))
			t.expect(firstError(server, "islandgold Nobody 3")):toContain("Unknown island 'Nobody'")
			const client = clientShell(world.Controller.Platform)
			Manifest.Apply(client, received(server, world.Players.Bob))
			t.expect(firstError(client, "islandgold Nobody 3")):toContain("Unknown island 'Nobody'")
		end)
	end)
end
