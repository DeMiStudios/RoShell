--!strict
--[[
	A small, safe arithmetic evaluator for the `math` command (no `loadstring`): numbers, + - * / // % ^,
	parentheses, unary minus, constants (pi, e, inf) and functions (abs, sqrt, floor, ceil, round, min, max, sin,
	cos, tan, asin, acos, atan, log, exp, clamp, sign).
]]

--// Types
type Token = {
	Kind: "number" | "name" | "op" | "(" | ")" | ",",
	Text: string,
	Value: number?,
}

--// Constants
const CONSTANTS: { [string]: number } = { pi = math.pi, e = math.exp(1), inf = math.huge, tau = math.pi * 2 }
const FUNCTIONS: { [string]: (args: { number }) -> number } = {
	abs = function(args)
		return math.abs(args[1])
	end,
	sqrt = function(args)
		return math.sqrt(args[1])
	end,
	floor = function(args)
		return math.floor(args[1])
	end,
	ceil = function(args)
		return math.ceil(args[1])
	end,
	round = function(args)
		const places = args[2] or 0
		const factor = 10 ^ places
		return math.floor(args[1] * factor + 0.5) / factor
	end,
	min = function(args)
		return math.min(table.unpack(args))
	end,
	max = function(args)
		return math.max(table.unpack(args))
	end,
	sin = function(args)
		return math.sin(args[1])
	end,
	cos = function(args)
		return math.cos(args[1])
	end,
	tan = function(args)
		return math.tan(args[1])
	end,
	asin = function(args)
		return math.asin(args[1])
	end,
	acos = function(args)
		return math.acos(args[1])
	end,
	atan = function(args)
		return if args[2] then math.atan2(args[1], args[2]) else math.atan(args[1])
	end,
	log = function(args)
		return if args[2] then math.log(args[1], args[2]) else math.log(args[1])
	end,
	exp = function(args)
		return math.exp(args[1])
	end,
	clamp = function(args)
		return math.clamp(args[1], args[2], args[3])
	end,
	sign = function(args)
		return math.sign(args[1])
	end,
}
const PRECEDENCE: { [string]: number } = {
	["+"] = 1,
	["-"] = 1,
	["*"] = 2,
	["/"] = 2,
	["//"] = 2,
	["%"] = 2,
	["^"] = 4,
}
const MAX_LENGTH = 1000

--// Helpers

const function tokenize(text: string): ({ Token }?, string?)
	const tokens: { Token } = {}
	local position = 1
	while position <= #text do
		const char = text:sub(position, position)
		if char:match("%s") then
			position += 1
		elseif char:match("[%d%.]") then
			const literal = text:match("^%d*%.?%d+[eE][%+%-]?%d+", position)
				or text:match("^0[xX]%x+", position)
				or text:match("^%d*%.?%d*", position)
				or ""
			const value = tonumber(literal)
			if value == nil then
				return nil, `Invalid number '{literal}'`
			end
			tokens[#tokens + 1] = { Kind = "number", Text = literal, Value = value }
			position += #literal
		elseif char:match("[%a_]") then
			const name = text:match("^[%a_][%w_]*", position) or char
			tokens[#tokens + 1] = { Kind = "name", Text = name:lower() }
			position += #name
		elseif text:sub(position, position + 1) == "//" or text:sub(position, position + 1) == "**" then
			tokens[#tokens + 1] = { Kind = "op", Text = if text:sub(position, position + 1) == "**" then "^" else "//" }
			position += 2
		elseif char:match("[%+%-%*/%%%^]") then
			tokens[#tokens + 1] = { Kind = "op", Text = char }
			position += 1
		elseif char == "(" or char == ")" or char == "," then
			tokens[#tokens + 1] = { Kind = char, Text = char }
			position += 1
		else
			return nil, `Unexpected '{char}'`
		end
	end
	return tokens, nil
end

--// MathEval
const MathEval = {}

--- Evaluates an expression. Returns the number, or nil and an error message.
function MathEval.Evaluate(text: string): (number?, string?)
	if #text > MAX_LENGTH then
		return nil, "Expression is too long"
	end
	const tokens, tokenizeError = tokenize(text)
	if tokens == nil then
		return nil, tokenizeError
	end
	local index = 1
	local failure: string? = nil

	const function peek(): Token?
		return tokens[index]
	end

	local parseExpression: (minimum: number) -> number

	const function parsePrimary(): number
		const token = peek()
		if token == nil then
			failure = failure or "Unexpected end of expression"
			return 0
		end
		index += 1
		if token.Kind == "number" then
			return token.Value or 0
		elseif token.Kind == "op" and (token.Text == "-" or token.Text == "+") then
			const operand = parseExpression(3)
			return if token.Text == "-" then -operand else operand
		elseif token.Kind == "(" then
			const value = parseExpression(1)
			const closing = peek()
			if closing == nil or closing.Kind ~= ")" then
				failure = failure or "Missing ')'"
			else
				index += 1
			end
			return value
		elseif token.Kind == "name" then
			const constant = CONSTANTS[token.Text]
			if constant then
				return constant
			end
			const fn = FUNCTIONS[token.Text]
			if fn == nil then
				failure = failure or `Unknown name '{token.Text}'`
				return 0
			end
			const open = peek()
			if open == nil or open.Kind ~= "(" then
				failure = failure or `Expected '(' after {token.Text}`
				return 0
			end
			index += 1
			const args: { number } = {}
			const close = peek()
			if close and close.Kind == ")" then
				index += 1
			else
				while true do
					table.insert(args, parseExpression(1))
					const separator = peek()
					if separator and separator.Kind == "," then
						index += 1
					elseif separator and separator.Kind == ")" then
						index += 1
						break
					else
						failure = failure or "Expected ',' or ')'"
						break
					end
				end
			end
			if #args == 0 then
				failure = failure or `{token.Text}() needs an argument`
				return 0
			end
			return fn(args)
		end
		failure = failure or `Unexpected '{token.Text}'`
		return 0
	end

	parseExpression = function(minimum: number): number
		local left = parsePrimary()
		while failure == nil do
			const token = peek()
			if token == nil or token.Kind ~= "op" then
				break
			end
			const precedence = PRECEDENCE[token.Text]
			if precedence == nil or precedence < minimum then
				break
			end
			index += 1
			-- `^` is right associative.
			const right = parseExpression(if token.Text == "^" then precedence else precedence + 1)
			if token.Text == "+" then
				left += right
			elseif token.Text == "-" then
				left -= right
			elseif token.Text == "*" then
				left *= right
			elseif token.Text == "/" then
				left /= right
			elseif token.Text == "//" then
				left //= right
			elseif token.Text == "%" then
				left %= right
			else
				left ^= right
			end
		end
		return left
	end

	const value = parseExpression(1)
	if failure == nil and index <= #tokens then
		failure = `Unexpected '{tokens[index].Text}'`
	end
	if failure then
		return nil, failure
	end
	return value, nil
end

return table.freeze(MathEval)
