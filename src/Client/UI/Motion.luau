--!strict
--[[
	Animation primitives. Springs are preferred (they retarget smoothly while typing); tweens are used for
	one-shot transitions. Everything respects reduced motion: the player's setting, the console option, and the
	engine's `GuiService.ReducedMotionEnabled`. With reduced motion, springs snap and tweens finish instantly.

	All springs share one `RenderStepped` connection that only runs while some spring is moving.
]]

--// Types
export type Spring = {
	--- Moves the spring towards a new target.
	read SetTarget: (target: number) -> (),
	--- Jumps to a value without animating.
	read Snap: (value: number) -> (),
	read Get: () -> number,
	read GetTarget: () -> number,
	read Destroy: () -> (),
}

type SpringState = {
	Position: number,
	Velocity: number,
	Target: number,
	Frequency: number,
	Damping: number,
	OnStep: (value: number) -> (),
	Active: boolean,
}

--// Constants
const REST_EPSILON = 0.001
const MAX_STEP = 1 / 30
const TWO_PI = math.pi * 2

--// Globals
local reduceOverride = false
local stepConnection: RBXScriptConnection? = nil
const active: { [SpringState]: true } = {}

--// Helpers

const function engineReducedMotion(): boolean
	const ok, enabled = pcall(function(): boolean
		return game:GetService("GuiService").ReducedMotionEnabled
	end)
	return ok and enabled
end

--- Advances a damped harmonic oscillator by `dt` (semi-implicit Euler with sub-steps for stability).
const function advance(state: SpringState, dt: number)
	const omega = state.Frequency * TWO_PI
	local remaining = dt
	while remaining > 0 do
		const step = math.min(remaining, 1 / 240)
		const acceleration = omega * omega * (state.Target - state.Position)
			- 2 * state.Damping * omega * state.Velocity
		state.Velocity += acceleration * step
		state.Position += state.Velocity * step
		remaining -= step
	end
end

const function onRender(dt: number)
	const delta = math.min(dt, MAX_STEP)
	for state in active do
		advance(state, delta)
		if math.abs(state.Target - state.Position) < REST_EPSILON and math.abs(state.Velocity) < REST_EPSILON then
			state.Position = state.Target
			state.Velocity = 0
			state.Active = false
			active[state] = nil
		end
		state.OnStep(state.Position)
	end
	if next(active) == nil and stepConnection then
		stepConnection:Disconnect()
		stepConnection = nil
	end
end

const function wake(state: SpringState)
	if state.Active then
		return
	end
	state.Active = true
	active[state] = true
	if stepConnection == nil then
		stepConnection = game:GetService("RunService").RenderStepped:Connect(onRender)
	end
end

--// Motion
const Motion = {}

--- True when animations should be skipped.
function Motion.Reduced(): boolean
	return reduceOverride or engineReducedMotion()
end

--- Forces reduced motion on or off (from the `reduceMotion` setting / `ReduceMotion` option).
function Motion.SetReduced(reduced: boolean)
	reduceOverride = reduced
end

--- Creates a spring. `frequency` is in Hz (higher is snappier); `damping` 1 is critical (no overshoot).
function Motion.Spring(initial: number, frequency: number, damping: number, onStep: (value: number) -> ()): Spring
	const state: SpringState = {
		Position = initial,
		Velocity = 0,
		Target = initial,
		Frequency = frequency,
		Damping = damping,
		OnStep = onStep,
		Active = false,
	}
	const function snap(value: number)
		state.Position = value
		state.Target = value
		state.Velocity = 0
		if state.Active then
			state.Active = false
			active[state] = nil
		end
		onStep(value)
	end
	return table.freeze({
		SetTarget = function(target: number)
			if Motion.Reduced() then
				snap(target)
				return
			end
			state.Target = target
			if state.Position ~= target or state.Velocity ~= 0 then
				wake(state)
			end
		end,
		Snap = snap,
		Get = function(): number
			return state.Position
		end,
		GetTarget = function(): number
			return state.Target
		end,
		Destroy = function()
			active[state] = nil
			state.Active = false
		end,
	})
end

--- Tweens properties of an instance. Durations are in seconds; reduced motion makes them instant.
function Motion.Tween(
	instance: Instance,
	duration: number,
	properties: { [string]: unknown },
	style: Enum.EasingStyle?,
	direction: Enum.EasingDirection?,
	delay: number?
): Tween
	const reduced = Motion.Reduced()
	const info = TweenInfo.new(
		if reduced then 0 else duration,
		style or Enum.EasingStyle.Quint,
		direction or Enum.EasingDirection.Out,
		0,
		false,
		if reduced then 0 else delay or 0
	)
	const tween = game:GetService("TweenService"):Create(instance, info, properties)
	tween:Play()
	return tween
end

--- A short horizontal shake (rejected input). Restores the original position.
function Motion.Shake(instance: GuiObject, amplitude: number?)
	if Motion.Reduced() then
		return
	end
	const origin = instance.Position
	const size = amplitude or 6
	task.spawn(function()
		for _, offset in { size, -size, size * 0.6, -size * 0.6, 0 } do
			const tween = Motion.Tween(
				instance,
				0.04,
				{ Position = origin + UDim2.fromOffset(offset, 0) },
				Enum.EasingStyle.Sine,
				Enum.EasingDirection.InOut
			)
			tween.Completed:Wait()
		end
		instance.Position = origin
	end)
end

return table.freeze(Motion)
