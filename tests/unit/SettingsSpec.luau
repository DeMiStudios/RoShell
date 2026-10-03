--!strict
const Runner = require("../Runner")
const Settings = require("../../src/Client/Settings")

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
			t.expect(settings:GetNumber("opacity")):toBe(0.97)
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
end
