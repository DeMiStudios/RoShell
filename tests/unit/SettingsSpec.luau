--!strict
const Completion = require("../../src/Shared/Completion")
const FakeConsole = require("../support/FakeConsole")
const Keys = require("../../src/Shared/Keys")
const Runner = require("../Runner")
const Settings = require("../../src/Client/Settings")
const Test = require("../../src/Shared/Test")

const function consoleHarness(): (Test.Harness, FakeConsole.FakeConsole)
	const fake = FakeConsole.new()
	const harness = Test.new({ Defaults = true, Client = true })
	harness.Shell.Registry:AddEnv(Keys.Console, fake.Api)
	return harness, fake
end

const function labels(harness: Test.Harness, text: string): { string }
	const result = Completion.Query({ Shell = harness.Shell, Text = text, Cursor = #text + 1, Limit = 20 })
	const list: { string } = {}
	for _, suggestion in result.Suggestions do
		table.insert(list, suggestion.Display)
	end
	return list
end

return function(t: Runner.Api)
	t.describe("Settings", function()
		t.it("docks the console to the top by default", function()
			t.expect(Settings.new(nil, nil):GetString("dock")):toBe("top")
		end)

		t.it("applies developer overrides as defaults, ignoring unknown keys and wrong types", function()
			const settings = Settings.new(nil, { theme = "Graphite", textScale = "big", nope = true })
			t.expect(settings:GetString("theme")):toBe("Graphite")
			t.expect(settings:GetNumber("textScale")):toBe(1)
		end)

		t.it("persists only values that differ from the defaults", function()
			const settings = Settings.new(nil, { theme = "Graphite" })
			t.expect((next(settings:Serialize()))):toBeNil()
			settings:Set("dock", "bottom")
			settings:Set("theme", "Midnight")
			const saved = settings:Serialize()
			t.expect(saved.dock):toBe("bottom")
			t.expect(saved.theme):toBe("Midnight")
			settings:Set("dock", "top")
			t.expect(settings:Serialize().dock):toBeNil()
		end)

		t.it("loads saved values over the defaults, ignoring invalid ones", function()
			const settings = Settings.new({ dock = "float", opacity = "x", unknown = 1 }, nil)
			t.expect(settings:GetString("dock")):toBe("float")
			t.expect(settings:GetNumber("opacity")):toBe(0.95)
		end)

		t.it("validates text through each setting's type", function()
			const settings = Settings.new(nil, nil)
			t.expect((settings:SetText("dock", "bottom"))):toBe(true)
			t.expect(settings:GetString("dock")):toBe("bottom")
			const ok, message = settings:SetText("textScale", "9")
			t.expect(ok):toBe(false)
			t.expect(message ~= nil):toBe(true)
			t.expect((settings:SetText("missing", "1"))):toBe(false)
		end)

		t.it("lists visible settings only", function()
			for _, entry in Settings.new(nil, nil):List() do
				t.expect(entry.Key ~= "layout"):toBe(true)
			end
		end)

		t.it("fires Changed only for real changes", function()
			const settings = Settings.new(nil, nil)
			local fired = 0
			settings.Changed:Connect(function()
				fired += 1
			end)
			settings:Set("dock", "top")
			settings:Set("dock", "bottom")
			t.expect(fired):toBe(1)
		end)
	end)

	t.describe("config command", function()
		t.it("changes a setting through its type", function()
			const harness, fake = consoleHarness()
			t.expect(harness.Run("config dock bottom").Output):toBe("dock = bottom")
			t.expect(fake.Settings:GetString("dock")):toBe("bottom")
			t.expect(harness.Run("config reduceMotion true").Ok):toBe(true)
			t.expect(fake.Settings:GetBoolean("reduceMotion")):toBe(true)
		end)

		t.it("rejects values the setting's type does not accept", function()
			const harness, fake = consoleHarness()
			t.expect(harness.Run("config textScale 9").Ok):toBe(false)
			t.expect(harness.Run("config dock sideways").Ok):toBe(false)
			t.expect(fake.Settings:GetString("dock")):toBe("top")
		end)

		t.it("completes keys, then values typed by the setting", function()
			const harness = consoleHarness()
			t.expect(table.find(labels(harness, "config do"), "dock") ~= nil):toBe(true)
			const docks = labels(harness, "config dock ")
			for _, value in { "top", "bottom", "float" } do
				t.expect(table.find(docks, value) ~= nil):toBe(true)
			end
			const toggles = labels(harness, "config reduceMotion ")
			t.expect(table.find(toggles, "true") ~= nil):toBe(true)
		end)
	end)
end
