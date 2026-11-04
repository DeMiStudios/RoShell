--!strict
--[[
	Specs that need the engine (run from Studio through tests/Studio.luau): engine-backed argument types, text
	metrics, theme palettes, permissions with a real player, engine-safe waiting inside engine callbacks, and the
	public shell from `RoShell.new` (its module reads engine services as it loads).
--]]

const BuiltInTypes = require(script.Parent.Parent.Parent.src.Shared.BuiltInTypes)
const Command = require(script.Parent.Parent.Parent.src.Shared.Command)
const FakeWorld = require(script.Parent.Parent.support.FakeWorld)
const Fixtures = require(script.Parent.Parent.support.Fixtures)
const Permissions = require(script.Parent.Parent.Parent.src.Shared.Permissions)
const Platform = require(script.Parent.Parent.Parent.src.Shared.Platform)
const Runner = require(script.Parent.Parent.Runner)
const Shell = require(script.Parent.Parent.Parent.src.Shared.Shell)
const Theme = require(script.Parent.Parent.Parent.src.Client.UI.Theme)
const TypeBuilder = require(script.Parent.Parent.Parent.src.Shared.TypeBuilder)
const Types = require(script.Parent.Parent.Parent.src.Shared.Types)

const T = BuiltInTypes.Types

const function firstPlayer(): Player?
	return game:GetService("Players"):GetPlayers()[1]
end

return function(t: Runner.Api)
	t.describe("Engine types", function()
		t.it("parses colors by name, hex and components", function()
			t.expect(Fixtures.Value(T.Color3, "#ff8800")):toBe(Color3.fromRGB(255, 136, 0))
			t.expect(Fixtures.Value(T.Color3, "255,0,0")):toBe(Color3.fromRGB(255, 0, 0))
			t.expect(typeof(Fixtures.Value(T.Color3, "red"))):toBe("Color3")
			t.expect(Fixtures.Value(T.BrickColor, "Bright red")):toBe(BrickColor.new("Bright red"))
		end)

		t.it("parses vectors", function()
			t.expect(Fixtures.Value(T.Vector3, "1,2,3")):toBe(Vector3.new(1, 2, 3))
			t.expect(Fixtures.Value(T.Vector2, "4, 5")):toBe(Vector2.new(4, 5))
		end)

		t.it("parses enums", function()
			t.expect(Fixtures.Value(T.Material, "Neon")):toBe(Enum.Material.Neon)
			t.expect(Fixtures.Value(T.KeyCode, "F2")):toBe(Enum.KeyCode.F2)
			const fromEnum = TypeBuilder.FromEnum({ Name = "part type", Enum = Enum.PartType })
			t.expect(Fixtures.Value(fromEnum, "ball")):toBe(Enum.PartType.Ball)
		end)

		t.it("resolves instance paths", function()
			t.expect(Fixtures.Value(T.Instance, "workspace")):toBe(workspace)
			t.expect(Fixtures.Value(T.Instance, "game.ReplicatedStorage")):toBe(game:GetService("ReplicatedStorage"))
		end)
	end)

	t.describe(
		"UI foundations",
		function()
			t.it("resolves every theme to a Color3 palette", function()
				for _, name in Theme.Names() do
					const palette = Theme.Get(name)
					t.expect(typeof(palette.Window)):toBe("Color3")
					t.expect(typeof(palette.Syntax.Command)):toBe("Color3")
					t.expect(typeof(Theme.TypeToken(palette.Types, "type.player"))):toBe("Color3")
				end
			end)

			t.it(
				"measures monospace text consistently",
				function()
					-- Required here: the module reads `Enum` when it loads, which the headless runner does not have.
					const Ui = require(script.Parent.Parent.Parent.src.Client.UI.Ui)
					const metrics = Ui.Metrics(1, false, false)
					t.expect(metrics.MonoWidth > 0):toBe(true)
					t.expect(metrics.LineHeight > 0):toBe(true)
					const measured = Ui.Measure("give me sword", metrics.Mono, Ui.Fonts.Mono).X
					t.expect(math.abs(Ui.MonoTextWidth("give me sword", metrics) - measured) <= 1):toBe(true)
					-- Non-ASCII text is measured, trailing spaces included.
					t.expect(Ui.MonoTextWidth("é ", metrics) > Ui.MonoTextWidth("é", metrics)):toBe(true)
				end
			)
		end
	)

	t.describe("Engine-safe waiting", function()
		t.it("returns values from engine callbacks parked on a gate", function()
			const platform = Platform.Roblox()
			const bindable = Instance.new("BindableFunction")
			bindable.OnInvoke = function(): number
				const gate = platform.Gate()
				task.delay(0.05, gate.Open)
				gate.Wait()
				return 42
			end
			t.expect(bindable:Invoke()):toBe(42)
			bindable:Destroy()
		end)

		t.it("runs yielding commands inside engine callbacks", function()
			const shell = Shell.new({ IsServer = true, IsClient = false, Platform = Platform.Roblox() })
			shell.Registry:RegisterCommand(
				Command.new({ Name = "nap", Args = {} }):Run(function()
					task.wait(0.05)
					return "rested"
				end)
			)
			const bindable = Instance.new("BindableFunction")
			bindable.OnInvoke = function(): boolean
				return shell.Dispatcher:Run({ Text = "nap" }).Ok
			end
			t.expect(bindable:Invoke()):toBe(true)
			bindable:Destroy()
			Shell.Destroy(shell)
		end)
	end)

	t.describe("Loading from containers", function()
		t.it("registers types and hooks found in folders", function()
			const testsFolder = (script :: Instance).Parent and ((script :: Instance).Parent :: Instance).Parent
			const fixtures = if testsFolder then testsFolder:FindFirstChild("fixtures") else nil
			if fixtures == nil then
				error("tests/fixtures is missing from the place", 0)
			end
			const typesFolder = fixtures:FindFirstChild("TypesFolder")
			const hooksFolder = fixtures:FindFirstChild("HooksFolder")
			if typesFolder == nil or hooksFolder == nil then
				error("fixture folders are missing", 0)
			end
			const shell = Shell.new({ IsServer = true, IsClient = false, Platform = Platform.Roblox() })
			t.expect(shell.Registry:RegisterTypesIn(typesFolder)):toBe(2)
			t.expect(shell.Registry:GetType("fixtureFlavor") ~= nil):toBe(true)
			t.expect(shell.Registry:RegisterHooksIn(hooksFolder)):toBe(1)
			shell.Registry:RegisterCommand(
				Command.new({ Name = "blocked", Args = {} }):Run(function()
					return "ran"
				end)
			)
			t.expect(shell.Dispatcher:Run({ Text = "blocked" }).Ok):toBe(false)
			Shell.Destroy(shell)
		end)
	end)

	t.describe(
		"Permissions with a player",
		function()
			t.it(
				"evaluates rules for a real player",
				function()
					const player = firstPlayer()
					if player == nil then
						return -- Needs play mode; nothing to check in edit mode.
					end
					const shell = Shell.new({
						IsServer = true,
						IsClient = false,
						Platform = Platform.Roblox(),
						Options = { StudioBypass = false },
					})
					const function CanRun(permission: Types.Permission?): boolean
						const command = Command.new({ Name = "probe", Permissions = permission, Args = {} })
						return (shell.Permissions:CanRun(player, command))
					end
					t.expect(CanRun(nil)):toBe(false)
					t.expect(CanRun(Permissions.Everyone())):toBe(true)
					t.expect(CanRun(Permissions.Nobody())):toBe(false)
					t.expect(CanRun(Permissions.Users({ player.UserId }))):toBe(true)
					t.expect(CanRun(Permissions.Users({ player.UserId + 1 }))):toBe(false)
					t.expect(CanRun(Permissions.Not(Permissions.Nobody()))):toBe(true)
					t.expect(CanRun(Permissions.All({ Permissions.Everyone(), Permissions.Nobody() }))):toBe(false)
					t.expect(CanRun(Permissions.Any({ Permissions.Nobody(), Permissions.Everyone() }))):toBe(true)
					t.expect(CanRun(Permissions.Studio())):toBe(true)
					-- Admins run every command, whatever its own rule.
					shell.Permissions:SetAdmins(Permissions.Users({ player.UserId }))
					t.expect(CanRun(nil)):toBe(true)
					t.expect(CanRun(Permissions.Nobody())):toBe(true)
					shell.Permissions:SetAdmins(Permissions.Users({ player.UserId + 1 }))
					t.expect(CanRun(nil)):toBe(false)
					shell.Permissions:SetAdmins(nil)
					Shell.Destroy(shell)
				end
			)
		end
	)

	t.describe(
		"Public shell",
		function()
			-- Required here: the module reads engine services as it loads, and this spec file also loads headless.
			const RoShell = require(script.Parent.Parent.Parent.src)

			t.it(
				"opens the palette and fills the line on clients only",
				function()
					const server = RoShell.new({ Name = "RoShellSpecServer", Platform = Platform.Headless().Platform })
					-- Calling a client method on the server errors in Studio (and warns in live games).
					const paletteOk, paletteError = pcall(function()
						server:OpenPalette()
					end)
					t.expect(paletteOk):toBe(false)
					t.expect(tostring(paletteError)):toContain("OpenPalette is client-only")
					const inputOk, inputError = pcall(function()
						server:SetInput("help ")
					end)
					t.expect(inputOk):toBe(false)
					t.expect(tostring(inputError)):toContain("SetInput is client-only")
					Shell.Destroy(server.Shell)
				end
			)

			t.it(
				"accepts both calls on a client before its console exists",
				function()
					const world = FakeWorld.new({}, { "Bob" })
					world.Controller:SetLocalPlayer(world.Players.Bob)
					const client = RoShell.new({
						Name = "RoShellSpecClient",
						Interface = false,
						Platform = world.Controller.Platform,
					})
					t.expect(client.IsClient):toBe(true)
					const callsOk = pcall(function()
						client:OpenPalette()
						client:SetInput("help ")
					end)
					t.expect(callsOk):toBe(true)
					-- The line must be text.
					const nilOk = pcall(function()
						client:SetInput((nil :: unknown) :: string)
					end)
					t.expect(nilOk):toBe(false)
					Shell.Destroy(client.Shell)
				end
			)
		end
	)
end
