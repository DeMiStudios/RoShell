--!strict
const InputText = require("../../src/Client/UI/InputText")
const Runner = require("../Runner")

const function text(cleaned: InputText.Cleaned): string
	return cleaned.Text
end

const function kindOf(cleaned: InputText.Cleaned): string
	return cleaned.Kind
end

const function cursorOf(cleaned: InputText.Cleaned): number?
	return if cleaned.Kind == "text" then cleaned.Cursor else nil
end

return function(t: Runner.Api)
	t.describe(
		"InputText.Clean",
		function()
			t.it("leaves ordinary text alone", function()
				const cleaned = InputText.Clean("give me sword", 5)
				t.expect(kindOf(cleaned)):toBe("text")
				t.expect(text(cleaned)):toBe("give me sword")
				t.expect(cursorOf(cleaned)):toBe(5)
			end)

			t.it("drops the Enter key's carriage return after a submit (the reported bug)", function()
				const cleaned = InputText.Clean("\r", 2)
				t.expect(kindOf(cleaned)):toBe("text")
				t.expect(text(cleaned)):toBe("")
				t.expect(cursorOf(cleaned)):toBe(1)
			end)

			t.it("drops a line break typed at the end of a command", function()
				for _, typed in { "kick Bob\r", "kick Bob\n", "kick Bob\r\n" } do
					const cleaned = InputText.Clean(typed, #typed + 1)
					t.expect(kindOf(cleaned)):toBe("text")
					t.expect(text(cleaned)):toBe("kick Bob")
					t.expect(cursorOf(cleaned)):toBe(9)
				end
			end)

			t.it(
				"drops Enter's break wherever it lands, keeping the caret on the same character",
				function()
					const cleaned = InputText.Clean("kick \rBob", 7, "kick Bob")
					t.expect(kindOf(cleaned)):toBe("text")
					t.expect(text(cleaned)):toBe("kick Bob")
					t.expect(cursorOf(cleaned)):toBe(6)
					-- The same text pasted over something else is two lines.
					t.expect(kindOf(InputText.Clean("kick \rBob", 7, ""))):toBe("script")
				end
			)

			t.it("removes tabs and moves the caret back", function()
				const cleaned = InputText.Clean("gi\tve", 4)
				t.expect(text(cleaned)):toBe("give")
				t.expect(cursorOf(cleaned)):toBe(3)
			end)

			t.it("treats two or more non-empty lines as a script", function()
				const cleaned = InputText.Clean("echo a\r\necho b\r\n", 1)
				t.expect(kindOf(cleaned)):toBe("script")
				t.expect(text(cleaned)):toBe("echo a\necho b\n")
				if cleaned.Kind == "script" then
					t.expect(cleaned.Lines):toBe(2)
				end
			end)

			t.it("does not count blank lines", function()
				t.expect(kindOf(InputText.Clean("\n\nheal me\n\n", 1))):toBe("text")
				t.expect(InputText.CountLines("a\n\n  \nb")):toBe(2)
			end)

			t.it("uses the end when there is no caret", function()
				const cleaned = InputText.Clean("hello\r", -1)
				t.expect(text(cleaned)):toBe("hello")
				t.expect(cursorOf(cleaned)):toBe(6)
			end)
		end
	)
end
