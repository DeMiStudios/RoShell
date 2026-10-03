--!strict
--[[
	Fuzzy pickers — the command palette (Ctrl+K), history search (Ctrl+R), themes and settings. The command bar's
	input becomes the search field; matches show in the panel's two-pane view with the highlighted entry described
	on the right. An entry can preview itself while highlighted (themes apply live); closing without choosing undoes
	it.
]]

--// Imports
const Fuzzy = require("../../Shared/Fuzzy")
const Model = require("./Model")
const Signal = require("../../Shared/Signal")
const Types = require("../../Shared/Types")

--// Types
export type Entry = {
	Item: Model.Item,
	--- Text the query is matched against first (the label, aliases).
	Search: string,
	--- Matched only after every `Search` match (a description), so `tp` finds `teleport` before a description
	--- that happens to contain a t and a p.
	Extra: string?,
	--- The right column while the entry is highlighted.
	Details: (() -> Model.Details)?,
	--- Applied while the entry is highlighted (e.g. a theme), undone when the picker closes without choosing.
	Preview: (() -> ())?,
	--- `alternate` is true for Shift+Enter (e.g. run instead of insert).
	Choose: (alternate: boolean) -> (),
}

export type OpenOptions = {
	--- Placeholder of the bar while the picker is open.
	Placeholder: string,
	Entries: { Entry },
	--- Initial query.
	Query: string?,
	--- Entry highlighted first (e.g. the current theme) while the query is empty.
	Selected: number?,
	--- Runs when the picker closes without a choice (to undo a preview).
	OnCancel: (() -> ())?,
}

export type Picker = {
	read Open: (options: OpenOptions) -> (),
	--- Closes; `chosen` skips `OnCancel`.
	read Close: (chosen: boolean?) -> (),
	read IsOpen: () -> boolean,
	read SetQuery: (query: string) -> (),
	read Move: (delta: number) -> (),
	--- Highlights an entry (mouse hover).
	read Select: (index: number) -> (),
	--- Chooses the highlighted entry (or `index`).
	read Choose: (alternate: boolean, index: number?) -> (),
	read Model: () -> Model.Assist,
	read Placeholder: () -> string,
	--- The model changed (query, highlight, entries).
	read Changed: Types.Signal<()>,
}

--// Constants
const LIMIT = 200

--// Helpers

const function searchText(entry: Entry): string
	return entry.Search
end

const function extraText(entry: Entry): string
	return entry.Extra or ""
end

--// Picker
const PickerModule = {}

function PickerModule.new(): Picker
	local open = false
	local options: OpenOptions = { Placeholder = "", Entries = {} }
	local visible: { Entry } = {}
	local items: { Model.Item } = {}
	local selected: number? = nil
	const changed: Types.Signal<()> = Signal.new()

	const function preview()
		const entry = if selected then visible[selected] else nil
		if entry and entry.Preview then
			entry.Preview()
		end
	end

	const function filter(query: string)
		visible = {}
		items = {}
		if query == "" then
			for index, entry in options.Entries do
				if index > LIMIT then
					break
				end
				table.insert(visible, entry)
				const item = table.clone(entry.Item)
				item.Ranges = nil
				table.insert(items, item)
			end
		else
			const seen: { [Entry]: true } = {}
			for _, scored in Fuzzy.Filter(query, options.Entries, searchText, LIMIT) do
				const entry = scored.Item
				seen[entry] = true
				table.insert(visible, entry)
				const item = table.clone(entry.Item)
				const labelLength = #item.Label
				const ranges: { Model.Span } = {}
				for _, range in scored.Ranges do
					if range.End - 1 <= labelLength then
						table.insert(ranges, range)
					end
				end
				item.Ranges = ranges
				table.insert(items, item)
			end
			-- Then entries whose descriptions match.
			for _, scored in Fuzzy.Filter(query, options.Entries, extraText, LIMIT) do
				const entry = scored.Item
				if not seen[entry] and #visible < LIMIT then
					table.insert(visible, entry)
					const item = table.clone(entry.Item)
					item.Ranges = nil
					table.insert(items, item)
				end
			end
		end
		selected = if #visible == 0 then nil
			elseif query == "" and options.Selected and visible[options.Selected] then options.Selected
			else 1
	end

	local picker: Picker

	picker = {
		Open = function(next: OpenOptions)
			options = next
			open = true
			filter(next.Query or "")
			preview()
			changed:Fire()
		end,
		Close = function(chosen: boolean?)
			if not open then
				return
			end
			open = false
			const cancel = options.OnCancel
			if not chosen and cancel then
				cancel()
			end
			visible = {}
			items = {}
			selected = nil
			changed:Fire()
		end,
		IsOpen = function(): boolean
			return open
		end,
		SetQuery = function(query: string)
			if not open then
				return
			end
			filter(query)
			preview()
			changed:Fire()
		end,
		Move = function(delta: number)
			if #visible == 0 then
				return
			end
			const current = selected or (if delta > 0 then 0 else #visible + 1)
			selected = (current + delta - 1) % #visible + 1
			preview()
			changed:Fire()
		end,
		Select = function(index: number)
			if visible[index] and index ~= selected then
				selected = index
				preview()
				changed:Fire()
			end
		end,
		Choose = function(alternate: boolean, index: number?)
			const position = index or selected
			const entry = if position then visible[position] else nil
			if entry then
				picker.Close(true)
				entry.Choose(alternate)
			end
		end,
		Model = function(): Model.Assist
			const entry = if selected then visible[selected] else nil
			const details = if entry and entry.Details then entry.Details() else nil
			return {
				Left = { Items = items, Selected = selected },
				Details = details,
				Right = nil,
				Focus = "left",
			}
		end,
		Placeholder = function(): string
			return options.Placeholder
		end,
		Changed = changed,
	}
	return picker
end

return table.freeze(PickerModule)
