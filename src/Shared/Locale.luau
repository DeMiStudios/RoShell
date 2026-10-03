--!strict
--[[
	Localization. Every built-in user-facing string goes through `Locale:Get(key, params)`, with `{param}`
	placeholders. Override any string with `shell.Locale:Set({ ["key"] = "text" })`.
]]

--// Imports
const Types = require("./Types")

--// Types
export type Locale = Types.Locale

--// Constants
const DEFAULT_STRINGS: { [string]: string } = {
	-- Resolution
	["resolve.emptyCommand"] = "Expected a command",
	["resolve.unknownCommand"] = "Unknown command '{name}'",
	["resolve.unknownCommandSuggestion"] = "Unknown command '{name}'. Did you mean '{suggestion}'?",
	["resolve.dynamicCommandName"] = "The command name must be written literally",
	["resolve.missingArgument"] = "Missing argument <{name}: {type}>",
	["resolve.tooManyArguments"] = "Too many arguments (unexpected '{text}')",
	["resolve.unknownFlag"] = "Unknown flag '{flag}'",
	["resolve.unknownFlagSuggestion"] = "Unknown flag '{flag}'. Did you mean '--{suggestion}'?",
	["resolve.flagNeedsValue"] = "Flag --{name} expects a value <{type}>",
	["resolve.flagNoValue"] = "Flag --{name} does not take a value",
	["resolve.duplicateArgument"] = "Argument '{name}' was given twice",
	["resolve.emptyList"] = "'{text}' matched no {plural}",
	["resolve.unknownVariable"] = "Unknown variable ${name}",
	["resolve.unknownFunction"] = "Unknown function ${name}()",
	["resolve.deferred"] = "Resolved when the command runs",
	["resolve.dynamicUnavailable"] = "Fill in the previous arguments first",
	["resolve.pipeMismatch"] = "Cannot pipe {from} into '{command}' (expects {to})",
	["resolve.noPipeArgument"] = "'{command}' does not accept piped input",

	-- Execution
	["run.permissionDenied"] = "You do not have permission to run '{command}'",
	["run.cooldown"] = "'{command}' is on cooldown for {seconds}s",
	["run.rateLimited"] = "You are running '{command}' too often; try again in {seconds}s",
	["run.noImplementation"] = "'{command}' has no implementation on this side",
	["run.clientOnly"] = "'{command}' can only run from a player's console",
	["run.cancelled"] = "Cancelled",
	["run.timeout"] = "'{command}' timed out after {seconds}s",
	["run.error"] = "'{command}' failed: {message}",
	["run.blockedByHook"] = "{message}",
	["run.confirmDestructive"] = "Run '{command}'? This cannot be undone.",
	["run.confirmMany"] = "This affects {count} {plural}. Continue?",
	["run.declined"] = "Declined",
	["run.dryRun"] = "Dry run of '{command}':",
	["run.dryUnsupported"] = "'{command}' does not support --dry",
	["run.executed"] = "Done",
	["run.tooManyCommands"] = "Stopped: more than {count} commands in one run",
	["run.aliasDepth"] = "Stopped: aliases nested more than {count} levels deep",
	["run.syntaxError"] = "Syntax error: {message}",
	["run.notConnected"] = "Not connected to the server yet",
	["run.inputTooLong"] = "Input is too long",

	-- Help
	["help.title"] = "Commands",
	["help.usage"] = "Usage",
	["help.aliases"] = "Aliases",
	["help.group"] = "Group",
	["help.examples"] = "Examples",
	["help.arguments"] = "Arguments",
	["help.subcommands"] = "Subcommands",
	["help.permissions"] = "Permissions",
	["help.deprecated"] = "Deprecated",
	["help.useInstead"] = "Use '{replacement}' instead",
	["help.operators"] = "Operators",
	["help.types"] = "Types",
	["help.tip"] = "Tab completes · ↑↓ history · Ctrl+K palette · Ctrl+R search history · F1 help",
}

--// Locale class
const LocaleClass = {}
LocaleClass.__index = LocaleClass

function LocaleClass.Get(self: Locale, key: string, params: { [string]: string | number }?): string
	const template = self._strings[key] or DEFAULT_STRINGS[key] or key
	if params == nil then
		return template
	end
	return (template:gsub("{(%w+)}", function(name: string): string
		const value = params[name]
		if value == nil then
			return "{" .. name .. "}"
		end
		return tostring(value)
	end))
end

function LocaleClass.Set(self: Locale, overrides: { [string]: string })
	for key, value in overrides do
		self._strings[key] = value
	end
end

table.freeze(LocaleClass)

--// Locale module
const LocaleModule = {}

--- Creates a locale with optional overrides.
function LocaleModule.new(overrides: { [string]: string }?): Locale
	const locale: Locale = setmetatable({ _strings = {} }, LocaleClass)
	if overrides then
		locale:Set(overrides)
	end
	return locale
end

--- The built-in English strings (read-only), for translators.
LocaleModule.Defaults = table.freeze(table.clone(DEFAULT_STRINGS))

return table.freeze(LocaleModule)
