--!strict
--[[
	Project-wide constants. The product name lives here (and only here) so the package can be renamed in one place.
]]

--// Constants
const Constants = {
	--- Product name, used for instance names, log prefixes and default namespaces.
	Name = "RoShell",
	--- Semantic version of the package.
	Version = "0.1.0",
	--- Network protocol version; bumped whenever the remote schema changes.
	ProtocolVersion = 1,

	--- Hard cap on the length of a single submitted command line (bytes).
	MaxInputLength = 8192,
	--- Hard cap on how deeply `${...}` embedded commands may nest.
	MaxEmbedDepth = 8,
	--- Hard cap on the number of commands executed by one script (guards against runaway aliases/macros).
	MaxCommandsPerScript = 256,
	--- Hard cap on alias/macro expansion depth.
	MaxAliasDepth = 16,
	--- Default number of suggestions computed per completion query.
	DefaultSuggestionLimit = 50,
	--- Default per-query completion budget in seconds.
	DefaultCompletionBudget = 0.008,
	--- Default command timeout in seconds (0 = none).
	DefaultTimeout = 60,
}

return table.freeze(Constants)
