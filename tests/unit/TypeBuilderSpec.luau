--!strict
const Fixtures = require("../support/Fixtures")
const Runner = require("../Runner")
const TypeBuilder = require("../../src/Shared/TypeBuilder")
const Types = require("../../src/Shared/Types")

--// Fixtures

const PEOPLE = { "Bob", "Bobby", "Alice", "Alfred", "Carol", "Guest1", "Guest2", "sword-of-embers" }

const function personCandidates(): { Types.Candidate<string> }
	const candidates: { Types.Candidate<string> } = {}
	for _, name in PEOPLE do
		table.insert(candidates, { Key = name, Value = name, Aliases = if name == "Alice" then { "ally" } else nil })
	end
	return candidates
end

const Person = TypeBuilder.Dynamic({
	Name = "person",
	Plural = "people",
	Candidates = personCandidates,
	Default = function(): string?
		return "Bob"
	end,
	Selectors = {
		{
			Prefix = "%",
			Name = "group",
			Description = "People in a group",
			Example = "%guests",
			Resolve = function(request: Types.ParseRequest): Types.ParseResult<{ read string }>
				if request.Text:lower() == "guests" then
					return { Ok = true, Value = { "Guest1", "Guest2" } }
				elseif request.Text:lower() == "al" then
					return { Ok = true, Value = { "Alice", "Alfred" } }
				end
				return { Ok = false, Error = `Unknown group '{request.Text}'` }
			end,
		},
	},
})
const People = TypeBuilder.List(Person, { Name = "people" })

const function sorted(values: { string }): string
	const copy = table.clone(values)
	table.sort(copy)
	return table.concat(copy, ",")
end

return function(t: Runner.Api)
	t.describe("Choice / Map", function()
		const Rarity = TypeBuilder.Choice({ Name = "rarity", Choices = { "common", "rare", "epic", "legendary" } })
		const Difficulty = TypeBuilder.Map({
			Name = "difficulty",
			Entries = {
				{ Key = "easy", Value = 1, Aliases = { "e" }, Description = "Forgiving enemies" },
				{ Key = "normal", Value = 2 },
				{ Key = "hard", Value = 3, Aliases = { "h" } },
			},
		})

		t.it("parses exact, case-insensitive and unique-prefix input", function()
			t.expect(Fixtures.Value(Rarity, "epic")):toBe("epic")
			t.expect(Fixtures.Value(Rarity, "EPIC")):toBe("epic")
			t.expect(Fixtures.Value(Rarity, "leg")):toBe("legendary")
		end)

		t.it("suggests the closest choice on typos", function()
			t.expect(Fixtures.Error(Rarity, "lgendary")):toContain("Did you mean 'legendary'?")
		end)

		t.it("reports ambiguous prefixes", function()
			const Fruit = TypeBuilder.Choice({ Name = "fruit", Choices = { "apple", "apricot", "banana" } })
			t.expect(Fixtures.Error(Fruit, "ap")):toContain("ambiguous")
		end)

		t.it("maps keys and aliases to values", function()
			t.expect(Fixtures.Value(Difficulty, "hard")):toBe(3)
			t.expect(Fixtures.Value(Difficulty, "e")):toBe(1)
		end)

		t.it("completes with fuzzy ranking", function()
			const suggestions = Fixtures.Suggest(Rarity, "lg")
			t.expect(suggestions[1]):toBe("legendary")
		end)
	end)

	t.describe("Numbers", function()
		const Count = TypeBuilder.Integer({ Name = "count", Min = 1, Max = 999 })
		const Speed = TypeBuilder.Number({ Name = "speed", Min = 0 })

		t.it("parses and validates bounds", function()
			t.expect(Fixtures.Value(Count, "5")):toBe(5)
			t.expect(Fixtures.Value(Speed, "2.5")):toBe(2.5)
			t.expect(Fixtures.Error(Count, "0")):toContain("at least 1")
			t.expect(Fixtures.Error(Count, "1.5")):toContain("whole number")
			t.expect(Fixtures.Error(Count, "abc")):toContain("not a whole number")
		end)

		t.it("expands ranges in lists", function()
			const Counts = TypeBuilder.List(Count)
			t.expect(Fixtures.Value(Counts, "1..4")):toEqual({ 1, 2, 3, 4 })
			t.expect(Fixtures.Value(Counts, "16..32/8")):toEqual({ 16, 24, 32 })
			t.expect(Fixtures.Value(Counts, "..3")):toEqual({ 1, 2, 3 })
			t.expect(Fixtures.Value(Counts, "1,5..6,9")):toEqual({ 1, 5, 6, 9 })
			t.expect(Fixtures.Error(Counts, "998..1000")):toContain("at most 999")
		end)

		t.it("parses range values", function()
			const Span = TypeBuilder.Range({ Name = "span", Min = 0, Max = 100 })
			const value = Fixtures.Value(Span, "10..2/2")
			t.expect(value.Min):toBe(2)
			t.expect(value.Max):toBe(10)
			t.expect(value.Step):toBe(2)
			t.expect(Fixtures.Value(Span, "..5").Min):toBe(0)
		end)
	end)

	t.describe("Strings, booleans, patterns", function()
		t.it("validates strings", function()
			const Tag = TypeBuilder.String({ Name = "tag", MaxLength = 4, Pattern = "^%a+$" })
			t.expect(Fixtures.Value(Tag, "abcd")):toBe("abcd")
			t.expect(Fixtures.Error(Tag, "abcde")):toContain("at most 4")
			t.expect(Fixtures.Error(Tag, "ab1")):toContain("expected format")
		end)

		t.it("parses booleans", function()
			const Flag = TypeBuilder.Boolean()
			t.expect(Fixtures.Value(Flag, "yes")):toBe(true)
			t.expect(Fixtures.Value(Flag, "OFF")):toBe(false)
		end)

		t.it("transforms patterns", function()
			const Hex = TypeBuilder.Pattern({
				Name = "hex",
				Pattern = "^#?%x%x%x%x%x%x$",
				Transform = function(text: string): number
					return tonumber(text:gsub("#", ""), 16) :: number
				end,
			})
			t.expect(Fixtures.Value(Hex, "#ff0000")):toBe(0xff0000)
			t.expect(Fixtures.Error(Hex, "#ff00")):toContain("not a valid hex")
		end)
	end)

	t.describe("Composition", function()
		t.it("Optional accepts empty and nil words", function()
			const MaybeCount = TypeBuilder.Optional(TypeBuilder.Integer())
			t.expect(Fixtures.Value(MaybeCount, "none")):toBeNil()
			t.expect(Fixtures.Value(MaybeCount, "4")):toBe(4)
		end)

		t.it("Union tries members in order and reports the furthest error", function()
			const Either = TypeBuilder.Union({ Name = "target", Members = { TypeBuilder.Integer(), Person } })
			t.expect(Fixtures.Value(Either, "12")):toBe(12)
			t.expect(Fixtures.Value(Either, "Carol")):toBe("Carol")
		end)

		t.it("Tuple parses positional members into a record", function()
			const Stack = TypeBuilder.Tuple({
				Name = "stack",
				Members = { { count = TypeBuilder.Integer() }, { item = Person } },
			})
			const result = Stack.Parse(Fixtures.Parse("5 Carol"))
			assert(result.Ok, "expected the tuple to parse")
			t.expect(result.Value.count):toBe(5)
			t.expect(result.Value.item):toBe("Carol")
			t.expect(Fixtures.Error(Stack, "5")):toContain("Expected 2 values")
		end)

		t.it("Struct parses named fields", function()
			const Point = TypeBuilder.Struct({
				Name = "point",
				Fields = { x = TypeBuilder.Number(), y = TypeBuilder.Number() },
			})
			const result = Point.Parse(Fixtures.Parse("x=1,y=2.5"))
			assert(result.Ok, "expected the struct to parse")
			t.expect(result.Value.x):toBe(1)
			t.expect(result.Value.y):toBe(2.5)
			t.expect(Fixtures.Error(Point, "x=1")):toContain("Missing field 'y'")
			t.expect(Fixtures.Error(Point, "x=1,z=3")):toContain("Unknown field 'z'")
		end)

		t.it("Transform maps values", function()
			const Bang = TypeBuilder.Transform({
				From = TypeBuilder.Integer({ Min = 1 }),
				To = function(count: number): string
					return string.rep("!", count)
				end,
			})
			t.expect(Fixtures.Value(Bang, "3")):toBe("!!!")
		end)

		t.it("Refine adds validation", function()
			const Even = TypeBuilder.Refine(TypeBuilder.Integer(), function(value: number): (boolean, string?)
				return value % 2 == 0, "Must be even"
			end)
			t.expect(Fixtures.Value(Even, "4")):toBe(4)
			t.expect(Fixtures.Error(Even, "3")):toBe("Must be even")
		end)
	end)

	t.describe(
		"Selectors (scalar)",
		function()
			t.it("resolves literals, me, fuzzy, globs and selectors", function()
				t.expect(Fixtures.Value(Person, "carol")):toBe("Carol")
				t.expect(Fixtures.Value(Person, "ally")):toBe("Alice")
				t.expect(Fixtures.Value(Person, ".")):toBe("Bob")
				t.expect(Fixtures.Value(Person, "me")):toBe("Bob")
				t.expect(Fixtures.Value(Person, "~crl")):toBe("Carol")
				t.expect(Fixtures.Value(Person, "Car*")):toBe("Carol")
				t.expect(Fixtures.Value(Person, "sword-of-embers")):toBe("sword-of-embers")
			end)

			t.it(
				"rejects multi-value operators and ambiguity",
				function()
					t.expect(Fixtures.Error(Person, "*")):toContain("only one person")
					t.expect(Fixtures.Error(Person, "Guest*")):toContain("matches 2 people")
					t.expect(Fixtures.Error(Person, "Al")):toContain("ambiguous")
					t.expect(Fixtures.Value(Person, "Bobb")):toBe("Bobby") -- unique prefix
					t.expect(Fixtures.Error(Person, "Carl")):toBe("Unknown person 'Carl'. Did you mean 'Carol'?")
				end
			)

			t.it("picks a random value for ?", function()
				const value = Fixtures.Value(Person, "?")
				t.expect(table.find(PEOPLE, value) ~= nil):toBe(true)
			end)
		end
	)

	t.describe("Selectors (lists)", function()
		t.it("supports *, ** and comma lists", function()
			t.expect(#Fixtures.Value(People, "*")):toBe(#PEOPLE)
			t.expect(table.find(Fixtures.Value(People, "**"), "Bob")):toBeNil()
			t.expect(sorted(Fixtures.Value(People, "Carol,Bob"))):toBe("Bob,Carol")
		end)

		t.it("supports set arithmetic with precedence and parentheses", function()
			t.expect(sorted(Fixtures.Value(People, "Guest*+Carol"))):toBe("Carol,Guest1,Guest2")
			t.expect(#Fixtures.Value(People, "*-Bob")):toBe(#PEOPLE - 1)
			t.expect(sorted(Fixtures.Value(People, "%al&A*"))):toBe("Alfred,Alice")
			t.expect(sorted(Fixtures.Value(People, "%guests+%al&Alice"))):toBe("Alice,Guest1,Guest2")
			t.expect(sorted(Fixtures.Value(People, "(%guests+%al)&*1"))):toBe("Guest1")
			t.expect(#Fixtures.Value(People, "!%guests")):toBe(#PEOPLE - 2)
		end)

		t.it("supports character classes and random samples", function()
			t.expect(sorted(Fixtures.Value(People, "[a-b]*"))):toBe("Alfred,Alice,Bob,Bobby")
			t.expect(#Fixtures.Value(People, "?3")):toBe(3)
		end)

		t.it("takes exact names literally even with operator characters", function()
			t.expect(Fixtures.Value(People, "sword-of-embers")):toEqual({ "sword-of-embers" })
			t.expect(sorted(Fixtures.Value(People, "sword-of-embers,Bob"))):toBe("Bob,sword-of-embers")
		end)

		t.it("disables operators for quoted text", function()
			t.expect(Fixtures.Error(People, "*", { Quoted = true })):toContain("Unknown person")
		end)

		t.it("reports errors with positions", function()
			t.expect(Fixtures.Error(People, "Bob,")):toContain("after ','")
			t.expect(Fixtures.Error(People, "Bob+")):toContain("Expected a person")
			t.expect(Fixtures.Error(People, "%nope")):toBe("Unknown group 'nope'")
		end)
	end)

	t.describe("Completion", function()
		t.it("completes the last list segment and skips chosen values", function()
			const suggestions = Fixtures.Suggest(People, "Bob,Bo")
			t.expect(suggestions[1]):toBe("Bob,Bobby")
			t.expect(table.find(suggestions, "Bob,Bob")):toBeNil()
		end)

		t.it("offers operators on empty input", function()
			const suggestions = Fixtures.Suggest(People, "", 100)
			t.expect(table.find(suggestions, "*") ~= nil):toBe(true)
			t.expect(table.find(suggestions, "%") ~= nil):toBe(true)
		end)

		t.it("completes inside selectors", function()
			const Grouped = TypeBuilder.List(
				TypeBuilder.Enumerable({
					Name = "thing",
					Candidates = personCandidates,
					Selectors = {
						{
							Prefix = "%",
							Name = "group",
							Description = "",
							Example = "",
							Complete = function(request: Types.CompleteRequest): { Types.Suggestion }
								return {
									{
										Text = "guests",
										Display = "guests",
										Kind = "group",
										Score = 1,
										MatchRanges = {},
									},
								}
							end,
							Resolve = function(): Types.ParseResult<{ read string }>
								return { Ok = true, Value = {} }
							end,
						},
					},
				})
			)
			t.expect(Fixtures.Suggest(Grouped, "Bob+%g")[1]):toBe("Bob+%guests")
		end)
	end)

	t.describe("Dynamic caching", function()
		t.it("caches candidates and invalidates on demand", function()
			local calls = 0
			const Cached = TypeBuilder.Dynamic({
				Name = "cached",
				CacheSeconds = 10,
				Candidates = function(): { Types.Candidate<string> }
					calls += 1
					return { { Key = "a", Value = "a" } }
				end,
			})
			Fixtures.Value(Cached, "a")
			Fixtures.Value(Cached, "a")
			t.expect(calls):toBe(1)
			Cached.Invalidate()
			Fixtures.Value(Cached, "a")
			t.expect(calls):toBe(2)
			Fixtures.Controller:Advance(11)
			Fixtures.Value(Cached, "a")
			t.expect(calls):toBe(3)
		end)
	end)
end
