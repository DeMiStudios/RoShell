--!strict
--[[
	Toast notifications for background events (announcements, scheduled commands, cancellations): small glass cards
	stacked in the top-right corner (top-center on touch screens, below the command bar when it is open there) that
	slide in and dismiss themselves. Tap one to dismiss it early.
--]]

--// Services
const GuiService = game:GetService("GuiService")

--// Imports
const Icons = require(script.Parent.Icons)
const Motion = require(script.Parent.Motion)
const Surface = require(script.Parent.Surface)
const Theme = require(script.Parent.Theme)
const Types = require(script.Parent.Parent.Parent.Shared.Types)
const Ui = require(script.Parent.Ui)

--// Types
export type Toasts = {
	read Show: (text: string, level: Types.Level?, duration: number?) -> (),
	--- Where the stack starts (root coordinates); nil for just below Roblox's top bar.
	read SetTop: (y: number?) -> (),
	read SetOpacity: (opacity: number) -> (),
	read SetTheme: (palette: Theme.Palette) -> (),
	read SetMetrics: (metrics: Ui.Metrics) -> (),
	read Destroy: () -> (),
}

type Toast = {
	Surface: Surface.Surface,
	Level: Types.Level,
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
const Toasts = {}

function Toasts.new(parent: Instance, initialPalette: Theme.Palette, initialMetrics: Ui.Metrics): Toasts
	local palette = initialPalette
	local metrics = initialMetrics
	local top: number? = nil
	local opacity = 0.95
	const toasts: { Toast } = {}

	const container = Ui.Frame("Toasts", parent)
	container.Size = UDim2.fromScale(1, 1)
	container.ZIndex = 50

	const function LevelColor(level: Types.Level): Color3
		if level == "success" then
			return palette.Success
		elseif level == "error" then
			return palette.Error
		elseif level == "warning" then
			return palette.Warning
		end
		return palette.Info
	end

	const function Width(): number
		return math.floor(WIDTH * math.min(1.2, metrics.Scale))
	end

	const function Arrange()
		-- The console's GUI ignores the inset; start below Roblox's top bar (or the command bar).
		local y = top or (GuiService:GetGuiInset().Y + 12)
		for _, toast in toasts do
			const holder = toast.Surface.Holder
			const target = if metrics.Touch then UDim2.new(0.5, -Width() // 2, 0, y)
				else UDim2.new(1, -Width() - 16, 0, y)
			Motion.Tween(holder, 0.22, { Position = target })
			y += toast.Height + GAP
		end
	end

	const function Dismiss(toast: Toast)
		if toast.Closing then
			return
		end
		toast.Closing = true
		const holder = toast.Surface.Holder
		const index = table.find(toasts, toast)
		if index then
			table.remove(toasts, index)
		end
		const offset = if metrics.Touch then UDim2.fromOffset(0, -(toast.Height + 24))
			else UDim2.fromOffset(Width() + 32, 0)
		const tween = Motion.Tween(holder, 0.18, { Position = holder.Position + offset })
		tween.Completed:Once(function()
			holder:Destroy()
		end)
		Arrange()
	end

	const function Paint(toast: Toast)
		toast.Surface.SetTheme(palette)
		toast.Surface.SetOpacity(opacity)
		toast.Icon.TextColor3 = LevelColor(toast.Level)
		toast.Text.TextColor3 = palette.Text
	end

	return table.freeze({
		Show = function(text: string, level: Types.Level?, duration: number?)
			const toastLevel: Types.Level = level or "info"
			const surface = Surface.new("Toast", container, Ui.Radius.L + 2, palette, { Elevated = true })
			const holder = surface.Holder
			const card = surface.Card
			const icon = Ui.Label("Icon", card, Ui.Fonts.Bold, metrics.IconSize)
			Icons.Apply(icon, toastLevel)
			icon.TextXAlignment = Enum.TextXAlignment.Center
			icon.TextYAlignment = Enum.TextYAlignment.Top
			icon.Position = UDim2.fromOffset(12, 12)
			icon.Size = UDim2.fromOffset(22, metrics.IconSize + 2)
			const label = Ui.Label("Text", card, Ui.Fonts.Medium, metrics.TextMd)
			label.TextWrapped = true
			label.TextYAlignment = Enum.TextYAlignment.Top
			label.Text = text
			const textWidth = Width() - 44 - 14
			const textHeight = Ui.Measure(text, metrics.TextMd, Ui.Fonts.Medium, textWidth).Y
			label.Position = UDim2.fromOffset(42, 13)
			label.Size = UDim2.fromOffset(textWidth, textHeight)
			const height = math.max(44, textHeight + 26)
			holder.Size = UDim2.fromOffset(Width(), height)
			const close = Ui.Button("Close", card)
			close.Size = UDim2.fromScale(1, 1)
			close.ZIndex = 3

			const toast: Toast = {
				Surface = surface,
				Level = toastLevel,
				Icon = icon,
				Text = label,
				Height = height,
				Closing = false,
			}
			Paint(toast)
			table.insert(toasts, 1, toast)
			-- Start off-screen, then slide into the stack.
			holder.Position = if metrics.Touch then UDim2.new(0.5, -Width() // 2, 0, -height - 12)
				else UDim2.new(1, 16, 0, top or 12)
			while #toasts > MAX_VISIBLE do
				Dismiss(toasts[#toasts])
			end
			Arrange()
			close.Activated:Connect(function()
				Dismiss(toast)
			end)
			task.delay(duration or DEFAULT_DURATION, function()
				Dismiss(toast)
			end)
		end,
		SetTop = function(y: number?)
			if y ~= top then
				top = y
				Arrange()
			end
		end,
		SetOpacity = function(value: number)
			opacity = value
			for _, toast in toasts do
				Paint(toast)
			end
		end,
		SetTheme = function(next: Theme.Palette)
			palette = next
			for _, toast in toasts do
				Paint(toast)
			end
		end,
		SetMetrics = function(next: Ui.Metrics)
			metrics = next
			Arrange()
		end,
		Destroy = function()
			container:Destroy()
		end,
	})
end

return table.freeze(Toasts)
