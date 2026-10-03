--!strict
--[[
	The console window: a rounded, shadowed card with a draggable title bar, a resize grip, three placements
	(floating, docked to the top, docked to the bottom) and the open/close transition (slide + scale + fade).
	Dragging a docked window undocks it. The rect is reported through `RectChanged` so it can be persisted.
]]

--// Imports
const Motion = require("./Motion")
const Signal = require("../../Shared/Signal")
const Surface = require("./Surface")
const Theme = require("./Theme")
const Types = require("../../Shared/Types")
const Ui = require("./Ui")

--// Types
export type Dock = "float" | "top" | "bottom"

--- Window placement in pixels (float: full rect; docks use only the height).
export type Rect = { X: number, Y: number, Width: number, Height: number }

export type Window = {
	read Holder: Frame,
	read Card: GuiObject,
	read Content: Frame,
	read Open: () -> (),
	read Close: (onClosed: (() -> ())?) -> (),
	read IsOpen: () -> boolean,
	read SetTitle: (title: string) -> (),
	read SetStatus: (text: string, level: Types.Level) -> (),
	read SetDock: (dock: Dock) -> (),
	read GetDock: () -> Dock,
	read SetRect: (rect: Rect?) -> (),
	read GetRect: () -> Rect,
	read SetOpacity: (opacity: number) -> (),
	--- Screen bounds of the window (for click-away detection and popup clamping).
	read Bounds: () -> Rect,
	read SetTheme: (palette: Theme.Palette) -> (),
	read SetMetrics: (metrics: Ui.Metrics) -> (),
	read PaletteRequested: Types.Signal<()>,
	read SettingsRequested: Types.Signal<()>,
	read ExportRequested: Types.Signal<()>,
	read CloseRequested: Types.Signal<()>,
	--- Fired after the player moves/resizes the window or changes its dock by dragging.
	read RectChanged: Types.Signal<()>,
	read Destroy: () -> (),
}

type IconButton = { Button: TextButton, Tooltip: string }

--// Constants
const MIN_WIDTH = 360
const MIN_HEIGHT = 220
const DEFAULT_WIDTH = 780
const DEFAULT_HEIGHT = 470
const DOCK_MARGIN = 8
const DRAG_THRESHOLD = 6

--// Window
const WindowModule = {}

function WindowModule.new(parent: GuiObject, initialPalette: Theme.Palette, initialMetrics: Ui.Metrics): Window
	local palette = initialPalette
	local metrics = initialMetrics
	local dock: Dock = "float"
	local floatRect: Rect? = nil
	local dockHeight: number? = nil
	local open = false
	local opacity = 0.97
	local generation = 0
	local statusLevel: Types.Level = "muted"
	const connections: { RBXScriptConnection } = {}
	const paletteRequested: Types.Signal<()> = Signal.new()
	const settingsRequested: Types.Signal<()> = Signal.new()
	const exportRequested: Types.Signal<()> = Signal.new()
	const closeRequested: Types.Signal<()> = Signal.new()
	const rectChanged: Types.Signal<()> = Signal.new()

	const surface = Surface.new("Window", parent, Ui.Radius.Window, palette, false, true)
	surface.SetElevation(3)
	const holder = surface.Holder
	holder.Visible = false
	holder.ZIndex = 10
	const card = surface.Card
	const group = surface.Group
	const scale = Instance.new("UIScale")
	scale.Parent = holder

	const sheen = Ui.Frame("Sheen", card)
	sheen.BackgroundTransparency = 0
	sheen.BackgroundColor3 = Color3.new(1, 1, 1)
	sheen.Size = UDim2.fromScale(1, 1)
	sheen.ZIndex = 0
	const sheenGradient = Instance.new("UIGradient")
	sheenGradient.Rotation = 90
	sheenGradient.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.955),
		NumberSequenceKeypoint.new(0.3, 1),
		NumberSequenceKeypoint.new(1, 1),
	})
	sheenGradient.Parent = sheen

	-- Title bar ------------------------------------------------------------------------------------------
	const titleBar = Ui.Button("TitleBar", card)
	titleBar.ZIndex = 2
	const brandDot = Ui.Frame("Dot", titleBar)
	brandDot.BackgroundTransparency = 0
	brandDot.AnchorPoint = Vector2.new(0, 0.5)
	Ui.Corner(brandDot, 999)
	const title = Ui.Label("Title", titleBar, Ui.Fonts.Medium, metrics.TextSm)
	title.RichText = true
	title.TextTruncate = Enum.TextTruncate.AtEnd
	const status = Ui.Label("Status", titleBar, Ui.Fonts.Medium, metrics.TextXs)
	status.TextXAlignment = Enum.TextXAlignment.Center
	status.BackgroundTransparency = 0
	status.AnchorPoint = Vector2.new(0, 0.5)
	Ui.Corner(status, 999)
	const divider = Ui.Frame("Divider", card)
	divider.BackgroundTransparency = 0

	const buttons: { IconButton } = {}
	const function iconButton(glyph: string, tooltip: string, signal: Types.Signal<()>): IconButton
		const button = Ui.Button(tooltip, titleBar)
		button.Text = glyph
		button.Font = Ui.Fonts.Bold
		button.AnchorPoint = Vector2.new(1, 0.5)
		button.ZIndex = 3
		Ui.Corner(button, Ui.Radius.M - 2)
		const entry: IconButton = { Button = button, Tooltip = tooltip }
		Ui.Hover(button, function(hovered: boolean)
			Motion.Tween(button, 0.12, {
				BackgroundTransparency = if hovered then 0 else 1,
				TextColor3 = if hovered then palette.Text else palette.TextMuted,
			})
		end)
		button.Activated:Connect(function()
			signal:Fire()
		end)
		table.insert(buttons, entry)
		return entry
	end
	-- Right to left.
	iconButton("✕", "Close", closeRequested)
	iconButton("⎘", "Export log", exportRequested)
	iconButton("⚙", "Settings", settingsRequested)
	iconButton("⌕", "Command palette", paletteRequested)

	const content = Ui.Frame("Content", card)
	content.ZIndex = 1

	const grip = Ui.Button("Resize", card)
	grip.Text = "◢"
	grip.Font = Ui.Fonts.Sans
	grip.AnchorPoint = Vector2.new(1, 1)
	grip.ZIndex = 5

	-- Geometry ---------------------------------------------------------------------------------------------
	const function screenSize(): Vector2
		return parent.AbsoluteSize
	end

	const function defaultFloat(): Rect
		const screen = screenSize()
		const width = math.min(math.floor(DEFAULT_WIDTH * math.min(1.25, metrics.Scale)), screen.X - 32)
		const height = math.min(math.floor(DEFAULT_HEIGHT * math.min(1.25, metrics.Scale)), math.floor(screen.Y * 0.62))
		return { X = (screen.X - width) // 2, Y = math.floor(screen.Y * 0.1), Width = width, Height = height }
	end

	const function clampRect(rect: Rect): Rect
		const screen = screenSize()
		const width = math.clamp(rect.Width, math.min(MIN_WIDTH, screen.X), screen.X)
		const height = math.clamp(rect.Height, math.min(MIN_HEIGHT, screen.Y), screen.Y)
		return {
			X = math.clamp(rect.X, 0, math.max(0, screen.X - width)),
			Y = math.clamp(rect.Y, 0, math.max(0, screen.Y - height)),
			Width = width,
			Height = height,
		}
	end

	const function currentRect(): Rect
		const screen = screenSize()
		if dock == "float" then
			return clampRect(floatRect or defaultFloat())
		end
		const height = math.clamp(dockHeight or math.floor(screen.Y * 0.4), MIN_HEIGHT, math.floor(screen.Y * 0.85))
		const width = screen.X - DOCK_MARGIN * 2
		return {
			X = DOCK_MARGIN,
			Y = if dock == "top" then DOCK_MARGIN else screen.Y - height - DOCK_MARGIN,
			Width = width,
			Height = height,
		}
	end

	const function applyRect()
		const rect = currentRect()
		holder.Position = UDim2.fromOffset(rect.X, rect.Y)
		holder.Size = UDim2.fromOffset(rect.Width, rect.Height)
	end

	const function layout()
		const height = metrics.TitleHeight
		titleBar.Size = UDim2.new(1, 0, 0, height)
		brandDot.Size = UDim2.fromOffset(8, 8)
		brandDot.Position = UDim2.new(0, metrics.Pad + 2, 0.5, 0)
		title.TextSize = metrics.TextSm
		title.Position = UDim2.fromOffset(metrics.Pad + 18, 0)
		const titleWidth = math.min(Ui.Measure(title.ContentText, metrics.TextSm, Ui.Fonts.Medium).X + 4, 360)
		title.Size = UDim2.new(0, titleWidth, 1, 0)
		status.TextSize = metrics.TextXs
		const statusWidth = Ui.Measure(status.Text, metrics.TextXs, Ui.Fonts.Medium).X + 16
		status.Size = UDim2.fromOffset(statusWidth, metrics.TextXs + 8)
		status.Position = UDim2.new(0, metrics.Pad + 18 + titleWidth + 8, 0.5, 0)
		const buttonSize = height - 10
		for index, entry in buttons do
			entry.Button.TextSize = metrics.TextSm
			entry.Button.Size = UDim2.fromOffset(buttonSize, buttonSize)
			entry.Button.Position = UDim2.new(1, -(metrics.Pad - 4) - (index - 1) * (buttonSize + 2), 0.5, 0)
		end
		divider.Position = UDim2.fromOffset(0, height)
		divider.Size = UDim2.new(1, 0, 0, 1)
		content.Position = UDim2.fromOffset(0, height + 1)
		content.Size = UDim2.new(1, 0, 1, -(height + 1))
		grip.TextSize = metrics.TextXs
		grip.Size = UDim2.fromOffset(16, 16)
		grip.Position = UDim2.new(1, -2, 1, -1)
		grip.Visible = dock == "float" and not metrics.Touch
	end

	const function statusColor(): Color3
		if statusLevel == "success" then
			return palette.Success
		elseif statusLevel == "warning" then
			return palette.Warning
		elseif statusLevel == "error" then
			return palette.Error
		elseif statusLevel == "info" then
			return palette.Info
		end
		return palette.TextMuted
	end

	const function applyTheme()
		surface.SetTheme(palette)
		card.BackgroundTransparency = 1 - opacity
		sheen.Visible = palette.Dark
		brandDot.BackgroundColor3 = palette.Accent
		title.TextColor3 = palette.Text
		status.TextColor3 = statusColor()
		status.BackgroundColor3 = palette.Hover
		divider.BackgroundColor3 = palette.Border
		grip.TextColor3 = palette.TextMuted
		for _, entry in buttons do
			entry.Button.BackgroundColor3 = palette.Hover
			entry.Button.BackgroundTransparency = 1
			entry.Button.TextColor3 = palette.TextMuted
		end
	end

	-- Dragging and resizing --------------------------------------------------------------------------------
	const UserInputService = game:GetService("UserInputService")
	local dragInput: InputObject? = nil
	local dragMode: "move" | "resize" | nil = nil
	local dragStart = Vector2.zero
	local dragRect: Rect = { X = 0, Y = 0, Width = 0, Height = 0 }
	local dragMoved = false

	const function beginDrag(input: InputObject, mode: "move" | "resize")
		if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end
		dragInput = input
		dragMode = mode
		dragStart = Vector2.new(input.Position.X, input.Position.Y)
		dragRect = currentRect()
		dragMoved = false
	end

	table.insert(
		connections,
		titleBar.InputBegan:Connect(function(input: InputObject)
			beginDrag(input, "move")
		end)
	)
	table.insert(
		connections,
		grip.InputBegan:Connect(function(input: InputObject)
			beginDrag(input, "resize")
		end)
	)
	table.insert(
		connections,
		UserInputService.InputChanged:Connect(
			function(input: InputObject)
				if dragMode == nil then
					return
				end
				const moving = input.UserInputType == Enum.UserInputType.MouseMovement
					or (input.UserInputType == Enum.UserInputType.Touch and input == dragInput)
				if not moving then
					return
				end
				const delta = Vector2.new(input.Position.X, input.Position.Y) - dragStart
				if not dragMoved and delta.Magnitude < DRAG_THRESHOLD then
					return
				end
				dragMoved = true
				if dragMode == "move" then
					if dock ~= "float" then
						-- Tear the window off its dock, keeping it under the pointer.
						const fresh = defaultFloat()
						dock = "float"
						dragRect = {
							X = dragStart.X - fresh.Width / 2,
							Y = dragRect.Y,
							Width = fresh.Width,
							Height = fresh.Height,
						}
						layout()
					end
					floatRect = clampRect({
						X = dragRect.X + delta.X,
						Y = dragRect.Y + delta.Y,
						Width = dragRect.Width,
						Height = dragRect.Height,
					})
				else
					floatRect = clampRect({
						X = dragRect.X,
						Y = dragRect.Y,
						Width = dragRect.Width + delta.X,
						Height = dragRect.Height + delta.Y,
					})
				end
				applyRect()
			end
		)
	)
	table.insert(
		connections,
		UserInputService.InputEnded:Connect(function(input: InputObject)
			if dragMode == nil then
				return
			end
			if input == dragInput or input.UserInputType == Enum.UserInputType.MouseButton1 then
				dragMode = nil
				dragInput = nil
				if dragMoved then
					rectChanged:Fire()
				end
			end
		end)
	)
	table.insert(connections, parent:GetPropertyChangedSignal("AbsoluteSize"):Connect(applyRect))

	-- Transitions --------------------------------------------------------------------------------------------
	const function hiddenOffset(): UDim2
		const rect = currentRect()
		if dock == "top" then
			return UDim2.fromOffset(rect.X, -rect.Height - 24)
		elseif dock == "bottom" then
			return UDim2.fromOffset(rect.X, screenSize().Y + 24)
		end
		return UDim2.fromOffset(rect.X, rect.Y + 14)
	end

	const fadeSpring = Motion.Spring(0, 5, 1, function(alpha: number)
		surface.SetFade(alpha)
		if group then
			group.GroupTransparency = 1 - alpha
		end
	end)

	const window: Window = {
		Holder = holder,
		Card = card,
		Content = content,
		Open = function()
			if open then
				return
			end
			open = true
			generation += 1
			applyRect()
			const rect = currentRect()
			holder.Visible = true
			holder.Position = hiddenOffset()
			scale.Scale = if dock == "float" and not Motion.Reduced() then 0.97 else 1
			Motion.Tween(holder, 0.2, { Position = UDim2.fromOffset(rect.X, rect.Y) })
			Motion.Tween(scale, 0.2, { Scale = 1 })
			fadeSpring.SetTarget(1)
		end,
		Close = function(onClosed: (() -> ())?)
			if not open then
				return
			end
			open = false
			generation += 1
			const closing = generation
			const tween = Motion.Tween(
				holder,
				0.16,
				{ Position = hiddenOffset() },
				Enum.EasingStyle.Quad,
				Enum.EasingDirection.In
			)
			Motion.Tween(
				scale,
				0.16,
				{ Scale = if dock == "float" then 0.97 else 1 },
				Enum.EasingStyle.Quad,
				Enum.EasingDirection.In
			)
			fadeSpring.SetTarget(0)
			tween.Completed:Once(function()
				if generation == closing then
					holder.Visible = false
					fadeSpring.Snap(0)
					if onClosed then
						onClosed()
					end
				end
			end)
		end,
		IsOpen = function(): boolean
			return open
		end,
		SetTitle = function(text: string)
			title.Text = text
			layout()
		end,
		SetStatus = function(text: string, level: Types.Level)
			status.Text = text
			statusLevel = level
			status.TextColor3 = statusColor()
			status.Visible = text ~= ""
			layout()
		end,
		SetDock = function(next: Dock)
			dock = next
			layout()
			if open then
				applyRect()
			end
		end,
		GetDock = function(): Dock
			return dock
		end,
		SetRect = function(rect: Rect?)
			if dock == "float" then
				floatRect = rect
			else
				dockHeight = if rect then rect.Height else nil
			end
			if open then
				applyRect()
			end
		end,
		GetRect = currentRect,
		SetOpacity = function(value: number)
			opacity = value
			card.BackgroundTransparency = 1 - value
		end,
		Bounds = function(): Rect
			const position = holder.AbsolutePosition
			const size = holder.AbsoluteSize
			return { X = position.X, Y = position.Y, Width = size.X, Height = size.Y }
		end,
		SetTheme = function(next: Theme.Palette)
			palette = next
			applyTheme()
		end,
		SetMetrics = function(next: Ui.Metrics)
			metrics = next
			layout()
			if open then
				applyRect()
			end
		end,
		PaletteRequested = paletteRequested,
		SettingsRequested = settingsRequested,
		ExportRequested = exportRequested,
		CloseRequested = closeRequested,
		RectChanged = rectChanged,
		Destroy = function()
			for _, connection in connections do
				connection:Disconnect()
			end
			fadeSpring.Destroy()
			holder:Destroy()
		end,
	}
	applyTheme()
	layout()
	fadeSpring.Snap(0)
	return window
end

return table.freeze(WindowModule)
