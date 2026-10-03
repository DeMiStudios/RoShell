--!strict
--[[
	Cooperative cancellation. Long-running commands check `ctx:Cancelled()` / `ctx:CheckCancelled()`; the
	dispatcher also abandons a cancelled command's thread once its timeout or the user's cancel arrives.
]]

--// Imports
const Types = require("./Types")

--// Types
export type CancelToken = Types.CancelToken

--// Constants
--- Error value raised by `ctx:CheckCancelled()`; the dispatcher recognizes it.
const CANCELLED_MARKER = "\0RoShell.Cancelled"

--// CancelToken class
const CancelTokenClass = {}
CancelTokenClass.__index = CancelTokenClass

function CancelTokenClass.IsCancelled(self: CancelToken): boolean
	return self._cancelled
end

function CancelTokenClass.Reason(self: CancelToken): string?
	return self._reason
end

function CancelTokenClass.Cancel(self: CancelToken, reason: string?)
	if self._cancelled then
		return
	end
	self._cancelled = true
	self._reason = reason
	const callbacks = table.clone(self._callbacks)
	table.clear(self._callbacks)
	for _, callback in callbacks do
		const ok, err = pcall(callback, reason)
		if not ok then
			print(`[RoShell] cancel callback errored: {err}`)
		end
	end
end

function CancelTokenClass.OnCancel(self: CancelToken, callback: (reason: string?) -> ()): () -> ()
	if self._cancelled then
		callback(self._reason)
		return function()
		end
	end
	table.insert(self._callbacks, callback)
	return function()
		const index = table.find(self._callbacks, callback)
		if index then
			table.remove(self._callbacks, index)
		end
	end
end

table.freeze(CancelTokenClass)

--// CancelToken module
const CancelToken = {}

CancelToken.Marker = CANCELLED_MARKER

function CancelToken.new(): CancelToken
	return setmetatable({ _cancelled = false, _reason = nil :: string?, _callbacks = {} }, CancelTokenClass)
end

--- A token that is cancelled when `parent` is (cancelling the child does not affect the parent).
function CancelToken.Child(parent: CancelToken): CancelToken
	const child = CancelToken.new()
	const disconnect = parent:OnCancel(function(reason: string?)
		child:Cancel(reason)
	end)
	child:OnCancel(function()
		disconnect()
	end)
	return child
end

--- True when an error value is the cancellation marker.
function CancelToken.IsCancellation(err: unknown): boolean
	return type(err) == "string" and err:find(CANCELLED_MARKER, 1, true) ~= nil
end

return table.freeze(CancelToken)
