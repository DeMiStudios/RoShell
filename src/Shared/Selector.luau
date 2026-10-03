--!strict
--[[
	The operator/wildcard engine for enumerable types (players, teams, items, enums, instances...).

	Scalar arguments accept:  literal, `.`/`me`, `?`, `~fuzzy`, globs (`Bo*`, `B?b`, `[a-m]*`), prefix
	selectors (`%Team`, `#Tag`, `@role:Admin`), and `/pattern/` when the type allows it.
	List arguments also accept: `*`, `**`, `?N`, `a,b`, `a+b` (union), `a-b` (difference), `a&b`
	(intersection), `!a` (complement) and parentheses. `&` binds tighter than `+`, `-` and `,`.

	Resolution is deterministic: results keep the candidate enumeration order (except `?`, which is random by
	design). A comma separated piece that exactly names a candidate is always taken literally, so names that
	contain operator characters (`sword-of-embers`) still work; quoting disables operators entirely.
]]

--// Imports
const Fuzzy = require("./Fuzzy")
const ShellDirectory = require("./ShellDirectory")
const Types = require("./Types")
const Util = require("./Util")

--// Types
type Candidate<T> = Types.Candidate<T>
type ParseResult<T> = Types.ParseResult<T>

export type Options<T> = {
	--- Singular and plural nouns for messages ("player" / "players").
	Noun: string,
	Plural: string,
	Candidates: { read Candidate<T> },
	--- The executor's own value (`.`, `me`, and the exclusion for `**`).
	Default: ((request: Types.ParseRequest) -> T?)?,
	Selectors: { read Types.Selector<T> }?,
	--- Allows `/luau pattern/` atoms.
	AllowPatterns: boolean?,
	CaseSensitive: boolean?,
	--- Type identity, for selectors registered on the registry (`@name:arg`).
	TypeId: number?,
}

type Set = { [number]: true }

type Index = {
	--- Normalized key/alias -> candidate index (first wins).
	Exact: { [string]: number },
	Keys: { string },
	Lower: { string },
}

--// Constants
const FUZZY_LIST_RATIO = 0.6
const MAX_RANDOM = 1000
const OPERATOR_CHARS: { [string]: true } = { [","] = true, ["+"] = true, ["-"] = true, ["&"] = true }

--// Globals
-- Index cache keyed by candidate list identity (types with cached candidate lists reuse their index).
const indexCache: { [{ read unknown }]: Index } = setmetatable({}, { __mode = "k" })

--// Helpers

const function normalize(text: string, caseSensitive: boolean?): string
	return if caseSensitive then text else text:lower()
end

const function buildIndex<T>(candidates: { read Candidate<T> }, caseSensitive: boolean?): Index
	const cached = indexCache[candidates]
	if cached then
		return cached
	end
	const index: Index = { Exact = {}, Keys = {}, Lower = {} }
	for position, candidate in candidates do
		index.Keys[position] = candidate.Key
		index.Lower[position] = normalize(candidate.Key, caseSensitive)
		const key = index.Lower[position]
		if index.Exact[key] == nil then
			index.Exact[key] = position
		end
	end
	-- Aliases never shadow keys.
	for position, candidate in candidates do
		if candidate.Aliases then
			for _, alias in candidate.Aliases do
				const key = normalize(alias, caseSensitive)
				if index.Exact[key] == nil then
					index.Exact[key] = position
				end
			end
		end
	end
	indexCache[candidates] = index
	return index
end

--- True when `text` contains glob syntax (and is not one of the bare operators `*`, `**`, `?`, `?N`).
const function isGlob(text: string): boolean
	if text == "*" or text == "**" or text == "?" or text:match("^%?%d+$") then
		return false
	end
	return text:find("[%*%?%[]") ~= nil
end

--- Converts a glob into an anchored Luau pattern.
const function globToPattern(glob: string): string
	const out: { string } = { "^" }
	local position = 1
	while position <= #glob do
		const char = glob:sub(position, position)
		if char == "*" then
			table.insert(out, ".*")
		elseif char == "?" then
			table.insert(out, ".")
		elseif char == "[" then
			const closing = glob:find("]", position + 1, true)
			if closing then
				local class = glob:sub(position + 1, closing - 1)
				if class:sub(1, 1) == "!" then
					class = "^" .. class:sub(2)
				end
				table.insert(out, "[" .. class:gsub("%%", "%%%%") .. "]")
				position = closing
			else
				table.insert(out, "%[")
			end
		elseif char:match("[%^%$%(%)%%%.%+%-%]]") then
			table.insert(out, "%" .. char)
		else
			table.insert(out, char)
		end
		position += 1
	end
	table.insert(out, "$")
	return table.concat(out)
end

const function setToList<T>(set: Set, candidates: { read Candidate<T> }): { T }
	const values: { T } = {}
	for position, candidate in candidates do
		if set[position] then
			table.insert(values, candidate.Value)
		end
	end
	return values
end

const function setSize(set: Set): number
	local count = 0
	for _ in set do
		count += 1
	end
	return count
end

const function displayOf<T>(set: Set, candidates: { read Candidate<T> }): string
	const names: { string } = {}
	for position, candidate in candidates do
		if set[position] then
			table.insert(names, candidate.Key)
		end
	end
	if #names == 0 then
		return "nothing"
	end
	if #names > 6 then
		return table.concat(names, ", ", 1, 5) .. ` (+{#names - 5} more)`
	end
	return table.concat(names, ", ")
end

const function namesOf<T>(set: Set, candidates: { read Candidate<T> }, limit: number): string
	const names: { string } = {}
	for position, candidate in candidates do
		if set[position] then
			table.insert(names, candidate.Key)
			if #names >= limit then
				break
			end
		end
	end
	return table.concat(names, ", ")
end

--- Finds the selector whose prefix starts `text` (longest prefix wins), including registry selectors.
const function findSelector<T>(text: string, options: Options<T>, request: Types.ParseRequest | Types.CompleteRequest): (Types.Selector<T>?, Types.Selector<unknown>?)
	local best: Types.Selector<T>? = nil
	if options.Selectors then
		for _, selector in options.Selectors do
			if text:sub(1, #selector.Prefix) == selector.Prefix and (best == nil or #selector.Prefix > #best.Prefix) then
				best = selector
			end
		end
	end
	if best then
		return best, nil
	end
	-- Registry selectors (`@name:`) attach to a type by id.
	if options.TypeId and text:sub(1, 1) == "@" then
		const shell = ShellDirectory.Get(request.Shell)
		if shell then
			const registered = shell.Registry:GetSelectors(options.TypeId)
			for _, selector in registered do
				if text:sub(1, #selector.Prefix) == selector.Prefix then
					return nil, selector
				end
			end
		end
	end
	return nil, nil
end

const function subRequest(request: Types.ParseRequest, text: string, offset: number): Types.ParseRequest
	return {
		Text = text,
		Quoted = request.Quoted,
		Span = { Start = request.Span.Start + offset, End = request.Span.Start + offset + #text },
		Executor = request.Executor,
		Shell = request.Shell,
		Platform = request.Platform,
		Final = request.Final,
		ArgName = request.ArgName,
	}
end

--// Atom resolution (shared by scalar and list modes)

type AtomResult = { Ok: true, Set: Set } | { Ok: false, Error: string }

const function resolveLiteral<T>(text: string, options: Options<T>, index: Index, listMode: boolean): AtomResult
	const key = normalize(text, options.CaseSensitive)
	const exact = index.Exact[key]
	if exact then
		return { Ok = true, Set = { [exact] = true } }
	end
	-- Unique prefix match.
	const matches: Set = {}
	local count = 0
	for position, lower in index.Lower do
		if lower:sub(1, #key) == key and not options.Candidates[position].Hidden then
			matches[position] = true
			count += 1
		end
	end
	if count == 1 then
		return { Ok = true, Set = matches }
	elseif count > 1 then
		return {
			Ok = false,
			Error = `'{text}' is ambiguous: {namesOf(matches, options.Candidates, 4)}{if count > 4
				then ` (+{count - 4} more)`
				else ""}`,
		}
	end
	const suggestion = Fuzzy.Suggest(text, index.Keys)
	if suggestion then
		return { Ok = false, Error = `Unknown {options.Noun} '{text}'. Did you mean '{suggestion}'?` }
	end
	return { Ok = false, Error = `Unknown {options.Noun} '{text}'.` }
end

--- `single`: the atom fills a single-value argument, so `~fuzzy` picks the best match instead of every strong one.
const function resolveAtom<T>(
	request: Types.ParseRequest,
	atom: string,
	offset: number,
	options: Options<T>,
	index: Index,
	single: boolean?
): AtomResult
	const candidates = options.Candidates
	const lowered = atom:lower()

	-- An exact name always wins over operator interpretations.
	const exact = index.Exact[normalize(atom, options.CaseSensitive)]
	if exact then
		return { Ok = true, Set = { [exact] = true } }
	end

	if atom == "*" then
		const all: Set = {}
		for position, candidate in candidates do
			if not candidate.Hidden then
				all[position] = true
			end
		end
		return { Ok = true, Set = all }
	elseif atom == "**" or atom == "." or lowered == "me" or lowered == "@me" then
		const default = if options.Default then options.Default(request) else nil
		if atom ~= "**" then
			if default == nil then
				return { Ok = false, Error = `'{atom}' has no meaning for {options.Plural} here` }
			end
			for position, candidate in candidates do
				if candidate.Value == default then
					return { Ok = true, Set = { [position] = true } }
				end
			end
			return { Ok = false, Error = `You are not a valid {options.Noun}` }
		end
		const others: Set = {}
		for position, candidate in candidates do
			if not candidate.Hidden and (default == nil or candidate.Value ~= default) then
				others[position] = true
			end
		end
		return { Ok = true, Set = others }
	elseif atom == "?" or atom:match("^%?%d+$") then
		const wanted = math.min(tonumber(atom:sub(2)) or 1, MAX_RANDOM)
		const pool: { number } = {}
		for position, candidate in candidates do
			if not candidate.Hidden then
				table.insert(pool, position)
			end
		end
		const picked: Set = {}
		for _ = 1, math.min(wanted, #pool) do
			const choice = request.Platform.Random(1, #pool)
			picked[pool[choice]] = true
			pool[choice] = pool[#pool]
			pool[#pool] = nil
		end
		return { Ok = true, Set = picked }
	elseif atom:sub(1, 1) == "~" then
		const query = atom:sub(2)
		if query == "" then
			return { Ok = false, Error = "Expected a search term after '~'" }
		end
		const positions: { number } = {}
		for position in candidates do
			table.insert(positions, position)
		end
		const ranked = Fuzzy.Filter(
			query,
			positions,
			function(position: number): string
				return index.Keys[position]
			end,
			#positions
		)
		if #ranked == 0 then
			return { Ok = false, Error = `No {options.Noun} matches '~{query}'` }
		end
		const set: Set = {}
		if single then
			set[ranked[1].Item] = true
			return { Ok = true, Set = set }
		end
		const threshold = if ranked[1].Score > 0 then ranked[1].Score * FUZZY_LIST_RATIO else ranked[1].Score
		for rank, result in ranked do
			if rank == 1 or result.Score >= threshold then
				set[result.Item] = true
			end
		end
		return { Ok = true, Set = set }
	elseif options.AllowPatterns and #atom >= 2 and atom:sub(1, 1) == "/" and atom:sub(-1) == "/" then
		const pattern = atom:sub(2, -2)
		const set: Set = {}
		for position, key in index.Keys do
			const ok, found = pcall(function(): number?
				return (key:find(pattern))
			end)
			if not ok then
				return { Ok = false, Error = `Invalid pattern: {found}` }
			end
			if found then
				set[position] = true
			end
		end
		return { Ok = true, Set = set }
	end

	-- Prefix selectors (`%Team`, `#Tag`, `@role:x`).
	const selector, registered = findSelector(atom, options, request)
	local values: { read unknown }? = nil
	if selector then
		const inner = subRequest(request, atom:sub(#selector.Prefix + 1), offset + #selector.Prefix)
		const result = selector.Resolve(inner)
		if not result.Ok then
			return { Ok = false, Error = result.Error }
		end
		values = result.Value
	elseif registered then
		const inner = subRequest(request, atom:sub(#registered.Prefix + 1), offset + #registered.Prefix)
		const result = registered.Resolve(inner)
		if not result.Ok then
			return { Ok = false, Error = result.Error }
		end
		values = result.Value
	end
	if values then
		-- Map values back to candidates by identity so only real candidates (with their typed values) remain.
		const set: Set = {}
		for _, value in values do
			for position, candidate in candidates do
				if candidate.Value == value then
					set[position] = true
				end
			end
		end
		return { Ok = true, Set = set }
	end

	if isGlob(atom) then
		const pattern = globToPattern(normalize(atom, options.CaseSensitive))
		const set: Set = {}
		for position, lower in index.Lower do
			if lower:find(pattern) and not candidates[position].Hidden then
				set[position] = true
			end
		end
		return { Ok = true, Set = set }
	end

	return resolveLiteral(atom, options, index, true)
end

--// List expression parser

type ExprToken = {
	Kind: "atom" | "+" | "-" | "&" | "!" | "(" | ")",
	Text: string,
	Start: number,
}

const function tokenizeExpression(text: string): { ExprToken }
	const tokens: { ExprToken } = {}
	local position = 1
	const length = #text
	while position <= length do
		const char = text:sub(position, position)
		if char == "+" or char == "-" or char == "&" or char == "(" or char == ")" then
			tokens[#tokens + 1] = { Kind = char, Text = char, Start = position }
			position += 1
		elseif char == "!" and (#tokens == 0 or tokens[#tokens].Kind ~= "atom") then
			tokens[#tokens + 1] = { Kind = "!", Text = "!", Start = position }
			position += 1
		else
			-- Atom: up to the next operator, honoring [...] classes and /.../ patterns.
			const start = position
			local inClass = false
			local inPattern = char == "/"
			if inPattern then
				position += 1
			end
			while position <= length do
				const current = text:sub(position, position)
				if inPattern then
					if current == "/" then
						position += 1
						break
					end
				elseif inClass then
					if current == "]" then
						inClass = false
					end
				elseif current == "[" then
					inClass = true
				elseif current == "+" or current == "-" or current == "&" or current == "(" or current == ")" then
					break
				end
				position += 1
			end
			tokens[#tokens + 1] = { Kind = "atom", Text = text:sub(start, position - 1), Start = start }
		end
	end
	return tokens
end

--- Splits on top-level commas (not inside [...] classes, /.../ patterns or parentheses).
const function splitPieces(text: string): { { Text: string, Start: number } }
	const pieces: { { Text: string, Start: number } } = {}
	local depth = 0
	local inClass = false
	local inPattern = false
	local start = 1
	for position = 1, #text do
		const char = text:sub(position, position)
		if inPattern then
			if char == "/" then
				inPattern = false
			end
		elseif inClass then
			if char == "]" then
				inClass = false
			end
		elseif char == "[" then
			inClass = true
		elseif char == "/" and (position == start) then
			inPattern = true
		elseif char == "(" then
			depth += 1
		elseif char == ")" then
			depth = math.max(0, depth - 1)
		elseif char == "," and depth == 0 then
			table.insert(pieces, { Text = text:sub(start, position - 1), Start = start })
			start = position + 1
		end
	end
	table.insert(pieces, { Text = text:sub(start), Start = start })
	return pieces
end

type Evaluation = { Ok: true, Set: Set, Position: number } | { Ok: false, Error: string, Position: number }

const function evaluatePiece<T>(
	request: Types.ParseRequest,
	piece: string,
	pieceStart: number,
	options: Options<T>,
	index: Index
): Evaluation
	const tokens = tokenizeExpression(piece)
	local cursor = 1
	const universeSize = #options.Candidates

	local parseUnion: () -> Evaluation

	const function fail(message: string, at: number): Evaluation
		return { Ok = false, Error = message, Position = pieceStart + at - 1 }
	end

	const function parseUnary(): Evaluation
		const token = tokens[cursor]
		if token == nil then
			return fail(`Expected a {options.Noun}`, #piece + 1)
		end
		if token.Kind == "!" then
			cursor += 1
			const inner = parseUnary()
			if not inner.Ok then
				return inner
			end
			const innerSet = inner.Set
			const complement: Set = {}
			for position = 1, universeSize do
				if not innerSet[position] and not options.Candidates[position].Hidden then
					complement[position] = true
				end
			end
			return { Ok = true, Set = complement, Position = inner.Position }
		elseif token.Kind == "(" then
			cursor += 1
			const inner = parseUnion()
			if not inner.Ok then
				return inner
			end
			const closing = tokens[cursor]
			if closing == nil or closing.Kind ~= ")" then
				return fail("Expected ')'", if closing then closing.Start else #piece + 1)
			end
			cursor += 1
			return inner
		elseif token.Kind == "atom" then
			cursor += 1
			const result = resolveAtom(request, token.Text, pieceStart + token.Start - 2, options, index)
			if not result.Ok then
				return fail(result.Error, token.Start)
			end
			return { Ok = true, Set = result.Set, Position = pieceStart + token.Start + #token.Text - 1 }
		end
		return fail(`Expected a {options.Noun} before '{token.Text}'`, token.Start)
	end

	const function parseIntersection(): Evaluation
		local left = parseUnary()
		while left.Ok do
			const token = tokens[cursor]
			if token == nil or token.Kind ~= "&" then
				break
			end
			cursor += 1
			const right = parseUnary()
			if not right.Ok then
				return right
			end
			const result: Set = {}
			for position in left.Set do
				if right.Set[position] then
					result[position] = true
				end
			end
			left = { Ok = true, Set = result, Position = right.Position }
		end
		return left
	end

	parseUnion = function(): Evaluation
		local left = parseIntersection()
		while left.Ok do
			const token = tokens[cursor]
			if token == nil or (token.Kind ~= "+" and token.Kind ~= "-") then
				break
			end
			cursor += 1
			const right = parseIntersection()
			if not right.Ok then
				return right
			end
			const result: Set = table.clone(left.Set)
			if token.Kind == "+" then
				for position in right.Set do
					result[position] = true
				end
			else
				for position in right.Set do
					result[position] = nil
				end
			end
			left = { Ok = true, Set = result, Position = right.Position }
		end
		return left
	end

	const result = parseUnion()
	if result.Ok and tokens[cursor] ~= nil then
		const stray = tokens[cursor]
		return fail(`Unexpected '{stray.Text}'`, stray.Start)
	end
	return result
end

--// Selector
const Selector = {}

--- Built-in operators, for help and completion.
Selector.Operators = table.freeze(
	{
		{ Symbol = "*", Name = "all", Description = "Every value", Example = "kick *", Scalar = false, List = true },
		{
			Symbol = "**",
			Name = "others",
			Description = "Everyone except you",
			Example = "kill **",
			Scalar = false,
			List = true,
		},
		{
			Symbol = ".",
			Name = "me",
			Description = "Yourself (also `me`)",
			Example = "bring .",
			Scalar = true,
			List = true,
		},
		{
			Symbol = "?",
			Name = "random",
			Description = "A random value; `?3` picks three",
			Example = "tp ? .",
			Scalar = true,
			List = true,
		},
		{
			Symbol = "~",
			Name = "fuzzy",
			Description = "Best fuzzy match(es)",
			Example = "give ~swrd",
			Scalar = true,
			List = true,
		},
		{
			Symbol = "a*",
			Name = "glob",
			Description = "Wildcards: `*` any run, `?` one char, `[a-m]` classes",
			Example = "kick Guest*",
			Scalar = true,
			List = true,
		},
		{
			Symbol = ",",
			Name = "list",
			Description = "Several values",
			Example = "heal Bob,Alice",
			Scalar = false,
			List = true,
		},
		{
			Symbol = "+",
			Name = "union",
			Description = "Values in either side",
			Example = "heal %Red+%Blue",
			Scalar = false,
			List = true,
		},
		{
			Symbol = "-",
			Name = "difference",
			Description = "Values in the left side but not the right",
			Example = "kick *-Bob",
			Scalar = false,
			List = true,
		},
		{
			Symbol = "&",
			Name = "intersection",
			Description = "Values in both sides",
			Example = "heal %Red&%Admins",
			Scalar = false,
			List = true,
		},
		{
			Symbol = "!",
			Name = "not",
			Description = "Every value except these",
			Example = "kill !%Red",
			Scalar = false,
			List = true,
		},
		{
			Symbol = "( )",
			Name = "group",
			Description = "Groups an expression",
			Example = "kick (*-%Red)&Guest*",
			Scalar = false,
			List = true,
		},
	} :: { Types.OperatorInfo }
)

--- The operators for a single-value or list argument. `.` and `**` mean "you", so they are left out for types
--- without a Default (the executor's own value).
function Selector.OperatorsFor(list: boolean, hasDefault: boolean): { Types.OperatorInfo }
	const operators: { Types.OperatorInfo } = {}
	for _, operator in Selector.Operators do
		if (if list then operator.List else operator.Scalar)
			and (hasDefault or (operator.Symbol ~= "." and operator.Symbol ~= "**")) then
			table.insert(operators, operator)
		end
	end
	return operators
end

Selector.GlobToPattern = globToPattern
Selector.IsGlob = isGlob

--- Resolves a single value.
function Selector.ResolveOne<T>(request: Types.ParseRequest, options: Options<T>): ParseResult<T>
	const text = request.Text
	const candidates = options.Candidates
	if text == "" then
		return { Ok = false, Error = `Expected a {options.Noun}`, Span = request.Span, Progress = 0 }
	end
	const index = buildIndex(candidates, options.CaseSensitive)
	local atom: AtomResult
	if request.Quoted then
		atom = resolveLiteral(text, options, index, false)
	elseif text == "*" or text == "**" or text:match("^%?%d+$") then
		return {
			Ok = false,
			Error = `'{text}' selects several {options.Plural}, but only one {options.Noun} is expected here`,
			Span = request.Span,
			Progress = 0,
		}
	else
		atom = resolveAtom(request, text, 0, options, index, true)
	end
	if not atom.Ok then
		return { Ok = false, Error = atom.Error, Span = request.Span, Progress = 0 }
	end
	const set = atom.Set
	const size = setSize(set)
	if size == 0 then
		return { Ok = false, Error = `'{text}' matched no {options.Plural}`, Span = request.Span, Progress = 0 }
	elseif size > 1 then
		return {
			Ok = false,
			Error = `'{text}' matches {size} {options.Plural} ({namesOf(set, candidates, 4)}{if size > 4
				then ", …"
				else ""}); expected one`,
			Span = request.Span,
			Progress = 0,
		}
	end
	for position, candidate in candidates do
		if set[position] then
			return { Ok = true, Value = candidate.Value, Display = candidate.Key }
		end
	end
	return { Ok = false, Error = `Expected a {options.Noun}`, Span = request.Span, Progress = 0 }
end

--- Resolves a list expression.
function Selector.ResolveMany<T>(request: Types.ParseRequest, options: Options<T>): ParseResult<{ T }>
	const text = request.Text
	const candidates = options.Candidates
	const index = buildIndex(candidates, options.CaseSensitive)
	if request.Quoted then
		const atom = resolveLiteral(text, options, index, false)
		if not atom.Ok then
			return { Ok = false, Error = atom.Error, Span = request.Span, Progress = 0 }
		end
		return { Ok = true, Value = setToList(atom.Set, candidates), Display = displayOf(atom.Set, candidates) }
	end
	if text == "" then
		return { Ok = false, Error = `Expected {options.Plural}`, Span = request.Span, Progress = 0 }
	end

	const total: Set = {}
	for _, piece in splitPieces(text) do
		if piece.Text == "" then
			return {
				Ok = false,
				Error = `Expected a {options.Noun} after ','`,
				Span = { Start = request.Span.Start + piece.Start - 1, End = request.Span.Start + piece.Start - 1 },
				Progress = piece.Start - 1,
			}
		end
		const literal = index.Exact[normalize(piece.Text, options.CaseSensitive)]
		if literal then
			total[literal] = true
		else
			const evaluation = evaluatePiece(request, piece.Text, piece.Start, options, index)
			if not evaluation.Ok then
				return {
					Ok = false,
					Error = evaluation.Error,
					Span = {
						Start = request.Span.Start + piece.Start - 1,
						End = request.Span.Start + piece.Start - 1 + #piece.Text,
					},
					Progress = evaluation.Position,
				}
			end
			for position in evaluation.Set do
				total[position] = true
			end
		end
	end
	return { Ok = true, Value = setToList(total, candidates), Display = displayOf(total, candidates) }
end

--- Splits list-mode text into the part before the segment being typed and the segment itself.
function Selector.SplitLastSegment(text: string): (string, string)
	local depthClass = false
	local lastOperator = 0
	for position = 1, #text do
		const char = text:sub(position, position)
		if depthClass then
			if char == "]" then
				depthClass = false
			end
		elseif char == "[" then
			depthClass = true
		elseif OPERATOR_CHARS[char] or char == "(" or char == ")" or char == "!" then
			lastOperator = position
		end
	end
	return text:sub(1, lastOperator), text:sub(lastOperator + 1)
end

--- Completion for enumerable values. `Text` of each suggestion is the raw (unescaped) full argument value.
function Selector.Complete<T>(request: Types.CompleteRequest, options: Options<T>, listMode: boolean): { Types.Suggestion }
	const text = request.Text
	local head, segment = "", text
	if listMode then
		head, segment = Selector.SplitLastSegment(text)
	end
	const suggestions: { Types.Suggestion } = {}
	const candidates = options.Candidates
	const index = buildIndex(candidates, options.CaseSensitive)

	-- Values already chosen earlier in the list are not suggested again.
	const chosen: { [string]: true } = {}
	if listMode and head ~= "" then
		for _, piece in splitPieces(head) do
			for word in piece.Text:gmatch("[^,+&%-!()]+") do
				chosen[normalize(word, options.CaseSensitive)] = true
			end
		end
	end

	-- Prefix selectors complete their own argument.
	const selector = findSelector(segment, options, request)
	if selector and selector.Complete then
		const inner = selector.Complete({
			Text = segment:sub(#selector.Prefix + 1),
			Quoted = request.Quoted,
			Executor = request.Executor,
			Shell = request.Shell,
			Platform = request.Platform,
			Limit = request.Limit,
			ArgName = request.ArgName,
		})
		for _, suggestion in inner do
			suggestion.Text = head .. selector.Prefix .. suggestion.Text
			suggestion.Display = selector.Prefix .. suggestion.Display
			for _, range in suggestion.MatchRanges do
				range.Start += #selector.Prefix
				range.End += #selector.Prefix
			end
			table.insert(suggestions, suggestion)
		end
		return suggestions
	end

	const query = if segment:sub(1, 1) == "~" then segment:sub(2) else segment
	const visible: { number } = {}
	for position, candidate in candidates do
		if not candidate.Hidden and not chosen[index.Lower[position]] then
			table.insert(visible, position)
		end
	end
	const ranked = Fuzzy.Filter(
		query,
		visible,
		function(position: number): string
			return index.Keys[position]
		end,
		request.Limit
	)
	const seen: { [number]: true } = {}
	for _, result in ranked do
		const candidate = candidates[result.Item]
		seen[result.Item] = true
		table.insert(suggestions, {
			Text = head .. candidate.Key,
			Display = candidate.Key,
			Detail = candidate.Detail,
			Description = candidate.Description,
			Kind = options.Noun,
			Score = result.Score,
			MatchRanges = result.Ranges,
			Icon = candidate.Icon,
		})
	end
	-- Aliases: suggest the canonical key when an alias matches better than nothing.
	if query ~= "" and #suggestions < request.Limit then
		const preparedQuery = Fuzzy.PrepareQuery(query)
		for position, candidate in candidates do
			if not seen[position] and candidate.Aliases and not candidate.Hidden then
				for _, alias in candidate.Aliases do
					const score = Fuzzy.Score(preparedQuery, Fuzzy.PrepareCached(alias))
					if score then
						seen[position] = true
						table.insert(suggestions, {
							Text = head .. candidate.Key,
							Display = candidate.Key,
							Detail = `alias {alias}`,
							Description = candidate.Description,
							Kind = options.Noun,
							Score = score - 50,
							MatchRanges = {},
							Icon = candidate.Icon,
						})
						break
					end
				end
			end
		end
	end

	-- Operators when nothing (or an operator prefix) has been typed.
	if segment == "" or segment:match("^[%*%.%?~%%#@!]") then
		for _, operator in Selector.OperatorsFor(listMode, options.Default ~= nil) do
			const symbol = operator.Symbol
			if #symbol <= 2
				and symbol ~= "a*"
				and symbol ~= "( )"
				and symbol ~= ","
				and symbol ~= "+"
				and symbol ~= "-"
				and symbol ~= "&" then
				if segment == "" or symbol:sub(1, #segment) == segment then
					table.insert(suggestions, {
						Text = head .. symbol,
						Display = symbol,
						Detail = operator.Name,
						Description = operator.Description,
						Kind = "operator",
						Score = -1000,
						MatchRanges = {},
						Partial = symbol == "~" or symbol == "!",
					})
				end
			end
		end
		if options.Selectors then
			for _, prefixSelector in options.Selectors do
				if segment == "" or prefixSelector.Prefix:sub(1, #segment) == segment then
					table.insert(suggestions, {
						Text = head .. prefixSelector.Prefix,
						Display = prefixSelector.Prefix,
						Detail = prefixSelector.Name,
						Description = prefixSelector.Description,
						Kind = "operator",
						Score = -999,
						MatchRanges = {},
						Partial = true,
					})
				end
			end
		end
	end
	return suggestions
end

--- Formats a resolution preview such as "→ 7 players" or "→ Sword of Embers (+2 more)".
function Selector.Preview<T>(values: { T }, options: Options<T>): string
	if #values == 1 then
		for _, candidate in options.Candidates do
			if candidate.Value == values[1] then
				return candidate.Key
			end
		end
		return Util.FormatValue(values[1])
	end
	return `{#values} {if #values == 1 then options.Noun else options.Plural}`
end

return table.freeze(Selector)
