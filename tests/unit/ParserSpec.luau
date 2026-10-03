--!strict
const Lexer = require("../../src/Shared/Lexer")
const Parser = require("../../src/Shared/Parser")
const Prng = require("../support/Prng")
const Runner = require("../Runner")

--// Helpers

const function kinds(text: string): string
	const out: { string } = {}
	for _, token in Lexer.Tokenize(text).Tokens do
		table.insert(out, token.Kind)
	end
	return table.concat(out, " ")
end

--- Returns the static values of the words of the first command of the first statement.
const function words(text: string): { string }
	const output = Parser.Parse(text)
	const values: { string } = {}
	const statement = output.Script.Statements[1]
	if statement then
		for _, word in statement.Pipelines[1].Commands[1].Words do
			table.insert(values, word.Value)
		end
	end
	return values
end

const function firstWord(text: string): Parser.Word
	return Parser.Parse(text).Script.Statements[1].Pipelines[1].Commands[1].Words[1]
end

const function diagnosticCount(text: string): number
	return #Parser.Parse(text).Diagnostics
end

--// Spec

return function(t: Runner.Api)
	t.describe("Lexer", function()
		t.it("splits bare words and records spans", function()
			const tokens = Lexer.Tokenize("give  Bob 5").Tokens
			t.expect(#tokens):toBe(3)
			t.expect(tokens[1].Start):toBe(1)
			t.expect(tokens[1].End):toBe(5)
			t.expect(tokens[2].Start):toBe(7)
			t.expect(tokens[2].SpaceBefore):toBe(true)
		end)

		t.it("recognizes operators", function()
			t.expect(kinds("a && b || c ; d | e")):toBe("Text And Text Or Text Semicolon Text Pipe Text")
			t.expect(kinds("a&&b")):toBe("Text And Text")
			t.expect(kinds("%Red&%Admins")):toBe("Text")
			t.expect(kinds("a\nb")):toBe("Text Newline Text")
		end)

		t.it("lexes quoted strings with escapes", function()
			t.expect(firstWord([["a \"b\" \\ \n"]]).Value):toBe('a "b" \\ \n')
			t.expect(firstWord([['it\'s']]).Value):toBe("it's")
			t.expect(firstWord([["\u{263A}"]]).Value):toBe("☺")
			t.expect(firstWord('"""raw \\n "quoted" text"""').Value):toBe('raw \\n "quoted" text')
		end)

		t.it("lexes variables", function()
			t.expect(kinds("$name $$ $1 $@ $:r12 $random(1, 10)")):toBe("Variable Variable Variable Variable Variable Variable")
			const tokens = Lexer.Tokenize("$random(1, 10)").Tokens
			t.expect(tokens[1].Value):toBe("random")
			t.expect(tokens[1].Args):toEqual({ "1", "10" })
			t.expect(kinds("cost $ 5")):toBe("Text Text Text")
			t.expect(firstWord("$").Value):toBe("$")
		end)

		t.it("lexes comments only at word starts", function()
			t.expect(kinds("kick bob # rude")):toBe("Text Text Comment")
			t.expect(kinds("tag #Boss")):toBe("Text Text")
			t.expect(kinds("# whole line\nnext")):toBe("Comment Newline Text")
		end)

		t.it("tracks embeds and nesting", function()
			t.expect(kinds("tp ${players ?}")):toBe("Text EmbedOpen Text Text EmbedClose")
			t.expect(kinds("a ${b ${c}}")):toBe("Text EmbedOpen Text EmbedOpen Text EmbedClose EmbedClose")
			t.expect(kinds('"x ${y} z"')):toBe("QuoteOpen QuotedText EmbedOpen Text EmbedClose QuotedText QuoteClose")
		end)

		t.it("backslash escapes outside quotes", function()
			t.expect(words([[a\ b c\|d]])):toEqual({ "a b", "c|d" })
		end)
	end)

	t.describe("Parser", function()
		t.it("parses commands, pipes and chains", function()
			const script = Parser.Parse("players %Red | kick --reason AFK && announce done; echo hi").Script
			t.expect(#script.Statements):toBe(2)
			const chain = script.Statements[1]
			t.expect(#chain.Pipelines):toBe(2)
			t.expect(chain.Operators):toEqual({ "&&" })
			t.expect(#chain.Pipelines[1].Commands):toBe(2)
			t.expect(#chain.Pipelines[1].Commands[2].Words):toBe(3)
		end)

		t.it("joins adjacent parts into one word", function()
			t.expect(words([[say foo"bar baz"qux]])):toEqual({ "say", "foobar bazqux" })
			const word = firstWord([["all quoted"]])
			t.expect(word.Quoted):toBe(true)
			t.expect(word.OpenQuote and word.OpenQuote.Quote):toBe('"')
		end)

		t.it("keeps empty strings as words", function()
			t.expect(words([[echo "" '']])):toEqual({ "echo", "", "" })
		end)

		t.it("parses embeds recursively", function()
			const word = Parser.Parse("tp Bob ${players ? | first}").Script.Statements[1].Pipelines[1].Commands[1].Words[
				3
			]
			t.expect(word.Static):toBe(false)
			const part = word.Parts[1]
			t.expect(part.Kind):toBe("Embed")
			if part.Kind == "Embed" then
				t.expect(part.Terminated):toBe(true)
				t.expect(#part.Script.Statements[1].Pipelines[1].Commands):toBe(2)
			end
			t.expect(Parser.CountCommands(Parser.Parse("a ${b ${c}} | d").Script)):toBe(4)
		end)

		t.it("treats newlines as statement separators", function()
			t.expect(#Parser.Parse("a\nb\n\nc").Script.Statements):toBe(3)
		end)

		t.it("ignores comments", function()
			const script = Parser.Parse("# setup\nkick bob # bye\n").Script
			t.expect(#script.Statements):toBe(1)
			t.expect(#script.Statements[1].Pipelines[1].Commands[1].Words):toBe(2)
		end)
	end)

	t.describe("Error recovery", function()
		t.it("reports trailing and leading operators", function()
			t.expect(diagnosticCount("a &&")):toBe(1)
			t.expect(diagnosticCount("a |")):toBe(1)
			t.expect(diagnosticCount("| b")):toBe(1)
			t.expect(diagnosticCount("a | | b")):toBe(1)
		end)

		t.it("reports unterminated strings but keeps their content", function()
			const output = Parser.Parse([[kick "Bo]])
			t.expect(#output.Diagnostics):toBe(1)
			const word = output.Script.Statements[1].Pipelines[1].Commands[1].Words[2]
			t.expect(word.Value):toBe("Bo")
			t.expect(word.OpenQuote and word.OpenQuote.Terminated):toBe(false)
		end)

		t.it("reports unclosed embeds", function()
			const output = Parser.Parse("tp ${players")
			t.expect(#output.Diagnostics):toBe(1)
			const part = output.Script.Statements[1].Pipelines[1].Commands[1].Words[2].Parts[1]
			t.expect(part.Kind):toBe("Embed")
			if part.Kind == "Embed" then
				t.expect(part.Terminated):toBe(false)
			end
		end)

		t.it("never crashes on random input and keeps spans valid (fuzz)", function()
			const rng = Prng.new(2024)
			const alphabet = "ab $\"'{}|&;#\\\n()@:1 é"
			for _ = 1, 3000 do
				const text = rng:NextString(alphabet, 0, 30)
				const output = Parser.Parse(text)
				local previous = 0
				for _, token in output.Tokens do
					t.expect(token.Start >= previous):toBe(true)
					t.expect(token.End >= token.Start and token.End <= #text + 1):toBe(true)
					previous = token.Start
				end
				for _, diagnostic in output.Diagnostics do
					t.expect(diagnostic.Span.Start >= 1 and diagnostic.Span.End <= #text + 1):toBe(true)
				end
				Parser.ForEachCommand(output.Script, function(command: Parser.CommandNode)
					for _, word in command.Words do
						t.expect(word.Span.Start >= 1 and word.Span.End <= #text + 1):toBe(true)
						t.expect(word.Span.Start <= word.Span.End):toBe(true)
					end
				end)
			end
		end)
	end)
end
