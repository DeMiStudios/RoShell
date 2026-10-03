--!strict
--[[
	Audit sinks. Every command the server runs emits an `AuditEntry` (time, executor, raw text, command, formatted
	arguments, result, duration) to the shell's sink.

	- `Audit.Memory(capacity)`: ring buffer (default sink), printed to the output in Studio.
	- `Audit.Fanout({ sinks })`: writes to several sinks.
	- `Audit.DataStore(name)`: appends to an ordered DataStore by time (example of a persistent sink).
	- Implement `Types.AuditSink` (`Write`, optional `Recent`) for HTTP or anything else.
]]

--// Imports
const Types = require("../Shared/Types")

--// Types
export type AuditSink = Types.AuditSink

--// Audit
const Audit = {}

--- A ring buffer of the most recent entries.
function Audit.Memory(capacity: number?, echoInStudio: boolean?): AuditSink
	const size = capacity or 500
	const entries: { Types.AuditEntry } = {}
	local head = 0
	local count = 0
	const echo = echoInStudio ~= false
	return table.freeze({
		Write = function(_self: AuditSink, entry: Types.AuditEntry)
			head = head % size + 1
			entries[head] = entry
			count = math.min(count + 1, size)
			if echo and game:GetService("RunService"):IsStudio() then
				print(`[RoShell audit] {entry.Executor}: {entry.Raw} -> {if entry.Ok then "ok" else "failed"}{if entry.Result
						then " (" .. entry.Result .. ")"
						else ""}`)
			end
		end,
		Recent = function(_self: AuditSink, wanted: number): { Types.AuditEntry }
			const recent: { Types.AuditEntry } = {}
			for offset = 0, math.min(wanted, count) - 1 do
				const index = (head - offset - 1) % size + 1
				const entry = entries[index]
				if entry then
					table.insert(recent, entry)
				end
			end
			return recent
		end,
	})
end

--- Writes every entry to each sink; `Recent` comes from the first sink that supports it.
function Audit.Fanout(sinks: { AuditSink }): AuditSink
	return table.freeze({
		Write = function(_self: AuditSink, entry: Types.AuditEntry)
			for _, sink in sinks do
				pcall(sink.Write, sink, entry)
			end
		end,
		Recent = function(_self: AuditSink, wanted: number): { Types.AuditEntry }
			for _, sink in sinks do
				const recent = sink.Recent
				if recent then
					return recent(sink, wanted)
				end
			end
			return {}
		end,
	})
end

--- Appends entries to a DataStore (keyed by time). Writes are queued so commands never wait on the network.
function Audit.DataStore(storeName: string): AuditSink
	const queue: { Types.AuditEntry } = {}
	local flushing = false
	const function flush()
		if flushing then
			return
		end
		flushing = true
		task.spawn(function()
			const store = game:GetService("DataStoreService"):GetDataStore(storeName)
			while #queue > 0 do
				const entry = table.remove(queue, 1)
				if entry then
					pcall(function()
						store:SetAsync(`{math.floor(entry.Time * 1000)}_{entry.ExecutorId or 0}`, entry)
					end)
				end
				task.wait(0.5)
			end
			flushing = false
		end)
	end
	return table.freeze({
		Write = function(_self: AuditSink, entry: Types.AuditEntry)
			table.insert(queue, entry)
			if #queue > 1000 then
				table.remove(queue, 1)
			end
			flush()
		end,
	})
end

return table.freeze(Audit)
