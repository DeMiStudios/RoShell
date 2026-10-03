--!strict
--[[
	Minimal typed signal. Handlers run synchronously in connection order; a handler that errors is reported with
	`warn`-style output but does not stop the others. Handlers may yield (each runs in its own coroutine).
]]

--// Imports
const Types = require("./Types")

--// Types
export type Signal<T...> = Types.Signal<T...>
export type Connection = Types.Connection

--// Helpers

const function report(message: string)
	-- `warn` does not exist in the standalone Luau runtime used for headless tests.
	const warnFunction: ((...unknown) -> ())? = (warn :: ((...unknown) -> ())?)
	if warnFunction then
		warnFunction(message)
	else
		print(message)
	end
end

const function runHandler<T...>(handler: (T...) -> (), ...: T...)
	const thread = coroutine.create(handler)
	const ok, err = coroutine.resume(thread, ...)
	if not ok then
		report(`[Signal] handler errored: {err}\n{debug.traceback(thread)}`)
	end
end

--// Connection class
const ConnectionClass = {}
ConnectionClass.__index = ConnectionClass

function ConnectionClass.Disconnect(self: Connection)
	if not self.Connected then
		return
	end
	self.Connected = false
	self._disconnect()
end

table.freeze(ConnectionClass)

--// Signal class
const Signal = {}
Signal.__index = Signal

--- Creates a new signal.
function Signal.new<T...>(): Signal<T...>
	return setmetatable({ _handlers = {}, _connections = {} }, Signal)
end

function Signal.Connect<T...>(self: Signal<T...>, callback: (T...) -> ()): Connection
	local connection: Connection
	connection = setmetatable(
		{
			Connected = true,
			_disconnect = function()
				const index = table.find(self._connections, connection)
				if index then
					table.remove(self._connections, index)
					table.remove(self._handlers, index)
				end
			end,
		},
		ConnectionClass
	)
	table.insert(self._connections, connection)
	table.insert(self._handlers, callback)
	return connection
end

function Signal.Once<T...>(self: Signal<T...>, callback: (T...) -> ()): Connection
	local connection: Connection? = nil
	connection = self:Connect(function(...: T...)
		if connection then
			connection:Disconnect()
		end
		callback(...)
	end)
	return connection :: Connection
end

function Signal.Fire<T...>(self: Signal<T...>, ...: T...)
	-- Snapshot so handlers can disconnect/connect while firing.
	const handlers = table.clone(self._handlers)
	for _, handler in handlers do
		runHandler(handler, ...)
	end
end

function Signal.Wait<T...>(self: Signal<T...>): T...
	const thread = coroutine.running()
	self:Once(function(...: T...)
		coroutine.resume(thread, ...)
	end)
	return coroutine.yield()
end

function Signal.DisconnectAll<T...>(self: Signal<T...>)
	for _, connection in table.clone(self._connections) do
		connection:Disconnect()
	end
end

return table.freeze(Signal)
