--!strict
--[[
	Storage adapters (history, aliases, binds, variables, UI preferences). `Storage.Memory()` is the default;
	`Server/DataStoreStorage` persists to a DataStore. Implement `Types.StorageAdapter` for anything else.
]]

--// Imports
const Types = require("./Types")

--// Types
export type StorageAdapter = Types.StorageAdapter

--// Storage
const Storage = {}

--- In-memory storage (lost when the server/client shuts down).
function Storage.Memory(): StorageAdapter
	const data: { [string]: { [string]: unknown } } = {}
	return table.freeze({
		Get = function(_self: StorageAdapter, scope: string, key: string): unknown
			const bucket = data[scope]
			return if bucket then bucket[key] else nil
		end,
		Set = function(_self: StorageAdapter, scope: string, key: string, value: unknown)
			local bucket = data[scope]
			if bucket == nil then
				bucket = {}
				data[scope] = bucket
			end
			bucket[key] = value
		end,
		Remove = function(_self: StorageAdapter, scope: string, key: string)
			const bucket = data[scope]
			if bucket then
				bucket[key] = nil
			end
		end,
	})
end

return table.freeze(Storage)
