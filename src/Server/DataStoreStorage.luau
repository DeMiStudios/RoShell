--!strict
--[[
	A DataStore-backed `StorageAdapter`: one DataStore key per scope (e.g. "user:123"), written through a small
	write-behind cache so rapid changes (history while typing commands) cost one request per scope per interval.
]]

--// Imports
const Types = require("../Shared/Types")

--// Types
export type StorageAdapter = Types.StorageAdapter

--// Constants
const FLUSH_INTERVAL = 6

--// DataStoreStorage
const DataStoreStorage = {}

function DataStoreStorage.new(storeName: string?): StorageAdapter
	const store = game:GetService("DataStoreService"):GetDataStore(storeName or "RoShell")
	const cache: { [string]: { [string]: unknown } } = {}
	const dirty: { [string]: true } = {}
	local scheduled = false

	const function load(scope: string): { [string]: unknown }
		const existing = cache[scope]
		if existing then
			return existing
		end
		local data: { [string]: unknown } = {}
		const ok, stored = pcall(function(): unknown
			return store:GetAsync(scope)
		end)
		if ok and type(stored) == "table" then
			for key, value in pairs(stored) do
				if type(key) == "string" then
					data[key] = value
				end
			end
		end
		cache[scope] = data
		return data
	end

	const function scheduleFlush()
		if scheduled then
			return
		end
		scheduled = true
		task.delay(FLUSH_INTERVAL, function()
			scheduled = false
			for scope in table.clone(dirty) do
				dirty[scope] = nil
				const data = cache[scope]
				if data then
					pcall(function()
						store:SetAsync(scope, data)
					end)
				end
			end
		end)
	end

	return table.freeze({
		Get = function(_self: StorageAdapter, scope: string, key: string): unknown
			return load(scope)[key]
		end,
		Set = function(_self: StorageAdapter, scope: string, key: string, value: unknown)
			load(scope)[key] = value
			dirty[scope] = true
			scheduleFlush()
		end,
		Remove = function(_self: StorageAdapter, scope: string, key: string)
			load(scope)[key] = nil
			dirty[scope] = true
			scheduleFlush()
		end,
	})
end

return table.freeze(DataStoreStorage)
