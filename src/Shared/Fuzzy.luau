--!strict
--!native
--[[
	Fuzzy matcher (fzy-style). Scores a query against candidate strings with bonuses for consecutive matches,
	word boundaries, camelCase transitions and prefixes, and penalties for gaps. Returns match ranges for
	highlighting.

	Performance strategy:
	- Candidates are prepared once (`Prepare`, cached by `PrepareCached`): codepoints, lowercase codepoints,
	  per-position bonuses and a character presence bitmask.
	- `Filter` rejects most candidates with the bitmask and a linear subsequence check before running the
	  O(n*m) scoring DP, keeps the best K in a min-heap (never sorting the whole list), and only computes
	  highlight positions for the K survivors.
]]

--// Imports
const Types = require("./Types")

--// Types
export type Prepared = Types.FuzzyPrepared
export type Query = Types.FuzzyQuery
export type Match = Types.FuzzyMatch

export type Scored<T> = { Item: T, Score: number, Ranges: { Types.Span } }

--// Constants
const SCORE_MIN = -math.huge
const SCORE_GAP_LEADING = -0.005
const SCORE_GAP_TRAILING = -0.005
const SCORE_GAP_INNER = -0.01
const SCORE_MATCH_CONSECUTIVE = 1.0
const SCORE_MATCH_SLASH = 0.9
const SCORE_MATCH_WORD = 0.8
const SCORE_MATCH_CAPITAL = 0.7
const SCORE_MATCH_DOT = 0.6

--- Final score scale and bonuses layered on the DP score.
const SCALE = 100
const EXACT_BONUS = 1000
const PREFIX_BONUS = 150
const CASE_EXACT_BONUS = 5
const LENGTH_PENALTY = 0.25

--- Candidates longer than this are not scored (pathological inputs).
const MAX_TARGET_LENGTH = 512
const CACHE_LIMIT = 32768

const BYTE_SLASH = string.byte("/")
const BYTE_BACKSLASH = string.byte("\\")
const BYTE_DASH = string.byte("-")
const BYTE_UNDERSCORE = string.byte("_")
const BYTE_SPACE = string.byte(" ")
const BYTE_DOT = string.byte(".")
const BYTE_COLON = string.byte(":")
const BYTE_LOWER_A = string.byte("a")
const BYTE_LOWER_Z = string.byte("z")
const BYTE_UPPER_A = string.byte("A")
const BYTE_UPPER_Z = string.byte("Z")
const BYTE_ZERO = string.byte("0")
const BYTE_NINE = string.byte("9")

--// Globals
-- Bounded memo of prepared strings. When full, the cache is swapped out wholesale (cheap generational reset).
local prepareCache: { [string]: Prepared } = {}
local prepareCacheSize = 0

--// Helpers

const function lowerCode(code: number): number
	if code >= BYTE_UPPER_A and code <= BYTE_UPPER_Z then
		return code + 32
	end
	return code
end

const function isUpper(code: number): boolean
	return code >= BYTE_UPPER_A and code <= BYTE_UPPER_Z
end

const function isLower(code: number): boolean
	return code >= BYTE_LOWER_A and code <= BYTE_LOWER_Z
end

const function isDigit(code: number): boolean
	return code >= BYTE_ZERO and code <= BYTE_NINE
end

--- Maps a lowercased codepoint to one of 32 presence bits.
const function maskBit(code: number): number
	if code >= BYTE_LOWER_A and code <= BYTE_LOWER_Z then
		return bit32.lshift(1, code - BYTE_LOWER_A)
	elseif code >= BYTE_ZERO and code <= BYTE_NINE then
		return bit32.lshift(1, 26 + (code - BYTE_ZERO) % 3)
	end
	return bit32.lshift(1, 29 + code % 3)
end

const function bonusFor(previous: number?, current: number): number
	if previous == nil then
		return SCORE_MATCH_SLASH
	elseif previous == BYTE_SLASH or previous == BYTE_BACKSLASH then
		return SCORE_MATCH_SLASH
	elseif previous == BYTE_DASH or previous == BYTE_UNDERSCORE or previous == BYTE_SPACE or previous == BYTE_COLON then
		return SCORE_MATCH_WORD
	elseif previous == BYTE_DOT then
		return SCORE_MATCH_DOT
	elseif isLower(previous) and isUpper(current) then
		return SCORE_MATCH_CAPITAL
	elseif not isDigit(previous) and isDigit(current) then
		return SCORE_MATCH_CAPITAL
	end
	return 0
end

const function codesOf(text: string): { number }
	const codes: { number } = {}
	for _, code in utf8.codes(text) do
		table.insert(codes, code)
	end
	return codes
end

--- Linear subsequence check (cheap rejection before the DP).
const function isSubsequence(needle: { read number }, haystack: { read number }, haystackLength: number): boolean
	const needleLength = #needle
	if needleLength == 0 then
		return true
	end
	local index = 1
	local wanted = needle[1]
	for position = 1, haystackLength do
		if haystack[position] == wanted then
			index += 1
			if index > needleLength then
				return true
			end
			wanted = needle[index]
		end
	end
	return false
end

--- fzy score of one term against a target (score only, two-row DP, no allocation beyond the rows).
const function scoreTerm(
	needle: { read number },
	haystack: { read number },
	bonus: { read number },
	length: number,
	rowD: { number },
	rowM: { number },
	prevD: { number },
	prevM: { number }
): number
	const needleLength = #needle
	if needleLength == length then
		-- Same length and a subsequence: identical (modulo case).
		return SCORE_MATCH_CONSECUTIVE * needleLength + SCORE_MATCH_SLASH
	end
	for i = 1, needleLength do
		const wanted = needle[i]
		local previousScore = SCORE_MIN
		const gapScore = if i == needleLength then SCORE_GAP_TRAILING else SCORE_GAP_INNER
		for j = 1, length do
			if haystack[j] == wanted then
				local score = SCORE_MIN
				if i == 1 then
					score = (j - 1) * SCORE_GAP_LEADING + bonus[j]
				elseif j > 1 then
					const fromGap = prevM[j - 1] + bonus[j]
					const fromConsecutive = prevD[j - 1] + SCORE_MATCH_CONSECUTIVE
					score = if fromGap > fromConsecutive then fromGap else fromConsecutive
				end
				rowD[j] = score
				const extended = previousScore + gapScore
				previousScore = if score > extended then score else extended
				rowM[j] = previousScore
			else
				rowD[j] = SCORE_MIN
				previousScore += gapScore
				rowM[j] = previousScore
			end
		end
		-- Swap rows: the current row becomes the previous one.
		for j = 1, length do
			prevD[j] = rowD[j]
			prevM[j] = rowM[j]
		end
	end
	return prevM[length]
end

--- fzy score with highlight positions (full matrices; only used for displayed results).
const function matchTerm(needle: { read number }, haystack: { read number }, bonus: { read number }, length: number): (number, { number })
	const needleLength = #needle
	const positions: { number } = table.create(needleLength, 0)
	if needleLength == length then
		for index = 1, needleLength do
			positions[index] = index
		end
		return SCORE_MATCH_CONSECUTIVE * needleLength + SCORE_MATCH_SLASH, positions
	end

	const matrixD: { { number } } = {}
	const matrixM: { { number } } = {}
	for i = 1, needleLength do
		const rowD: { number } = table.create(length, SCORE_MIN)
		const rowM: { number } = table.create(length, SCORE_MIN)
		matrixD[i] = rowD
		matrixM[i] = rowM
		const wanted = needle[i]
		local previousScore = SCORE_MIN
		const gapScore = if i == needleLength then SCORE_GAP_TRAILING else SCORE_GAP_INNER
		for j = 1, length do
			if haystack[j] == wanted then
				local score = SCORE_MIN
				if i == 1 then
					score = (j - 1) * SCORE_GAP_LEADING + bonus[j]
				elseif j > 1 then
					const fromGap = matrixM[i - 1][j - 1] + bonus[j]
					const fromConsecutive = matrixD[i - 1][j - 1] + SCORE_MATCH_CONSECUTIVE
					score = if fromGap > fromConsecutive then fromGap else fromConsecutive
				end
				rowD[j] = score
				const extended = previousScore + gapScore
				previousScore = if score > extended then score else extended
				rowM[j] = previousScore
			else
				rowD[j] = SCORE_MIN
				previousScore += gapScore
				rowM[j] = previousScore
			end
		end
	end

	-- Backtrack the optimal path.
	local matchRequired = false
	local j = length
	for i = needleLength, 1, -1 do
		while j >= 1 do
			const d = matrixD[i][j]
			if d ~= SCORE_MIN and (matchRequired or d == matrixM[i][j]) then
				matchRequired = i > 1 and j > 1 and matrixM[i][j] == matrixD[i - 1][j - 1] + SCORE_MATCH_CONSECUTIVE
				positions[i] = j
				j -= 1
				break
			end
			j -= 1
		end
	end
	return matrixM[needleLength][length], positions
end

--- Converts sorted codepoint positions into merged byte spans.
const function positionsToRanges(prepared: Prepared, positions: { number }): { Types.Span }
	table.sort(positions)
	const ranges: { Types.Span } = {}
	const offsets = prepared.Offsets
	const textLength = #prepared.Text
	local current: Types.Span? = nil
	local lastPosition = -1
	for _, position in positions do
		if position ~= lastPosition then
			const startByte = offsets[position]
			const endByte = if position < prepared.Length then offsets[position + 1] else textLength + 1
			if current and position == lastPosition + 1 then
				current.End = endByte
			else
				const span: Types.Span = { Start = startByte, End = endByte }
				table.insert(ranges, span)
				current = span
			end
			lastPosition = position
		end
	end
	return ranges
end

--// Fuzzy
const Fuzzy = {}

Fuzzy.MinScore = SCORE_MIN

--- Precomputes search data for a candidate string.
function Fuzzy.Prepare(text: string): Prepared
	const codes: { number } = {}
	const lowerCodes: { number } = {}
	const offsets: { number } = {}
	const bonus: { number } = {}
	local mask = 0
	local previous: number? = nil
	for offset, code in utf8.codes(text) do
		const lowered = lowerCode(code)
		table.insert(codes, code)
		table.insert(lowerCodes, lowered)
		table.insert(offsets, offset)
		table.insert(bonus, bonusFor(previous, code))
		mask = bit32.bor(mask, maskBit(lowered))
		previous = code
	end
	return table.freeze({
		Text = text,
		Codes = codes,
		LowerCodes = lowerCodes,
		Offsets = offsets,
		Bonus = bonus,
		Mask = mask,
		Length = #codes,
	})
end

--- `Prepare` with memoization (bounded).
function Fuzzy.PrepareCached(text: string): Prepared
	const cached = prepareCache[text]
	if cached then
		return cached
	end
	if prepareCacheSize >= CACHE_LIMIT then
		prepareCache = {}
		prepareCacheSize = 0
	end
	const prepared = Fuzzy.Prepare(text)
	prepareCache[text] = prepared
	prepareCacheSize += 1
	return prepared
end

--- Parses a query: whitespace separated terms that must all match, smart case.
function Fuzzy.PrepareQuery(text: string): Query
	const terms: { { number } } = {}
	const lowerTerms: { { number } } = {}
	local mask = 0
	local caseSensitive = false
	for word in text:gmatch("%S+") do
		const codes = codesOf(word)
		const lowered: { number } = table.create(#codes, 0)
		for index, code in codes do
			if isUpper(code) then
				caseSensitive = true
			end
			lowered[index] = lowerCode(code)
			mask = bit32.bor(mask, maskBit(lowered[index]))
		end
		table.insert(terms, codes)
		table.insert(lowerTerms, lowered)
	end
	return table.freeze({
		Text = text,
		Terms = terms,
		LowerTerms = lowerTerms,
		Mask = mask,
		CaseSensitive = caseSensitive,
		Empty = #terms == 0,
	})
end

--// Scratch rows reused across Score calls (no per-candidate allocation).
const scratchD: { number } = {}
const scratchM: { number } = {}
const scratchPrevD: { number } = {}
const scratchPrevM: { number } = {}

--- Scores `prepared` against `query`. Returns nil when it does not match.
function Fuzzy.Score(query: Query, prepared: Prepared): number?
	if query.Empty then
		return 0
	end
	const length = prepared.Length
	if length > MAX_TARGET_LENGTH or bit32.band(query.Mask, prepared.Mask) ~= query.Mask then
		return nil
	end
	const haystack = if query.CaseSensitive then prepared.Codes else prepared.LowerCodes
	const terms = if query.CaseSensitive then query.Terms else query.LowerTerms
	local total = 0
	for _, term in terms do
		if #term > length or not isSubsequence(term, haystack, length) then
			return nil
		end
		total += scoreTerm(term, haystack, prepared.Bonus, length, scratchD, scratchM, scratchPrevD, scratchPrevM)
	end
	return Fuzzy._finalize(query, prepared, total)
end

--- Applies exact/prefix/case/length adjustments on top of the DP score.
function Fuzzy._finalize(query: Query, prepared: Prepared, dpScore: number): number
	local score = dpScore * SCALE - prepared.Length * LENGTH_PENALTY
	if #query.Terms == 1 then
		const term = query.LowerTerms[1]
		const termLength = #term
		local prefix = termLength <= prepared.Length
		if prefix then
			for index = 1, termLength do
				if prepared.LowerCodes[index] ~= term[index] then
					prefix = false
					break
				end
			end
		end
		if prefix then
			score += PREFIX_BONUS
			if termLength == prepared.Length then
				score += EXACT_BONUS
			end
			-- Case-exact prefix ranks above case-insensitive ones.
			const exactCase = query.Terms[1]
			local sameCase = true
			for index = 1, termLength do
				if prepared.Codes[index] ~= exactCase[index] then
					sameCase = false
					break
				end
			end
			if sameCase then
				score += CASE_EXACT_BONUS
			end
		end
	end
	return score
end

--- Scores and returns highlight ranges. Returns nil when it does not match.
function Fuzzy.Match(query: Query, prepared: Prepared): Match?
	if query.Empty then
		return { Score = 0, Ranges = {} }
	end
	const length = prepared.Length
	if length > MAX_TARGET_LENGTH or bit32.band(query.Mask, prepared.Mask) ~= query.Mask then
		return nil
	end
	const haystack = if query.CaseSensitive then prepared.Codes else prepared.LowerCodes
	const terms = if query.CaseSensitive then query.Terms else query.LowerTerms
	local total = 0
	const positions: { number } = {}
	for _, term in terms do
		if #term > length or not isSubsequence(term, haystack, length) then
			return nil
		end
		const score, termPositions = matchTerm(term, haystack, prepared.Bonus, length)
		total += score
		for _, position in termPositions do
			table.insert(positions, position)
		end
	end
	return { Score = Fuzzy._finalize(query, prepared, total), Ranges = positionsToRanges(prepared, positions) }
end

--- Convenience: does `text` fuzzy-match `query`?
function Fuzzy.Matches(query: string, text: string): boolean
	return Fuzzy.Score(Fuzzy.PrepareQuery(query), Fuzzy.PrepareCached(text)) ~= nil
end

--// Top-K heap helpers (min-heap on score; ties broken by shorter then lexicographically smaller text).

type HeapEntry<T> = { Item: T, Score: number, Text: string, Prepared: Prepared }

const function worse<T>(a: HeapEntry<T>, b: HeapEntry<T>): boolean
	if a.Score ~= b.Score then
		return a.Score < b.Score
	end
	if #a.Text ~= #b.Text then
		return #a.Text > #b.Text
	end
	return a.Text > b.Text
end

const function siftUp<T>(heap: { HeapEntry<T> }, index: number)
	local child = index
	while child > 1 do
		const parent = child // 2
		if worse(heap[child], heap[parent]) then
			heap[child], heap[parent] = heap[parent], heap[child]
			child = parent
		else
			return
		end
	end
end

const function siftDown<T>(heap: { HeapEntry<T> }, index: number)
	const size = #heap
	local parent = index
	while true do
		const left = parent * 2
		const right = left + 1
		local smallest = parent
		if left <= size and worse(heap[left], heap[smallest]) then
			smallest = left
		end
		if right <= size and worse(heap[right], heap[smallest]) then
			smallest = right
		end
		if smallest == parent then
			return
		end
		heap[parent], heap[smallest] = heap[smallest], heap[parent]
		parent = smallest
	end
end

--- Scores `items` against `query` and returns the best `limit` matches (best first) with highlight ranges.
--- `getText` returns each item's searchable text.
function Fuzzy.Filter<T>(query: string | Query, items: { T }, getText: (item: T) -> string, limit: number?): { Scored<T> }
	const prepared = if type(query) == "string" then Fuzzy.PrepareQuery(query) else query
	const maximum = limit or 50
	const heap: { HeapEntry<T> } = {}
	if maximum <= 0 then
		return {}
	end
	for _, item in items do
		const text = getText(item)
		const target = Fuzzy.PrepareCached(text)
		const score = Fuzzy.Score(prepared, target)
		if score ~= nil then
			const entry: HeapEntry<T> = { Item = item, Score = score, Text = text, Prepared = target }
			if #heap < maximum then
				table.insert(heap, entry)
				siftUp(heap, #heap)
			elseif worse(heap[1], entry) then
				heap[1] = entry
				siftDown(heap, 1)
			end
		end
	end
	table.sort(
		heap,
		function(a: HeapEntry<T>, b: HeapEntry<T>): boolean
			return worse(b, a)
		end
	)
	const results: { Scored<T> } = {}
	for index, entry in heap do
		const match = Fuzzy.Match(prepared, entry.Prepared)
		results[index] = {
			Item = entry.Item,
			Score = entry.Score,
			Ranges = if match then match.Ranges else {},
		}
	end
	return results
end

--- Returns the closest string to `text` among `options` ("did you mean"), or nil if nothing is close enough.
--- Combines fuzzy matching with edit distance so both abbreviations and typos are caught.
function Fuzzy.Suggest(text: string, options: { string }): string?
	if text == "" or #options == 0 then
		return nil
	end
	const lowered = text:lower()
	local best: string? = nil
	local bestDistance = math.huge
	const threshold = math.max(1, math.floor(#text / 3))
	for _, option in options do
		const distance = Fuzzy._editDistance(lowered, option:lower(), threshold)
		if distance < bestDistance or (distance == bestDistance and best ~= nil and #option < #best) then
			best = option
			bestDistance = distance
		end
	end
	if best ~= nil and bestDistance <= threshold then
		return best
	end
	const ranked = Fuzzy.Filter(
		text,
		options,
		function(option: string): string
			return option
		end,
		1
	)
	if ranked[1] then
		return ranked[1].Item
	end
	return nil
end

--- Optimal string alignment distance, bounded (returns limit + 1 when exceeded).
function Fuzzy._editDistance(a: string, b: string, limit: number): number
	const lengthA = #a
	const lengthB = #b
	if math.abs(lengthA - lengthB) > limit then
		return limit + 1
	end
	local beforePrevious: { number } = table.create(lengthB + 1, 0)
	local previous: { number } = table.create(lengthB + 1, 0)
	local current: { number } = table.create(lengthB + 1, 0)
	for column = 0, lengthB do
		previous[column + 1] = column
	end
	for row = 1, lengthA do
		current[1] = row
		local rowMinimum = row
		const charA = a:byte(row)
		for column = 1, lengthB do
			const charB = b:byte(column)
			const cost = if charA == charB then 0 else 1
			local value = math.min(previous[column + 1] + 1, current[column] + 1, previous[column] + cost)
			-- Transposition (swapped adjacent characters count as one edit).
			if row > 1 and column > 1 and charA == b:byte(column - 1) and a:byte(row - 1) == charB then
				value = math.min(value, beforePrevious[column - 1] + 1)
			end
			current[column + 1] = value
			if value < rowMinimum then
				rowMinimum = value
			end
		end
		if rowMinimum > limit then
			return limit + 1
		end
		beforePrevious, previous, current = previous, current, beforePrevious
	end
	return previous[lengthB + 1]
end

return table.freeze(Fuzzy)
