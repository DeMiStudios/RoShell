--!strict
const Runner = require("../Runner")
const Theme = require("../../src/Client/UI/Theme")

const function describeIssues(issues: { Theme.ContrastIssue }): string
	const lines: { string } = {}
	for _, issue in issues do
		table.insert(lines, `{issue.Theme}: {issue.Token} on {issue.Surface} = {string.format("%.2f", issue.Ratio)}`)
	end
	return table.concat(lines, "\n")
end

return function(t: Runner.Api)
	t.describe("Contrast", function()
		t.it("computes WCAG ratios", function()
			t.expect(math.floor(Theme.Contrast("#FFFFFF", "#000000") * 10 + 0.5) / 10):toBe(21)
			t.expect(Theme.Contrast("#777777", "#777777")):toBe(1)
		end)

		t.it("mixes colors", function()
			t.expect(Theme.Mix("#000000", "#FFFFFF", 0.5)):toBe("#808080")
		end)
	end)

	t.describe("Presets", function()
		t.it("ships the required presets", function()
			for _, name in { "Midnight", "Graphite", "Light", "HighContrast", "Solarized", "Mocha" } do
				t.expect(Theme.Has(name)):toBe(true)
			end
			t.expect(Theme.Find("highcontrast")):toBe("HighContrast")
		end)

		t.it("keeps every text token at 4.5:1 or better", function()
			const issues: { Theme.ContrastIssue } = {}
			for _, name in Theme.Names() do
				for _, issue in Theme.Audit(Theme.Definition(name)) do
					table.insert(issues, issue)
				end
			end
			if #issues > 0 then
				error("contrast failures:\n" .. describeIssues(issues), 0)
			end
		end)
	end)

	t.describe("Create", function()
		t.it("derives from a base and validates hex values", function()
			const created = Theme.Create({ Name = "SpecOcean", Base = "Graphite", Overrides = { Accent = "#3dd6d0" } })
			t.expect(created.Accent):toBe("#3DD6D0")
			t.expect(created.Window):toBe(Theme.Definition("Graphite").Window)
			t.expect(Theme.Has("SpecOcean")):toBe(true)
			t.expectThrows(
				function()
					Theme.Create({ Name = "Broken", Overrides = { Text = "red" } })
				end,
				"#RRGGBB"
			)
		end)

		t.it("maps type tokens", function()
			const midnight = Theme.Definition("Midnight")
			t.expect(Theme.TypeToken(midnight.Types, "type.player")):toBe(midnight.Types.Player)
			t.expect(Theme.TypeToken(midnight.Types, "unknown")):toBe(midnight.Types.Default)
			t.expect(Theme.TypeToken(midnight.Types, nil)):toBe(midnight.Types.Default)
		end)
	end)
end
