--!strict
--[[
	Result helpers. `Result<T, E>` is a discriminated union on `Ok`, so `if result.Ok then ... end` narrows it.
]]

--// Imports
const Types = require("./Types")

--// Types
export type Result<T, E> = Types.Result<T, E>
export type ParseResult<T> = Types.ParseResult<T>

--// Result
const Result = {}

--- Creates a successful result.
function Result.Ok<T>(value: T): Types.Ok<T>
	return { Ok = true, Value = value }
end

--- Creates a failed result.
function Result.Err<E>(err: E): Types.Err<E>
	return { Ok = false, Error = err }
end

--- Maps the value of a successful result.
function Result.Map<T, U, E>(result: Result<T, E>, mapper: (value: T) -> U): Result<U, E>
	if result.Ok then
		return { Ok = true, Value = mapper(result.Value) }
	end
	return { Ok = false, Error = result.Error }
end

--- Returns the value of a successful result, or errors with the failure.
function Result.Unwrap<T, E>(result: Result<T, E>): T
	if result.Ok then
		return result.Value
	end
	error(tostring(result.Error), 2)
end

--- Returns the value of a successful result, or `fallback`.
function Result.UnwrapOr<T, E>(result: Result<T, E>, fallback: T): T
	if result.Ok then
		return result.Value
	end
	return fallback
end

--- Runs `callback` in protected mode, capturing errors as a failed result.
function Result.Try<T>(callback: () -> T): Result<T, string>
	const ok, valueOrError = pcall(callback)
	if ok then
		return { Ok = true, Value = valueOrError }
	end
	return { Ok = false, Error = tostring(valueOrError) }
end

--- Successful parse result.
function Result.Parsed<T>(value: T, display: string?): ParseResult<T>
	return { Ok = true, Value = value, Display = display }
end

--- Failed parse result.
function Result.ParseError<T>(message: string, span: Types.Span?, progress: number?): ParseResult<T>
	return { Ok = false, Error = message, Span = span, Progress = progress }
end

return table.freeze(Result)
