--!strict
--[[
	Toast notifications for background events (announcements, scheduled commands, cancellations). Stack in the
	top-right corner (top-center on touch screens), slide in, and dismiss themselves.
]]

--// Imports
const Motion = require("./Motion")
const Surface = require("./Surface")
const Theme = require("./Theme")
const Types = require("../../Shared/Types")
const Ui = require("./Ui")

--// Types
export type Toasts = {
	read Show: (text: string, level: Types.Level?, duration: number?) -> (),
	read SetTheme: (palette: Theme.Palette) -> (),
	read SetMetrics: (metrics: Ui.Metrics) -> (),
	read Destroy: () -> (),
}

type Toast = {
	Surface: Surface.Surface,
	Level: Types.Level,
	Accent: Frame,
	Icon: TextLabel,
	Text: TextLabel,
	Height: number,
	Closing: boolean,
}

--// Constants
const WIDTH = 340
const MAX_VISIBLE = 4
const DEFAULT_DURATION = 4.5
const GAP = 8

--// Toasts
const ToastsModule = {}

function ToastsModule.new(parent: Instance, initialPalette: Theme.Palette, initialMetrics: Ui.Metrics): Toasts
	local palette = initialPalette
	local metrics = initialMetrics
	const toasts: { Toast } = {}

	const container = Ui.Frame("Toasts", parent)
	container.Size = UDim2.fromScale(1, 1)
	container.ZIndex = 50

	const function levelColor(level: Types.Level): Color3
		if level == "success" then
			return palette.Success
		elseif level == "error" then
			return palette.Error
		elseif level == "warning" then
			return palette.Warning
		end
		return palette.Info
	end

	const function width(): number
		return math.floor(WIDTH * math.min(1.2, metrics.Scale))
	end

	const function arrange()
		-- The console's GUI ignores the inset; start below Roblox's top bar.
		local y = game:GetService("GuiService"):GetGuiInset().Y + 12
		for _, toast in toasts do
			const holder = toast.Surface.Holder
			const target = if metrics.Touch then UDim2.new(0.5, -width() // 2, 0, y)
				else UDim2.new(1, -width() - 16, 0, y)
			Motion.Tween(holder, 0.22, { Position = target })
			y += toast.Height + GAP
		end
	end

	const function dismiss(toast: Toast)
		if toast.Closing then
			return
		end
		toast.Closing = true
		const holder = toast.Surface.Holder
		const index = table.find(toasts, toast)
		if index then
			table.remove(toasts, index)
		end
		const tween = Motion.Tween(holder, 0.18, { Position = holder.Position + UDim2.fromOffset(width() + 32, 0) })
		tween.Completed:Once(function()
			holder:Destroy()
		end)
		arrange()
	end

	const function paint(toast: Toast)
		toast.Surface.SetTheme(palette)
		toast.Accent.BackgroundColor3 = levelColor(toast.Level)
		toast.Icon.TextColor3 = levelColor(toast.Level)
		toast.Text.TextColor3 = palette.Text
	end

	return table.freeze({
		Show = function(text: string, level: Types.Level?, duration: number?)
			const toastLevel: Types.Level = level or "info"
			const surface = Surface.new("Toast", container, Ui.Radius.L - 2, palette, true)
			const holder = surface.Holder
			const card = surface.Card
			const accent = Ui.Frame("Accent", card)
			accent.BackgroundTransparency = 0
			accent.Size = UDim2.new(0, 3, 1, -16)
			accent.Position = UDim2.fromOffset(8, 8)
			Ui.Corner(accent, 2)
			const icon = Ui.Label("Icon", card, Ui.Fonts.Bold, metrics.TextMd)
			icon.Text = Ui.Icon(toastLevel)
			icon.TextXAlignment = Enum.TextXAlignment.Center
			icon.TextYAlignment = Enum.TextYAlignment.Top
			icon.Position = UDim2.fromOffset(16, 12)
			icon.Size = UDim2.fromOffset(20, metrics.TextMd + 2)
			const label = Ui.Label("Text", card, Ui.Fonts.Sans, metrics.TextMd)
			label.TextWrapped = true
			label.TextYAlignment = Enum.TextYAlignment.Top
			label.Text = text
			const textWidth = width() - 44 - 14
			const textHeight = Ui.Measure(text, metrics.TextMd, Ui.Fonts.Sans, textWidth).Y
			label.Position = UDim2.fromOffset(44, 12)
			label.Size = UDim2.fromOffset(textWidth, textHeight)
			const height = math.max(44, textHeight + 24)
			holder.Size = UDim2.fromOffset(width(), height)
			const close = Ui.Button("Close", card)
			close.Size = UDim2.fromScale(1, 1)
			close.ZIndex = 3

			const toast: Toast = {
				Surface = surface,
				Level = toastLevel,
				Accent = accent,
				Icon = icon,
				Text = label,
				Height = height,
				Closing = false,
			}
			paint(toast)
			table.insert(toasts, 1, toast)
			-- Start off-screen to the right, then slide into the stack.
			holder.Position = if metrics.Touch then UDim2.new(0.5, -width() // 2, 0, -height - 12)
				else UDim2.new(1, 16, 0, 12)
			while #toasts > MAX_VISIBLE do
				dismiss(toasts[#toasts])
			end
			arrange()
			close.Activated:Connect(function()
				dismiss(toast)
			end)
			task.delay(duration or DEFAULT_DURATION, function()
				dismiss(toast)
			end)
		end,
		SetTheme = function(next: Theme.Palette)
			palette = next
			for _, toast in toasts do
				paint(toast)
			end
		end,
		SetMetrics = function(next: Ui.Metrics)
			metrics = next
			arrange()
		end,
		Destroy = function()
			container:Destroy()
		end,
	})
end

return table.freeze(ToastsModule)
