--!strict
--[[
	Platform adapters. Everything the core needs from the engine (players, teams, time, scheduling, randomness)
	goes through a `PlatformInfo`, so the core can run headless under the standalone Luau runtime and in
	deterministic tests.

	- `Platform.Roblox()` uses the real engine services (only valid inside Roblox).
	- `Platform.Headless()` returns a platform with a virtual clock and a cooperative scheduler; drive it with
	  the returned controller (`Advance`, `SetPlayers`...).
]]

--// Imports
const Types = require("./Types")

--// Types
export type PlatformInfo = Types.PlatformInfo

export type HeadlessController = {
	--- Advances the virtual clock, running due timers in order.
	read Advance: (self: HeadlessController, seconds: number) -> (),
	--- Runs every pending timer regardless of its due time (bounded).
	read Flush: (self: HeadlessController) -> (),
	read SetPlayers: (self: HeadlessController, players: { Player }) -> (),
	read SetTeams: (self: HeadlessController, teams: { Team }) -> (),
	read SetLocalPlayer: (self: HeadlessController, player: Player?) -> (),
	read Platform: PlatformInfo,
	_state: HeadlessState,
}

type HeadlessState = {
	Time: number,
	Timers: { { Due: number, Thread: thread, Order: number } },
	Order: number,
	Players: { Player },
	Teams: { Team },
	LocalPlayer: Player?,
	Seed: number,
}

--// Helpers

const function resumeSafely(thread: thread)
	if coroutine.status(thread) ~= "suspended" then
		return
	end
	const ok, err = coroutine.resume(thread)
	if not ok then
		print(`[Platform] thread errored: {err}\n{debug.traceback(thread)}`)
	end
end

--// Headless controller
const HeadlessController = {}
HeadlessController.__index = HeadlessController

const function schedule(state: HeadlessState, delay: number, thread: thread)
	state.Order += 1
	table.insert(state.Timers, { Due = state.Time + math.max(0, delay), Thread = thread, Order = state.Order })
end

const function popDue(state: HeadlessState, limit: number): thread?
	local bestIndex: number? = nil
	for index, timer in state.Timers do
		if timer.Due <= limit then
			const best = if bestIndex then state.Timers[bestIndex] else nil
			if best == nil or timer.Due < best.Due or (timer.Due == best.Due and timer.Order < best.Order) then
				bestIndex = index
			end
		end
	end
	if bestIndex == nil then
		return nil
	end
	const timer = table.remove(state.Timers, bestIndex)
	if timer then
		state.Time = math.max(state.Time, timer.Due)
		return timer.Thread
	end
	return nil
end

function HeadlessController.Advance(self: HeadlessController, seconds: number)
	const state = self._state
	const target = state.Time + seconds
	while true do
		const thread = popDue(state, target)
		if thread == nil then
			break
		end
		resumeSafely(thread)
	end
	state.Time = target
end

function HeadlessController.Flush(self: HeadlessController)
	for _ = 1, 10000 do
		const thread = popDue(self._state, math.huge)
		if thread == nil then
			return
		end
		resumeSafely(thread)
	end
end

function HeadlessController.SetPlayers(self: HeadlessController, players: { Player })
	self._state.Players = players
end

function HeadlessController.SetTeams(self: HeadlessController, teams: { Team })
	self._state.Teams = teams
end

function HeadlessController.SetLocalPlayer(self: HeadlessController, player: Player?)
	self._state.LocalPlayer = player
end

table.freeze(HeadlessController)

--// Platform
const Platform = {}

--- The real Roblox engine platform.
function Platform.Roblox(): PlatformInfo
	const Players = game:GetService("Players")
	const Teams = game:GetService("Teams")
	const RunService = game:GetService("RunService")
	const random = Random.new()
	return table.freeze({
		GetPlayers = function(): { Player }
			return Players:GetPlayers()
		end,
		GetTeams = function(): { Team }
			const teams: { Team } = {}
			for _, child in Teams:GetChildren() do
				if child:IsA("Team") then
					table.insert(teams, child)
				end
			end
			return teams
		end,
		GetLocalPlayer = function(): Player?
			return Players.LocalPlayer
		end,
		IsStudio = function(): boolean
			return RunService:IsStudio()
		end,
		Now = function(): number
			return DateTime.now().UnixTimestampMillis / 1000
		end,
		Clock = os.clock,
		Random = function(minimum: number, maximum: number): number
			return random:NextInteger(minimum, maximum)
		end,
		Spawn = function(callback: () -> ()): thread
			return task.spawn(callback)
		end,
		Delay = function(seconds: number, callback: () -> ()): thread
			return task.delay(seconds, callback)
		end,
		Cancel = function(thread: thread)
			if coroutine.status(thread) ~= "dead" then
				pcall(task.cancel, thread)
			end
		end,
		Wait = function(seconds: number)
			task.wait(seconds)
		end,
		Gate = function(): Types.Gate
			-- A BindableEvent wait is a real engine yield, so callbacks resumed by it still return to the engine.
			local opened = false
			const event = Instance.new("BindableEvent")
			return table.freeze({
				Wait = function()
					if not opened then
						event.Event:Wait()
					end
				end,
				Open = function()
					if opened then
						return
					end
					opened = true
					event:Fire()
				end,
			})
		end,
	})
end

--- A deterministic platform for headless tests. Returns the platform's controller.
function Platform.Headless(seed: number?): HeadlessController
	const state: HeadlessState = {
		Time = 0,
		Timers = {},
		Order = 0,
		Players = {},
		Teams = {},
		LocalPlayer = nil,
		Seed = seed or 12345,
	}

	const platform: PlatformInfo = table.freeze({
		GetPlayers = function(): { Player }
			return table.clone(state.Players)
		end,
		GetTeams = function(): { Team }
			return table.clone(state.Teams)
		end,
		GetLocalPlayer = function(): Player?
			return state.LocalPlayer
		end,
		IsStudio = function(): boolean
			return true
		end,
		Now = function(): number
			return 1700000000 + state.Time
		end,
		Clock = function(): number
			return state.Time
		end,
		Random = function(minimum: number, maximum: number): number
			-- xorshift32 for reproducible tests.
			local x = state.Seed
			x = bit32.bxor(x, bit32.lshift(x, 13))
			x = bit32.bxor(x, bit32.rshift(x, 17))
			x = bit32.bxor(x, bit32.lshift(x, 5))
			state.Seed = x
			return minimum + x % (maximum - minimum + 1)
		end,
		Spawn = function(callback: () -> ()): thread
			const thread = coroutine.create(callback)
			resumeSafely(thread)
			return thread
		end,
		Delay = function(seconds: number, callback: () -> ()): thread
			const thread = coroutine.create(callback)
			schedule(state, seconds, thread)
			return thread
		end,
		Cancel = function(thread: thread)
			for index, timer in state.Timers do
				if timer.Thread == thread then
					table.remove(state.Timers, index)
					break
				end
			end
			if coroutine.status(thread) == "suspended" then
				coroutine.close(thread)
			end
		end,
		Wait = function(seconds: number)
			const thread = coroutine.running()
			schedule(state, seconds, thread)
			coroutine.yield()
		end,
		Gate = function(): Types.Gate
			local opened = false
			local waiter: thread? = nil
			return table.freeze({
				Wait = function()
					if opened then
						return
					end
					waiter = coroutine.running()
					coroutine.yield()
				end,
				Open = function()
					if opened then
						return
					end
					opened = true
					const thread = waiter
					waiter = nil
					if thread then
						resumeSafely(thread)
					end
				end,
			})
		end,
	})

	return setmetatable({ Platform = platform, _state = state }, HeadlessController)
end

return table.freeze(Platform)
