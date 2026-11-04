--!strict
const Command = require(script.Parent.Parent.Parent.src.Shared.Command)
const FakeWorld = require(script.Parent.Parent.support.FakeWorld)
const Permissions = require(script.Parent.Parent.Parent.src.Shared.Permissions)
const Runner = require(script.Parent.Parent.Runner)
const Test = require(script.Parent.Parent.Parent.src.Shared.Test)
const Types = require(script.Parent.Parent.Parent.src.Shared.Types)

const ping = Command.new({ Name = "ping", Group = "Staff", Args = {} }):Run(function()
	return "pong"
end)

const secret = Command.new({ Name = "secret", Permissions = Permissions.Role("Moderator"), Args = {} }):Run(function()
	return "shh"
end)

-- The harness counts as Studio, where everything is allowed by default.
const STRICT: Types.ShellOptions = { StudioBypass = false }

return function(t: Runner.Api)
	t.describe(
		"Permissions",
		function()
			t.it(
				"uses rules changed while the game runs",
				function()
					const world = FakeWorld.new({}, { "Bob", "Alice" })
					const harness = Test.new({
						Platform = world.Controller.Platform,
						Options = STRICT,
						Commands = { ping, secret },
					})
					const bob, alice = world.Players.Bob, world.Players.Alice
					const permissions = harness.Shell.Permissions
					t.expect(harness.Run("ping", { As = bob }).Ok):toBe(false)

					permissions:SetAdmins(Permissions.Users({ bob.UserId }))
					t.expect(harness.Run("ping", { As = bob }).Ok):toBe(true)
					t.expect(harness.Run("ping", { As = alice }).Ok):toBe(false)

					-- Replacing the rule takes Bob's access away and gives Alice hers.
					permissions:SetAdmins(Permissions.Users({ alice.UserId }))
					t.expect(harness.Run("ping", { As = bob }).Ok):toBe(false)
					t.expect(harness.Run("ping", { As = alice }).Ok):toBe(true)

					-- Roles can be (re)defined after the commands that use them are registered.
					t.expect(harness.Run("secret", { As = bob }).Ok):toBe(false)
					permissions:DefineRole("Moderator", Permissions.Users({ bob.UserId }))
					t.expect(harness.Run("secret", { As = bob }).Ok):toBe(true)
					permissions:DefineRole("Moderator", Permissions.Nobody())
					t.expect(harness.Run("secret", { As = bob }).Ok):toBe(false)

					permissions:SetGroup("Staff", Permissions.Users({ bob.UserId }))
					t.expect(harness.Run("ping", { As = bob }).Ok):toBe(true)
				end
			)

			t.it("reads live data through a predicate", function()
				const world = FakeWorld.new({}, { "Bob" })
				const harness = Test.new({ Platform = world.Controller.Platform, Options = STRICT, Commands = { ping } })
				const bob = world.Players.Bob
				const moderators: { [number]: true } = {}
				harness.Shell.Permissions:SetGroup(
					"Staff",
					Permissions.Predicate(
						function(player: Player?): boolean
							return player ~= nil and moderators[player.UserId] == true
						end,
						"moderators"
					)
				)
				t.expect(harness.Run("ping", { As = bob }).Ok):toBe(false)
				moderators[bob.UserId] = true
				t.expect(harness.Run("ping", { As = bob }).Ok):toBe(true)
				moderators[bob.UserId] = nil
				t.expect(harness.Run("ping", { As = bob }).Ok):toBe(false)
			end)

			t.it("signals every change", function()
				const harness = Test.new({ Commands = { ping } })
				local changes = 0
				harness.Shell.Permissions.Changed:Connect(function()
					changes += 1
				end)
				harness.Shell.Permissions:SetAdmins(Permissions.Nobody())
				harness.Shell.Permissions:DefineRole("Moderator", Permissions.Nobody())
				harness.Shell.Permissions:SetGroup("Staff", Permissions.Everyone())
				harness.Shell.Permissions:SetAdmins(nil)
				t.expect(changes):toBe(4)
			end)
		end
	)
end
