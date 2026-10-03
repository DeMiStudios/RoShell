--!strict
--[[
	Deterministic PRNG (xorshift32) so property tests behave identically under the Luau CLI and Roblox.
]]

export type Prng = {
	read NextInteger: (self: Prng, minimum: number, maximum: number) -> number,
	read NextString: (self: Prng, alphabet: string, minimumLength: number, maximumLength: number) -> string,
	read Pick: <T>(self: Prng, items: { T }) -> T,
	_state: number,
}

const Prng = {}
Prng.__index = Prng

function Prng.new(seed: number): Prng
	return setmetatable({ _state = if seed == 0 then 0x9E3779B9 else seed }, Prng)
end

const function step(self: Prng): number
	local x = self._state
	x = bit32.bxor(x, bit32.lshift(x, 13))
	x = bit32.bxor(x, bit32.rshift(x, 17))
	x = bit32.bxor(x, bit32.lshift(x, 5))
	self._state = x
	return x
end

function Prng.NextInteger(self: Prng, minimum: number, maximum: number): number
	return minimum + step(self) % (maximum - minimum + 1)
end

function Prng.NextString(self: Prng, alphabet: string, minimumLength: number, maximumLength: number): string
	const length = self:NextInteger(minimumLength, maximumLength)
	const chars: { string } = {}
	const codes: { string } = {}
	for _, code in utf8.codes(alphabet) do
		table.insert(codes, utf8.char(code))
	end
	for _ = 1, length do
		table.insert(chars, codes[self:NextInteger(1, #codes)])
	end
	return table.concat(chars)
end

function Prng.Pick<T>(self: Prng, items: { T }): T
	return items[self:NextInteger(1, #items)]
end

return table.freeze(Prng)
