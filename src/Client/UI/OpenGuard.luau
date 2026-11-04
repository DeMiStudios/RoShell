--!strict
--[[
	The input event that opens the console belongs to whoever opened it. A game that opens the console from its own
	input handler (`shell:OpenPalette()` on Ctrl+K, `shell:SetInput(...)` on a click) runs in the same event as the
	console's own handler, in either order. Without this guard the console then handled that key or click a second
	time: Ctrl+K shut the palette it had just opened, and a click away from the bar hid the console again.

	`Mark()` when the console opens. `Active()` stays true until the event being handled is over (the deferred work
	queued after it has run), and the console ignores input while it is.
--]]

--// Types
export type OpenGuard = {
	--- The console just opened: input of the current event is not the console's.
	read Mark: () -> (),
	--- True while the event that opened the console is still being handled.
	read Active: () -> boolean,
}

--// OpenGuard
const OpenGuard = {}

--- `defer` runs a callback once the current event has been handled (default `task.defer`).
function OpenGuard.new(defer: ((callback: () -> ()) -> ())?): OpenGuard
	const schedule = defer
		or function(callback: () -> ())
			task.defer(callback)
		end
	local generation = 0
	local active = false
	return table.freeze({
		Mark = function()
			generation += 1
			const marked = generation
			active = true
			schedule(
				function()
					-- A later Mark keeps the guard up until its own event is over.
					if generation == marked then
						active = false
					end
				end
			)
		end,
		Active = function(): boolean
			return active
		end,
	})
end

return table.freeze(OpenGuard)
