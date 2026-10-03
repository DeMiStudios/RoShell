--!strict
--[[
	View models for the command bar's panel. Pure (no instances), so what the panel shows for a line is unit tested
	headlessly: a list of commands on the left, and on the right the signature with the argument being typed, its
	type and description, and its candidates.

	Colors are hex strings chosen by the caller, so the models carry finished RichText.
]]

--// Imports
const Command = require("../../Shared/Command")
const Completion = require("../../Shared/Completion")
const Types = require("../../Shared/Types")
const Util = require("../../Shared/Util")

--// Types
export type Span = { Start: number, End: number }

--- One row of a list.
export type Item = {
	Label: string,
	--- Byte spans of `Label` to emphasize (fuzzy matches).
	Ranges: { Span }?,
	--- Second line of a two-line row.
	Subtitle: string?,
	--- Right-aligned secondary text.
	Detail: string?,
	--- Icon key (see Icons.luau).
	Icon: string?,
	--- Theme token for the icon: `command`, `flag`, `operator`, `variable`, `accent`, `muted`, a level, or a type token.
	Tint: string?,
	--- Color chips drawn instead of the icon (theme previews).
	Swatches: { Color3 }?,
	Deprecated: boolean?,
}

export type List = { Items: { Item }, Selected: number? }

export type Section = {
	Heading: string?,
	--- RichText body.
	Rich: string,
	--- Draw the body in the monospace font (examples, code).
	Mono: boolean?,
}

export type Notice = { Text: string, Level: Types.Level }

--- The argument (or flag) being typed.
export type Active = { Name: string, Type: string?, Description: string? }

export type Details = {
	--- RichText title (a command signature, a theme name...).
	Title: string,
	Description: string?,
	Notice: Notice?,
	Active: Active?,
	Sections: { Section },
	Swatches: { Color3 }?,
}

export type Assist = {
	Left: List?,
	Details: Details?,
	Right: List?,
	--- The list the arrow keys move and Tab accepts from.
	Focus: "left" | "right",
}

--- Hex colors for RichText.
export type Colors = {
	Text: string,
	Secondary: string,
	Muted: string,
	Accent: string,
	--- Color of a type token (`type.player`), for argument lists.
	Type: (token: string?) -> string,
}

export type SuggestInput = {
	Result: Completion.CompletionResult,
	--- Highlighted suggestion (index into `Result.Suggestions`).
	Selected: number?,
	--- Problem nearest to the caret, shown under the signature.
	Diagnostic: Types.Diagnostic?,
	GetCommand: (name: string) -> Types.Command?,
	--- Commands listed under the current one while an argument is typed (most relevant first).
	Others: { Types.Command },
	Colors: Colors,
}

--// Constants
--- Commands shown in the left column while an argument is typed.
const CONTEXT_ROWS = 5

--// Helpers

const escape = Util.EscapeRichText

const function colored(color: string, text: string): string
	return `<font color="{color}">{text}</font>`
end

--- `players` -> `Players`: type names read like type names.
const function typeLabel(name: string): string
	return name:sub(1, 1):upper() .. name:sub(2)
end

const function commandItem(command: Types.Command, label: string?, ranges: { Span }?, alias: boolean?): Item
	return {
		Label = label or Command.FullName(command),
		Ranges = ranges,
		Subtitle = if alias then `alias of {command.Name} · {command.Description}` else command.Description,
		Icon = command.Icon or (if alias then "alias" else "command"),
		Tint = "command",
		Deprecated = command.Deprecated ~= nil,
	}
end

const function list(items: { Item }, selected: number?): List
	return { Items = items, Selected = selected }
end

--- Details with nothing but a title and a problem (an unknown command).
const function problem(title: string, notice: Notice): Details
	return { Title = title, Notice = notice, Sections = {} }
end

const function suggestionTint(suggestion: Types.Suggestion): string?
	if suggestion.Color then
		return suggestion.Color
	end
	const kind = suggestion.Kind
	if kind == "command" or kind == "alias" or kind == "subcommand" then
		return "command"
	elseif kind == "flag" or kind == "operator" or kind == "variable" then
		return kind
	end
	return nil
end

--// Model
const Model = {}

--- A command by full name (`ban add` finds the `add` subcommand of `ban`).
function Model.FindCommand(getCommand: (name: string) -> Types.Command?, fullName: string): Types.Command?
	local command: Types.Command? = nil
	for word in fullName:gmatch("%S+") do
		if command == nil then
			command = getCommand(word)
		else
			local found: Types.Command? = nil
			for _, sub in command.Subcommands do
				if sub.Name:lower() == word:lower() then
					found = sub
					break
				end
			end
			command = found
		end
		if command == nil then
			return nil
		end
	end
	return command
end

--- `giveitem <player> <itemKey> [amount]` with `active` highlighted.
function Model.Signature(command: Types.Command, active: string?, colors: Colors): string
	const parts: { string } = { colored(colors.Text, `<b>{escape(Command.FullName(command))}</b>`) }
	for _, arg in command.Args do
		if arg.Options.Hidden then
			continue
		end
		local text: string
		if arg.Kind == "flag" or not arg.Positional then
			text = `[--{arg.Name}]`
		elseif arg.Kind == "required" then
			text = `<{arg.Name}>`
		elseif arg.Kind == "rest" then
			text = `<{arg.Name}…>`
		else
			text = `[{arg.Name}]`
		end
		if arg.Name == active then
			table.insert(parts, colored(colors.Accent, `<b>{escape(text)}</b>`))
		else
			table.insert(
				parts,
				colored(if arg.Kind == "required" then colors.Secondary else colors.Muted, escape(text))
			)
		end
	end
	return table.concat(parts, " ")
end

--- Everything about a command: signature, description, arguments, examples, aliases.
function Model.CommandDetails(command: Types.Command, colors: Colors): Details
	const sections: { Section } = {}
	const lines: { string } = {}
	for _, arg in command.Args do
		if arg.Options.Hidden then
			continue
		end
		local line = colored(colors.Text, escape(arg.Name))
			.. colored(colors.Muted, " · ")
			.. colored(colors.Type(arg.Type.Color), escape(typeLabel(arg.Type.Name)))
		if arg.DefaultDisplay then
			line ..= colored(colors.Muted, escape(` = {arg.DefaultDisplay}`))
		elseif arg.Optional then
			line ..= colored(colors.Muted, " (optional)")
		end
		const description = arg.Options.Description or arg.Type.Description
		if description and description ~= "" then
			line ..= colored(colors.Secondary, ` — {escape(description)}`)
		end
		table.insert(lines, line)
	end
	if #lines > 0 then
		table.insert(sections, { Heading = "Arguments", Rich = table.concat(lines, "\n") })
	end
	if #command.Examples > 0 then
		const examples: { string } = {}
		for index, example in command.Examples do
			if index > 3 then
				break
			end
			table.insert(examples, escape(example.Text))
		end
		table.insert(sections, { Heading = "Examples", Rich = table.concat(examples, "\n"), Mono = true })
	end
	if #command.Aliases > 0 then
		table.insert(sections, { Heading = "Aliases", Rich = escape(Util.Join(command.Aliases, ", ")) })
	end
	if command._isAlias and command._aliasBody then
		table.insert(sections, { Heading = "Runs", Rich = escape(command._aliasBody), Mono = true })
	end
	const deprecation = command.Deprecated
	return {
		Title = Model.Signature(command, nil, colors),
		Description = if command.Description ~= "" then command.Description else nil,
		Notice = if deprecation then {
				Text = deprecation.Message
					or (if deprecation.Replacement then `Deprecated: use {deprecation.Replacement}` else "Deprecated"),
				Level = "warning" :: Types.Level,
			}
			else nil,
		Sections = sections,
	}
end

--- A one-line row for an argument candidate (or flag, operator, variable).
function Model.ValueItem(suggestion: Types.Suggestion): Item
	return {
		Label = suggestion.Display,
		Ranges = suggestion.MatchRanges,
		Detail = suggestion.Detail,
		Icon = suggestion.Icon or suggestion.Kind,
		Tint = suggestionTint(suggestion),
		Swatches = if suggestion.Swatch then { suggestion.Swatch } else nil,
		Deprecated = suggestion.Deprecated,
	}
end

--- What the panel shows while a line is typed.
function Model.Suggest(input: SuggestInput): Assist
	const result = input.Result
	const colors = input.Colors
	const suggestions = result.Suggestions
	const notice: Notice? = if input.Diagnostic then {
			Text = input.Diagnostic.Message,
			Level = if input.Diagnostic.Severity == "warning" then "warning" else "error",
		}
		else nil

	-- Choosing a command: the commands are the list, the highlighted one is described.
	if result.Context == "Command" or result.Context == "Subcommand" then
		const items: { Item } = {}
		local selectedCommand: Types.Command? = nil
		const selected = if input.Selected and suggestions[input.Selected] then input.Selected
			elseif #suggestions > 0 then 1
			else nil
		const parent = if result.Context == "Subcommand" and result.Signature then Model.FindCommand(
				input.GetCommand,
				result.Signature.Command
			)
			else nil
		for index, suggestion in suggestions do
			local command: Types.Command? = nil
			if result.Context == "Subcommand" and parent then
				const owner = parent._parent or parent
				command = Model.FindCommand(input.GetCommand, `{Command.FullName(owner)} {suggestion.Text}`)
			else
				command = input.GetCommand(suggestion.Text)
			end
			if command then
				const item = commandItem(
					command,
					suggestion.Display,
					suggestion.MatchRanges,
					suggestion.Kind == "alias"
				)
				item.Deprecated = suggestion.Deprecated
				table.insert(items, item)
			else
				const item = Model.ValueItem(suggestion)
				item.Subtitle = suggestion.Description
				table.insert(items, item)
			end
			if index == selected then
				selectedCommand = command
			end
		end
		local details: Details? = nil
		if selectedCommand then
			details = Model.CommandDetails(selectedCommand, colors)
		elseif notice then
			details = problem(colored(colors.Text, `<b>{escape(result.Partial)}</b>`), notice)
		end
		return {
			Left = if #items > 0 then list(items, selected) else nil,
			Details = details,
			Right = nil,
			Focus = "left",
		}
	end

	-- Typing an argument: the command stays on the left; the right shows the argument and its candidates.
	const signature = result.Signature
	const command = if signature then Model.FindCommand(input.GetCommand, signature.Command) else nil
	local left: List? = nil
	local details: Details? = nil
	if command and signature then
		const items: { Item } = { commandItem(command) }
		for _, other in input.Others do
			if #items > CONTEXT_ROWS then
				break
			end
			if other ~= command then
				table.insert(items, commandItem(other))
			end
		end
		left = list(items, 1)
		local activeName: string? = nil
		for _, part in signature.Parts do
			if part.Active and part.ArgName then
				activeName = part.ArgName
			end
		end
		local active: Active? = nil
		if activeName then
			active = {
				Name = activeName,
				Type = if signature.ActiveType then typeLabel(signature.ActiveType) else nil,
				Description = signature.ActiveDescription,
			}
		end
		const sections: { Section } = {}
		const preview = result.Preview
		if preview and preview.Ok and preview.Text ~= "" then
			table.insert(sections, { Rich = colored(colors.Accent, `→ {escape(preview.Text)}`) })
		end
		-- What the highlighted candidate is.
		const chosen = suggestions[input.Selected or 1]
		if chosen and chosen.Description and chosen.Description ~= "" then
			table.insert(sections, {
				Rich = colored(colors.Text, `<b>{escape(chosen.Display)}</b>`)
					.. colored(colors.Secondary, ` — {escape(chosen.Description)}`),
			})
		end
		const described: Details = {
			Title = Model.Signature(command, activeName, colors),
			Description = if command.Description ~= "" then command.Description else nil,
			Notice = notice,
			Active = active,
			Sections = sections,
		}
		details = described
	elseif notice then
		details = problem(colored(colors.Text, `<b>{escape(result.Partial)}</b>`), notice)
	end

	local right: List? = nil
	if #suggestions > 0 then
		const items: { Item } = {}
		for index, suggestion in suggestions do
			items[index] = Model.ValueItem(suggestion)
		end
		right = list(items, if input.Selected and suggestions[input.Selected] then input.Selected else 1)
	end
	return { Left = left, Details = details, Right = right, Focus = "right" }
end

return table.freeze(Model)
