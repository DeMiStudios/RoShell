--!strict
--[[
	The signature hint above the input: `give  <targets: players>  <item: item>  [amount: number = 1]` with the
	active argument highlighted, plus the active argument's description, or the first error at the caret.
]]

--// Imports
const Completion = require("../../Shared/Completion")
const Theme = require("./Theme")
const Types = require("../../Shared/Types")
const Ui = require("./Ui")

--// Types
export type SignatureBar = {
	read Frame: Frame,
	read Set: (signature: Completion.SignatureHint?, diagnostic: Types.Diagnostic?, hint: string?) -> (),
	read SetTheme: (palette: Theme.Palette) -> (),
	read SetMetrics: (metrics: Ui.Metrics) -> (),
	read Destroy: () -> (),
}

--// SignatureBar
const SignatureBarModule = {}

function SignatureBarModule.new(parent: Instance, initialPalette: Theme.Palette, initialMetrics: Ui.Metrics): SignatureBar
	local palette = initialPalette
	local metrics = initialMetrics
	local lastSignature: Completion.SignatureHint? = nil
	local lastDiagnostic: Types.Diagnostic? = nil
	local lastHint: string? = nil

	const frame = Ui.Frame("Signature", parent)
	const signature = Ui.Label("Parts", frame, Ui.Fonts.Mono, metrics.TextSm)
	signature.RichText = true
	signature.TextTruncate = Enum.TextTruncate.AtEnd
	const detail = Ui.Label("Detail", frame, Ui.Fonts.Sans, metrics.TextSm)
	detail.RichText = true
	detail.TextXAlignment = Enum.TextXAlignment.Right
	detail.TextTruncate = Enum.TextTruncate.AtEnd
	detail.AnchorPoint = Vector2.new(1, 0)

	const function render()
		const signatureHint = lastSignature
		const diagnostic = lastDiagnostic
		const muted = Ui.Hex(palette.TextMuted)
		if signatureHint then
			const parts: { string } = {}
			for _, part in signatureHint.Parts do
				local text = Ui.Escape(part.Text)
				if part.Kind == "command" then
					text = `<font color="{Ui.Hex(palette.Syntax.Command)}">{text}</font>`
				elseif part.Active then
					text = `<font color="{Ui.Hex(palette.Accent)}"><b>{text}</b></font>`
				else
					text = `<font color="{muted}">{text}</font>`
				end
				table.insert(parts, text)
			end
			signature.Text = table.concat(parts, "  ")
		else
			signature.Text = `<font color="{muted}">{Ui.Escape(lastHint or "")}</font>`
		end

		if diagnostic and diagnostic.Severity == "error" then
			detail.Text = `<font color="{Ui.Hex(palette.Error)}">✕ {Ui.Escape(diagnostic.Message)}</font>`
		elseif diagnostic and diagnostic.Severity == "warning" then
			detail.Text = `<font color="{Ui.Hex(palette.Warning)}">▲ {Ui.Escape(diagnostic.Message)}</font>`
		elseif signatureHint then
			const description = signatureHint.ActiveDescription or signatureHint.Description
			const typeName = signatureHint.ActiveType
			local text = `<font color="{Ui.Hex(palette.TextSecondary)}">{Ui.Escape(description)}</font>`
			if typeName then
				text ..= `  <font color="{muted}">· {Ui.Escape(typeName)}</font>`
			end
			detail.Text = text
		else
			detail.Text = ""
		end
	end

	const function layout()
		frame.Size = UDim2.new(1, 0, 0, metrics.SignatureHeight)
		signature.TextSize = metrics.TextSm
		detail.TextSize = metrics.TextSm
		signature.Position = UDim2.fromOffset(metrics.Pad - 2, 0)
		signature.Size = UDim2.new(0.6, -metrics.Pad, 1, 0)
		detail.Position = UDim2.new(1, -(metrics.Pad - 2), 0, 0)
		detail.Size = UDim2.new(0.4, -metrics.Pad, 1, 0)
	end

	layout()
	render()

	return table.freeze({
		Frame = frame,
		Set = function(signatureHint: Completion.SignatureHint?, diagnostic: Types.Diagnostic?, hint: string?)
			lastSignature = signatureHint
			lastDiagnostic = diagnostic
			lastHint = hint
			render()
		end,
		SetTheme = function(next: Theme.Palette)
			palette = next
			render()
		end,
		SetMetrics = function(next: Ui.Metrics)
			metrics = next
			layout()
		end,
		Destroy = function()
			frame:Destroy()
		end,
	})
end

return table.freeze(SignatureBarModule)
