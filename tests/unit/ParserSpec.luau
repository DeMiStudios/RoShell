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

	t.describe(
		"Lexer.ToLine",
		function()
			t.it("leaves single lines alone", function()
				for _, text in { "", "echo hi", "a; b && c | d", 'say "x # y"', "tag #Boss # note", [["""raw"""]] } do
					t.expect(Lexer.ToLine(text)):toBe(text)
				end
			end)

			t.it("joins statements with semicolons, dropping blank lines and comments", function()
				t.expect(Lexer.ToLine("echo a\necho b")):toBe("echo a; echo b")
				t.expect(Lexer.ToLine("\r\n\r\necho a\r\n\r\n\r\necho b\r\n")):toBe("echo a; echo b")
				t.expect(Lexer.ToLine("# setup\necho a # first\n\n# done\necho b")):toBe("echo a; echo b")
				t.expect(Lexer.ToLine("echo a;\necho b;")):toBe("echo a; echo b")
			end)

			t.it("turns line continuations and tabs between words into spaces", function()
				t.expect(Lexer.ToLine("announce hello \\\n  world")):toBe("announce hello world")
				t.expect(Lexer.ToLine("kick\tBob\t")):toBe("kick Bob")
			end)

			t.it(
				"escapes line breaks and tabs inside strings",
				function()
					t.expect(Lexer.ToLine('echo "a\nb"')):toBe('echo "a\\nb"')
					t.expect(Lexer.ToLine("echo 'x\ty'")):toBe("echo 'x\\ty'")
					-- A continuation inside quotes produces nothing, and what it separated must stay apart.
					t.expect(Lexer.ToLine('announce "restarting \\\nin 5"')):toBe('announce "restarting in 5"')
					const priced = 'echo "cost $\\\nfive"'
					t.expect(Lexer.ToLine(priced)):toBe('echo "cost \\$five"')
					t.expect(words(Lexer.ToLine(priced))):toEqual(words(priced))
					const named = 'echo "$name\\\ns"'
					t.expect(Lexer.ToLine(named)):toBe('echo "$name\\x73"')
					t.expect(words(Lexer.ToLine(named))):toEqual(words(named))
				end
			)

			t.it("turns raw strings that span lines into single-quoted strings", function()
				const raw = 'echo """one\nit\'s \\ two"""'
				const line = Lexer.ToLine(raw)
				t.expect(line):toBe("echo 'one\\nit\\'s \\\\ two'")
				t.expect(words(line)):toEqual(words(raw))
			end)

			t.it("keeps embeds intact", function()
				t.expect(Lexer.ToLine("tp ${\n  players ?\n}")):toBe("tp ${ players ?}")
				t.expect(Lexer.ToLine('say "hi ${\nme\n}"')):toBe('say "hi ${me}"')
			end)

			t.it("keeps a lone # from turning into a comment", function()
				const text = "tag #\\\nBoss"
				t.expect(words(Lexer.ToLine(text))):toEqual({ "tag", "#", "Boss" })
			end)

			t.it(
				"parses the same as the original, with no line breaks or tabs left (fuzz)",
				function()
					-- The parse tree without spans: words as their text runs, variables and embeds, marked `=`
					-- when the word is a single variable or embed (its typed value passes through). Quoting is
					-- ignored because a bare escaped tab can only be written as a quoted one.
					local scriptShape: (script: Parser.Script) -> string
					const function wordShape(word: Parser.Word): string
						const out: { string } = {}
						const run: { string } = {}
						const function flush()
							if #run > 0 then
								table.insert(out, string.format("%q", table.concat(run)))
								table.clear(run)
							end
						end
						for _, part in word.Parts do
							if part.Kind == "Text" then
								table.insert(run, part.Value)
							elseif part.Kind == "Variable" then
								flush()
								const args = if part.Args then table.concat(part.Args, ","):gsub("[\r\n\t]", " ")
									else ""
								table.insert(out, `${part.Name}({args})`)
							else
								flush()
								table.insert(out, "${" .. scriptShape(part.Script) .. "}")
							end
						end
						flush()
						const single = #word.Parts == 1 and word.Parts[1].Kind ~= "Text"
						return (if single then "=" else "") .. table.concat(out, "+")
					end
					scriptShape = function(script: Parser.Script): string
						const statements: { string } = {}
						for _, chain in script.Statements do
							const pieces: { string } = {}
							for index, pipeline in chain.Pipelines do
								const commands: { string } = {}
								for _, command in pipeline.Commands do
									const shapes: { string } = {}
									for _, word in command.Words do
										table.insert(shapes, wordShape(word))
									end
									table.insert(commands, table.concat(shapes, " "))
								end
								table.insert(pieces, table.concat(commands, " | "))
								table.insert(pieces, chain.Operators[index] or "")
							end
							table.insert(statements, table.concat(pieces, " "))
						end
						return table.concat(statements, " ; ")
					end

					const rng = Prng.new(77)
					const alphabet = "ab $\"'{}|&;#\\\n\n\t\r()@:1 é"
					-- Whole constructs too, so raw strings, embeds, calls and continuations show up often.
					const fragments = {
						"a",
						"b1",
						" ",
						"\n",
						"\t",
						"\r\n",
						"\r",
						'"',
						"'",
						'"""',
						"${",
						"}",
						"$x",
						"$$",
						"$1",
						"$:r1",
						"$f(1,\n 2)",
						"$f(",
						")",
						"# c",
						"#",
						"\\",
						"\\\n",
						"\\\t",
						"\\x4",
						"\\u{41}",
						";",
						"|",
						"||",
						"&&",
						"é",
					}
					for iteration = 1, 10000 do
						local text = ""
						if iteration <= 4000 then
							text = rng:NextString(alphabet, 0, 36)
						else
							for _ = 1, rng:NextInteger(0, 14) do
								text ..= rng:Pick(fragments)
							end
						end
						const line = Lexer.ToLine(text)
						t.expect((line:find("[\r\n\t]"))):toBeNil()
						t.expect(Lexer.ToLine(line)):toBe(line)
						const before = Parser.Parse(text)
						const beforeShape = scriptShape(before.Script)
						const beforeErrors = #before.Diagnostics
						const after = Parser.Parse(line)
						if scriptShape(after.Script) ~= beforeShape or #after.Diagnostics ~= beforeErrors then
							t.expect(string.format("%q -> %q", text, line)):toBe("the same parse")
						end
					end
				end
			)
		end
	)
end
