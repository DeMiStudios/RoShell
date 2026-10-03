--!strict
--[[
	Durations (`90s`, `1h30m`, `2d`, `1.5h`, `1:30`) and timestamps (`now`, `in 5m`, `5m ago`, `today`,
	`tomorrow`, `2026-10-03`, `2026-10-03T12:30`, unix seconds).
]]

--// Imports
const TypeBuilder = require("../TypeBuilder")
const Types = require("../Types")
const Util = require("../Util")

--// Types
type ParseRequest = Types.ParseRequest

--// Constants
const UNIT_SECONDS: { [string]: number } = {
	ms = 0.001,
	s = 1,
	sec = 1,
	secs = 1,
	second = 1,
	seconds = 1,
	m = 60,
	min = 60,
	mins = 60,
	minute = 60,
	minutes = 60,
	h = 3600,
	hr = 3600,
	hrs = 3600,
	hour = 3600,
	hours = 3600,
	d = 86400,
	day = 86400,
	days = 86400,
	w = 604800,
	wk = 604800,
	week = 604800,
	weeks = 604800,
	mo = 2629746,
	month = 2629746,
	months = 2629746,
	y = 31556952,
	yr = 31556952,
	year = 31556952,
	years = 31556952,
}
const UNIT_SUGGESTIONS = { "s", "m", "h", "d", "w" }
const DAY = 86400

--// Helpers

--- Parses a duration in seconds, or returns nil and an error message.
const function parseDuration(text: string): (number?, string?)
	const trimmed = Util.Trim(text):lower()
	if trimmed == "" then
		return nil, "Expected a duration such as 30s, 5m or 1h30m"
	end
	const plain = tonumber(trimmed)
	if plain then
		return plain, nil
	end
	-- Clock form: h:m:s or m:s
	const a, b, c = trimmed:match("^(%d+):(%d%d):?(%d*)$")
	if a and b then
		if c and c ~= "" then
			return tonumber(a) :: number * 3600 + tonumber(b) :: number * 60 + tonumber(c) :: number, nil
		end
		return tonumber(a) :: number * 60 + tonumber(b) :: number, nil
	end
	-- A sequence of <number><unit> pairs, spaces allowed between them: "1h 30m", "1h30m", "1.5h".
	const compact = trimmed:gsub("%s+", "")
	local total = 0
	local position = 1
	while position <= #compact do
		const numberText, unit, nextPosition = compact:match("^([%d%.]+)(%a+)()", position)
		if numberText == nil or unit == nil or type(nextPosition) ~= "number" then
			return nil, `'{text}' is not a duration (try 30s, 5m, 1h30m)`
		end
		const amount = tonumber(numberText)
		const size = UNIT_SECONDS[unit]
		if amount == nil then
			return nil, `'{numberText}' is not a number`
		end
		if size == nil then
			return nil, `Unknown time unit '{unit}' (use s, m, h, d, w, mo or y)`
		end
		total += amount * size
		position = nextPosition
	end
	return total, nil
end

--- Parses a point in time (unix seconds) relative to `now`.
const function parseTimestamp(text: string, now: number): (number?, string?)
	const lowered = Util.Trim(text):lower()
	if lowered == "now" then
		return now, nil
	elseif lowered == "today" then
		return now - now % DAY, nil
	elseif lowered == "tomorrow" then
		return now - now % DAY + DAY, nil
	elseif lowered == "yesterday" then
		return now - now % DAY - DAY, nil
	end
	const future = lowered:match("^in%s+(.+)$")
	if future then
		const seconds, err = parseDuration(future)
		if seconds == nil then
			return nil, err
		end
		return now + seconds, nil
	end
	const past = lowered:match("^(.+)%s+ago$")
	if past then
		const seconds, err = parseDuration(past)
		if seconds == nil then
			return nil, err
		end
		return now - seconds, nil
	end
	const unix = tonumber(lowered)
	if unix then
		return unix, nil
	end
	const year, month, day, rest = lowered:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)(.*)$")
	if year and month and day then
		const hour, minute, second = (rest or ""):match("^[t%s](%d%d):(%d%d):?(%d*)")
		const ok, value = pcall(function(): number
			return DateTime.fromUniversalTime(
				tonumber(year) :: number,
				tonumber(month) :: number,
				tonumber(day) :: number,
				tonumber(hour) or 0,
				tonumber(minute) or 0,
				tonumber(second) or 0
			).UnixTimestamp
		end)
		if ok then
			return value, nil
		end
		return nil, `'{text}' is not a valid date`
	end
	return nil, `'{text}' is not a time (try now, in 5m, 2h ago, tomorrow, 2026-10-03)`
end

const function formatTimestamp(seconds: number): string
	const ok, text = pcall(function(): string
		return DateTime.fromUnixTimestamp(seconds):FormatUniversalTime("YYYY-MM-DD HH:mm:ss", "en-us") .. " UTC"
	end)
	return if ok then text else tostring(seconds)
end

--// Types

const Duration = TypeBuilder.Custom({
	Name = "duration",
	Description = "A duration: 30s, 5m, 1h30m, 2d, 1.5h or 1:30",
	Examples = { "30s", "1h30m", "2d" },
	Parse = function(request: ParseRequest): Types.ParseResult<number>
		const seconds, err = parseDuration(request.Text)
		if seconds == nil then
			return { Ok = false, Error = err or "Invalid duration", Span = request.Span, Progress = 0 }
		end
		if seconds < 0 then
			return { Ok = false, Error = "Durations cannot be negative", Span = request.Span, Progress = 0 }
		end
		return { Ok = true, Value = seconds, Display = Util.FormatDuration(seconds) }
	end,
	Complete = function(request: Types.CompleteRequest): { Types.Suggestion }
		const text = request.Text
		if not text:match("%d$") then
			return {}
		end
		const suggestions: { Types.Suggestion } = {}
		for index, unit in UNIT_SUGGESTIONS do
			table.insert(suggestions, {
				Text = text .. unit,
				Display = text .. unit,
				Detail = Util.FormatDuration((tonumber(text:match("([%d%.]+)$")) or 0) * UNIT_SECONDS[unit]),
				Kind = "value",
				Score = -index,
				MatchRanges = {},
				Partial = true,
			})
		end
		return suggestions
	end,
	Color = "type.number",
	Icon = "time",
})

const Timestamp = TypeBuilder.Custom({
	Name = "timestamp",
	Description = "A point in time: now, in 5m, 2h ago, today, tomorrow, 2026-10-03, 2026-10-03T12:30",
	Examples = { "in 5m", "tomorrow", "2026-12-25" },
	Parse = function(request: ParseRequest): Types.ParseResult<number>
		const seconds, err = parseTimestamp(request.Text, request.Platform.Now())
		if seconds == nil then
			return { Ok = false, Error = err or "Invalid time", Span = request.Span, Progress = 0 }
		end
		return { Ok = true, Value = seconds, Display = formatTimestamp(seconds) }
	end,
	Suggestions = { "now", "today", "tomorrow", "yesterday", "in 5m", "in 1h", "1h ago" },
	Color = "type.number",
	Icon = "time",
})

const TimeTypes = {
	Duration = Duration,
	Durations = TypeBuilder.List(Duration, { Name = "durations" }),
	Timestamp = Timestamp,
	ParseDuration = parseDuration,
}

return table.freeze(TimeTypes)
