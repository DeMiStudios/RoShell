--!strict
--[[
	Minimal test runner (describe / it / expect) that runs both under the standalone Luau runtime (CI) and inside
	Roblox Studio. See DESIGN_NOTES.md for why this is used instead of TestEZ/Jest-Lua.
]]

--// Types
export type Expectation = {
	--- Negates the following assertion: `expect(x):Not():toBe(y)`.
	read Not: (self: Expectation) -> Expectation,
	read toBe: (self: Expectation, expected: unknown) -> (),
	read toEqual: (self: Expectation, expected: unknown) -> (),
	read toBeNil: (self: Expectation) -> (),
	read toBeTruthy: (self: Expectation) -> (),
	read toContain: (self: Expectation, item: unknown) -> (),
	read toHaveLength: (self: Expectation, length: number) -> (),
	read toBeGreaterThan: (self: Expectation, value: number) -> (),
	read toBeLessThan: (self: Expectation, value: number) -> (),
	read toBeCloseTo: (self: Expectation, value: number, epsilon: number?) -> (),
	read toMatch: (self: Expectation, pattern: string) -> (),
	_value: unknown,
	_negated: boolean,
}

export type Api = {
	read describe: (name: string, body: () -> ()) -> (),
	read it: (name: string, body: () -> ()) -> (),
	read skip: (name: string, body: () -> ()) -> (),
	read beforeEach: (body: () -> ()) -> (),
	read expect: (value: unknown) -> Expectation,
	--- Asserts that `callback` errors (optionally with a message containing `pattern`).
	read expectThrows: (callback: () -> (), pattern: string?) -> (),
	--- True when running inside Roblox (tests that need the engine check this).
	read IsRoblox: boolean,
}

export type Spec = { Name: string, Run: (t: Api) -> (), RobloxOnly: boolean? }

export type Failure = { Name: string, Message: string }

export type Summary = {
	Passed: number,
	Failed: number,
	Skipped: number,
	Failures: { Failure },
	Duration: number,
}

export type RunOptions = {
	--- Only tests whose full name contains this text run.
	Filter: string?,
	--- Print each passing test as well.
	Verbose: boolean?,
	Print: ((message: string) -> ())?,
}

type TestCase = { Name: string, Body: () -> (), Skip: boolean, BeforeEach: { () -> () } }

--// Constants
const IS_ROBLOX = typeof(game) == "Instance"

--// Helpers

const function describeValue(value: unknown): string
	if type(value) == "string" then
		return string.format("%q", value)
	elseif type(value) == "table" then
		const parts: { string } = {}
		local count = 0
		for key, item in pairs(value) do
			count += 1
			if count > 12 then
				table.insert(parts, "…")
				break
			end
			table.insert(parts, `[{describeValue(key)}]={describeValue(item)}`)
		end
		table.sort(parts)
		return "{" .. table.concat(parts, ", ") .. "}"
	end
	return tostring(value)
end

const function toDictionary(value: unknown): { [unknown]: unknown }
	const dictionary: { [unknown]: unknown } = {}
	if type(value) == "table" then
		for key, item in pairs(value) do
			dictionary[key] = item
		end
	end
	return dictionary
end

const function deepEqual(a: unknown, b: unknown, depth: number): boolean
	if a == b then
		return true
	end
	if type(a) ~= "table" or type(b) ~= "table" or depth > 20 then
		return false
	end
	const left = toDictionary(a)
	const right = toDictionary(b)
	for key, value in left do
		if not deepEqual(value, right[key], depth + 1) then
			return false
		end
	end
	for key in right do
		if left[key] == nil then
			return false
		end
	end
	return true
end

--// Expectation class
const Expectation = {}
Expectation.__index = Expectation

const function newExpectation(value: unknown, negated: boolean): Expectation
	return setmetatable({ _value = value, _negated = negated }, Expectation)
end

const function check(self: Expectation, passed: boolean, message: string)
	if passed == self._negated then
		error((if self._negated then "expected NOT: " else "expected: ") .. message, 3)
	end
end

function Expectation.Not(self: Expectation): Expectation
	return newExpectation(self._value, not self._negated)
end

function Expectation.toBe(self: Expectation, expected: unknown)
	check(self, self._value == expected, `{describeValue(self._value)} to be {describeValue(expected)}`)
end

function Expectation.toEqual(self: Expectation, expected: unknown)
	check(self, deepEqual(self._value, expected, 0), `{describeValue(self._value)} to equal {describeValue(expected)}`)
end

function Expectation.toBeNil(self: Expectation)
	check(self, self._value == nil, `{describeValue(self._value)} to be nil`)
end

function Expectation.toBeTruthy(self: Expectation)
	check(self, self._value ~= nil and self._value ~= false, `{describeValue(self._value)} to be truthy`)
end

function Expectation.toContain(self: Expectation, item: unknown)
	const value = self._value
	local found = false
	if type(value) == "string" and type(item) == "string" then
		found = value:find(item, 1, true) ~= nil
	elseif type(value) == "table" then
		for _, element in pairs(value) do
			if element == item then
				found = true
				break
			end
		end
	end
	check(self, found, `{describeValue(value)} to contain {describeValue(item)}`)
end

function Expectation.toHaveLength(self: Expectation, length: number)
	const value = self._value
	local actual = -1
	if type(value) == "string" then
		actual = #value
	elseif type(value) == "table" then
		actual = #value
	end
	check(self, actual == length, `length {actual} to be {length}`)
end

function Expectation.toBeGreaterThan(self: Expectation, other: number)
	const value = self._value
	check(self, type(value) == "number" and value > other, `{describeValue(value)} to be > {other}`)
end

function Expectation.toBeLessThan(self: Expectation, other: number)
	const value = self._value
	check(self, type(value) == "number" and value < other, `{describeValue(value)} to be < {other}`)
end

function Expectation.toBeCloseTo(self: Expectation, other: number, epsilon: number?)
	const value = self._value
	check(
		self,
		type(value) == "number" and math.abs(value - other) <= (epsilon or 1e-6),
		`{describeValue(value)} to be close to {other}`
	)
end

function Expectation.toMatch(self: Expectation, pattern: string)
	const value = self._value
	check(self, type(value) == "string" and value:match(pattern) ~= nil, `{describeValue(value)} to match {pattern}`)
end

table.freeze(Expectation)

--// Runner
const Runner = {}

Runner.IsRoblox = IS_ROBLOX

--- Creates an expectation (usable outside of a spec, e.g. in helpers).
function Runner.expect(value: unknown): Expectation
	return newExpectation(value, false)
end

--- Asserts that `callback` errors (optionally with a message containing `pattern`).
function Runner.expectThrows(callback: () -> (), pattern: string?)
	const ok, err = pcall(callback)
	const message = tostring(err)
	if ok then
		error("expected function to throw", 2)
	elseif pattern and not message:find(pattern, 1, true) then
		error(`expected error containing {string.format("%q", pattern)}, got {message}`, 2)
	end
end

--- Runs specs and returns a summary. Errors are captured per test.
function Runner.Run(specs: { Spec }, options: RunOptions?): Summary
	const opts: RunOptions = options or {}
	const output = opts.Print or print
	const started = os.clock()
	const summary: Summary = { Passed = 0, Failed = 0, Skipped = 0, Failures = {}, Duration = 0 }

	for _, spec in specs do
		if spec.RobloxOnly and not IS_ROBLOX then
			summary.Skipped += 1
			continue
		end
		const cases: { TestCase } = {}
		const prefixStack: { string } = { spec.Name }
		const rootHooks: { () -> () } = {}
		const beforeStack: { { () -> () } } = { rootHooks }

		const function currentPrefix(): string
			return table.concat(prefixStack, " › ")
		end
		const function collectBefore(): { () -> () }
			const all: { () -> () } = {}
			for _, level in beforeStack do
				for _, hook in level do
					table.insert(all, hook)
				end
			end
			return all
		end

		const api: Api = {
			describe = function(name: string, body: () -> ())
				const levelHooks: { () -> () } = {}
				table.insert(prefixStack, name)
				table.insert(beforeStack, levelHooks)
				body()
				table.remove(beforeStack)
				table.remove(prefixStack)
			end,
			it = function(name: string, body: () -> ())
				table.insert(cases, {
					Name = currentPrefix() .. " › " .. name,
					Body = body,
					Skip = false,
					BeforeEach = collectBefore(),
				})
			end,
			skip = function(name: string, body: () -> ())
				const noHooks: { () -> () } = {}
				table.insert(cases, { Name = currentPrefix() .. " › " .. name, Body = body, Skip = true, BeforeEach = noHooks })
			end,
			beforeEach = function(body: () -> ())
				table.insert(beforeStack[#beforeStack], body)
			end,
			expect = Runner.expect,
			expectThrows = Runner.expectThrows,
			IsRoblox = IS_ROBLOX,
		}

		const collected, collectError = pcall(spec.Run, api)
		if not collected then
			summary.Failed += 1
			table.insert(summary.Failures, { Name = spec.Name .. " (collection)", Message = tostring(collectError) })
			continue
		end

		for _, case in cases do
			if opts.Filter and not case.Name:find(opts.Filter, 1, true) then
				continue
			end
			if case.Skip then
				summary.Skipped += 1
				continue
			end
			local err = ""
			const ok = xpcall(function()
				for _, hook in case.BeforeEach do
					hook()
				end
				case.Body()
			end, function(message: unknown)
				err = tostring(message) .. "\n" .. debug.traceback(nil, 2)
			end)
			if ok then
				summary.Passed += 1
				if opts.Verbose then
					output("  ✓ " .. case.Name)
				end
			else
				summary.Failed += 1
				table.insert(summary.Failures, { Name = case.Name, Message = tostring(err) })
			end
		end
	end

	summary.Duration = os.clock() - started
	for _, failure in summary.Failures do
		output("  ✗ " .. failure.Name .. "\n    " .. failure.Message:gsub("\n", "\n    "))
	end
	output(
		string.format(
			"%d passed, %d failed, %d skipped (%.2fs)",
			summary.Passed,
			summary.Failed,
			summary.Skipped,
			summary.Duration
		)
	)
	return summary
end

return table.freeze(Runner)
