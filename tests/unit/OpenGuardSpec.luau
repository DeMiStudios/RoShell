--!strict
--[[
	The console ignores the rest of the input event that opened it, so a game's own shortcut or button can open the
	palette or fill the line of a closed console in one call (Client/UI/OpenGuard.luau).
--]]

--// Imports
const OpenGuard = require(script.Parent.Parent.Parent.src.Client.UI.OpenGuard)
const Runner = require(script.Parent.Parent.Runner)

--// Functions
-- Runs the oldest callback of a deferred queue run by hand (what `task.defer` would run once an event is over).
const function runNext(queue: { () -> () })
	const callback = table.remove(queue, 1)
	if callback then
		callback()
	end
end

-- A deferred queue and a function that runs everything in it.
const function deferredQueue(): ((callback: () -> ()) -> (), () -> ())
	const queue: { () -> () } = {}
	const function Defer(callback: () -> ())
		table.insert(queue, callback)
	end
	const function Flush()
		while #queue > 0 do
			runNext(queue)
		end
	end
	return Defer, Flush
end

return function(t: Runner.Api)
	t.it(
		"covers the rest of the event that opened the console, and nothing after it",
		function()
			const defer, flush = deferredQueue()
			const guard = OpenGuard.new(defer)
			t.expect(guard.Active()):toBe(false)
			-- A game's Ctrl+K handler opens the palette of a closed console...
			guard.Mark()
			-- ...so the console's own handler for the same Ctrl+K must not shut it again.
			t.expect(guard.Active()):toBe(true)
			flush()
			-- The next Ctrl+K is the player's and toggles the palette as usual.
			t.expect(guard.Active()):toBe(false)
		end
	)

	t.it(
		"stays up for a newer opening when an older one finishes",
		function()
			const queue: { () -> () } = {}
			const guard = OpenGuard.new(function(callback: () -> ())
				table.insert(queue, callback)
			end)
			guard.Mark()
			guard.Mark()
			-- The first opening's event ends: the second one's is still being handled.
			runNext(queue)
			t.expect(guard.Active()):toBe(true)
			runNext(queue)
			t.expect(guard.Active()):toBe(false)
		end
	)
end
