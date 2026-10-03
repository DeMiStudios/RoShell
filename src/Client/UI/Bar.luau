--!strict
--[[
	The command bar's placement: a pill docked to the top of the screen (below Roblox's top bar — the default, like
	Cmdr), docked to the bottom, or floating where the player dragged it. Dragging the prompt icon moves it; letting
	go near a docked position snaps back into that dock. Opening slides it in from its edge and fades it in; on
	touch screens it stays clear of the on-screen keyboard.

	Rects are in the coordinates of the full-screen root frame (the console's GUI ignores the top bar inset).
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

export type Rect = { X: number, Y: number, Width: number, Height: number }

export type Bar = {
	read Holder: Frame,
	--- Put the bar's contents here.
	read Content: GuiObject,
	read Open: () -> (),
	read Close: (onClosed: (() -> ())?) -> (),
	read IsOpen: () -> boolean,
	read SetDock: (dock: Dock) -> (),
	read GetDock: () -> Dock,
	--- Floating position as fractions of the screen (center X, top Y); nil for the default.
	read SetFloat: (position: Vector2?) -> (),
	read GetFloat: () -> Vector2?,
	--- Where the bar is (or is going), in root coordinates.
	read Rect: () -> Rect,
	--- Screen bounds right now (AbsolutePosition space), for click-away detection.
	read Bounds: () -> Rect,
	--- Lowest point the panel may reach (above the on-screen keyboard), in root coordinates.
	read FloorY: () -> number,
	--- Highest point the panel may reach (below Roblox's top bar), in root coordinates.
	read CeilingY: () -> number,
	--- Starts dragging from this button.
	read AttachHandle: (handle: GuiButton) -> (),
	read SetFocused: (focused: boolean) -> (),
	read SetOpacity: (opacity: number) -> (),
	read SetTheme: (palette: Theme.Palette) -> (),
	read SetMetrics: (metrics: Ui.Metrics) -> (),
	--- Fired when the target rect changes (dock, drag, screen size, keyboard).
	read Moved: Types.Signal<()>,
	--- Fired after the player drags the bar (to persist the dock and position).
	read Dragged: Types.Signal<()>,
	read Destroy: () -> (),
}

--// Constants
const MARGIN = 12
const DRAG_THRESHOLD = 6
--- Letting go this close to a docked position docks the bar there.
const SNAP = 28

--// Bar
const BarModule = {}

function BarModule.new(parent: GuiObject, initialPalette: Theme.Palette, initialMetrics: Ui.Metrics): Bar
	const UserInputService = game:GetService("UserInputService")
	const GuiService = game:GetService("GuiService")
	local palette = initialPalette
	local metrics = initialMetrics
	local dock: Dock = "top"
	local float: Vector2? = nil
	local open = false
	local generation = 0
	local keyboardTop: number? = nil
	const connections: { RBXScriptConnection } = {}
	const moved: Types.Signal<()> = Signal.new()
	const dragged: Types.Signal<()> = Signal.new()

	const surface = Surface.new("Bar", parent, 999, palette, { Canvas = true })
	const holder = surface.Holder
	holder.Visible = false
	holder.ZIndex = 20
	const card = surface.Card
	const scale = Instance.new("UIScale")
	scale.Parent = holder

	-- Geometry ---------------------------------------------------------------------------------------------
	const function screen(): Vector2
		return parent.AbsoluteSize
	end

	const function inset(): number
		return GuiService:GetGuiInset().Y
	end

	const function width(): number
		return math.min(screen().X - MARGIN * 2, metrics.BarWidth)
	end

	const function dockedY(which: Dock): number
		if which == "bottom" then
			const bottom = if keyboardTop then math.min(screen().Y, keyboardTop) else screen().Y
			return bottom - metrics.BarHeight - MARGIN
		end
		return inset() + MARGIN
	end

	const function currentRect(): Rect
		const size = screen()
		const barWidth = width()
		const height = metrics.BarHeight
		if dock == "float" then
			const fraction = float or Vector2.new(0.5, 0.18)
			local x = math.floor(fraction.X * size.X - barWidth / 2)
			local y = math.floor(fraction.Y * size.Y)
			x = math.clamp(x, MARGIN, math.max(MARGIN, size.X - barWidth - MARGIN))
			const floor = (if keyboardTop then math.min(size.Y, keyboardTop) else size.Y) - height - MARGIN
			y = math.clamp(y, inset() + MARGIN, math.max(inset() + MARGIN, floor))
			return { X = x, Y = y, Width = barWidth, Height = height }
		end
		return { X = (size.X - barWidth) // 2, Y = dockedY(dock), Width = barWidth, Height = height }
	end

	const function applyRect(animate: boolean)
		const rect = currentRect()
		holder.Size = UDim2.fromOffset(rect.Width, rect.Height)
		const target = UDim2.fromOffset(rect.X, rect.Y)
		if animate and open then
			Motion.Tween(holder, 0.18, { Position = target })
		else
			holder.Position = target
		end
		moved:Fire()
	end

	-- Dragging -------------------------------------------------------------------------------------------------
	local dragInput: InputObject? = nil
	local dragStart = Vector2.zero
	local dragRect: Rect = { X = 0, Y = 0, Width = 0, Height = 0 }
	local dragMoved = false

	const function beginDrag(inputObject: InputObject)
		const kind = inputObject.UserInputType
		if kind ~= Enum.UserInputType.MouseButton1 and kind ~= Enum.UserInputType.Touch then
			return
		end
		dragInput = inputObject
		dragStart = Vector2.new(inputObject.Position.X, inputObject.Position.Y)
		dragRect = currentRect()
		dragMoved = false
	end

	table.insert(
		connections,
		UserInputService.InputChanged:Connect(function(inputObject: InputObject)
			const current = dragInput
			if current == nil then
				return
			end
			const moving = inputObject.UserInputType == Enum.UserInputType.MouseMovement
				or (inputObject.UserInputType == Enum.UserInputType.Touch and inputObject == current)
			if not moving then
				return
			end
			const delta = Vector2.new(inputObject.Position.X, inputObject.Position.Y) - dragStart
			if not dragMoved and delta.Magnitude < DRAG_THRESHOLD then
				return
			end
			dragMoved = true
			const size = screen()
			dock = "float"
			float = Vector2.new(
				(dragRect.X + delta.X + dragRect.Width / 2) / math.max(1, size.X),
				(dragRect.Y + delta.Y) / math.max(1, size.Y)
			)
			applyRect(false)
		end)
	)
	table.insert(
		connections,
		UserInputService.InputEnded:Connect(
			function(inputObject: InputObject)
				const current = dragInput
				if current == nil then
					return
				end
				if inputObject ~= current and inputObject.UserInputType ~= Enum.UserInputType.MouseButton1 then
					return
				end
				dragInput = nil
				if not dragMoved then
					return
				end
				-- Close to a docked position: dock there.
				const rect = currentRect()
				if math.abs(rect.Y - dockedY("top")) <= SNAP then
					dock = "top"
				elseif math.abs(rect.Y - dockedY("bottom")) <= SNAP then
					dock = "bottom"
				end
				applyRect(true)
				dragged:Fire()
			end
		)
	)

	-- Screen and keyboard changes ------------------------------------------------------------------------------
	table.insert(
		connections,
		parent:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
			applyRect(false)
		end)
	)
	const function readKeyboard()
		const ok, visible = pcall(function(): boolean
			return UserInputService.OnScreenKeyboardVisible
		end)
		if ok and visible then
			-- The keyboard's position is in screen space (it includes the top bar inset).
			keyboardTop = UserInputService.OnScreenKeyboardPosition.Y
		else
			keyboardTop = nil
		end
		applyRect(true)
	end
	for _, property in { "OnScreenKeyboardVisible", "OnScreenKeyboardPosition" } do
		const ok, signal = pcall(function(): RBXScriptSignal
			return UserInputService:GetPropertyChangedSignal(property)
		end)
		if ok then
			table.insert(connections, signal:Connect(readKeyboard))
		end
	end

	-- Transitions --------------------------------------------------------------------------------------------
	const function hiddenPosition(): UDim2
		const rect = currentRect()
		if dock == "top" then
			return UDim2.fromOffset(rect.X, rect.Y - rect.Height - 12)
		elseif dock == "bottom" then
			return UDim2.fromOffset(rect.X, rect.Y + rect.Height + 12)
		end
		return UDim2.fromOffset(rect.X, rect.Y + 8)
	end

	const fadeSpring = Motion.Spring(0, 5, 1, function(alpha: number)
		surface.SetFade(alpha)
	end)

	const bar: Bar = {
		Holder = holder,
		Content = card,
		Open = function()
			if open then
				return
			end
			open = true
			generation += 1
			const rect = currentRect()
			holder.Size = UDim2.fromOffset(rect.Width, rect.Height)
			holder.Visible = true
			holder.Position = hiddenPosition()
			scale.Scale = if dock == "float" and not Motion.Reduced() then 0.97 else 1
			Motion.Tween(holder, 0.22, { Position = UDim2.fromOffset(rect.X, rect.Y) })
			Motion.Tween(scale, 0.22, { Scale = 1 })
			fadeSpring.SetTarget(1)
			moved:Fire()
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
				{ Position = hiddenPosition() },
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
		SetDock = function(next: Dock)
			if next == dock then
				return
			end
			dock = next
			applyRect(true)
		end,
		GetDock = function(): Dock
			return dock
		end,
		SetFloat = function(position: Vector2?)
			float = position
			if dock == "float" then
				applyRect(true)
			end
		end,
		GetFloat = function(): Vector2?
			return float
		end,
		Rect = currentRect,
		Bounds = function(): Rect
			const position = holder.AbsolutePosition
			const size = holder.AbsoluteSize
			return { X = position.X, Y = position.Y, Width = size.X, Height = size.Y }
		end,
		FloorY = function(): number
			const bottom = if keyboardTop then math.min(screen().Y, keyboardTop) else screen().Y
			return bottom - MARGIN
		end,
		CeilingY = function(): number
			return inset() + MARGIN
		end,
		AttachHandle = function(handle: GuiButton)
			table.insert(connections, handle.InputBegan:Connect(beginDrag))
		end,
		SetFocused = surface.SetFocused,
		SetOpacity = surface.SetOpacity,
		SetTheme = function(next: Theme.Palette)
			palette = next
			surface.SetTheme(palette)
		end,
		SetMetrics = function(next: Ui.Metrics)
			metrics = next
			applyRect(false)
		end,
		Moved = moved,
		Dragged = dragged,
		Destroy = function()
			for _, connection in connections do
				connection:Disconnect()
			end
			fadeSpring.Destroy()
			holder:Destroy()
		end,
	}
	surface.SetTheme(palette)
	fadeSpring.Snap(0)
	return bar
end

return table.freeze(BarModule)
