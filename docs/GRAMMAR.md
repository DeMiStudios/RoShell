# Input grammar

This is the language the console, `server:Run`, `client:Run`, aliases, scripts and `RoShell.Test` accept. It is
implemented by `Shared/Lexer.luau` (text → tokens), `Shared/Parser.luau` (tokens → tree) and
`Shared/Resolver.luau` (words → typed argument values). None of them ever throws: problems become diagnostics with
byte spans, and the tree stays usable so the console can highlight and complete half-typed input.

## Lexical structure

```ebnf
script        = { separator } [ chain { separator { separator } chain } ] { separator } ;
separator     = ";" | newline ;
chain         = pipeline { ( "&&" | "||" ) pipeline } ;
pipeline      = command { "|" command } ;
command       = word { whitespace word } ;

word          = part { part } ;                      (* parts touch: no whitespace between them *)
part          = bare | dq-string | sq-string | raw-string | variable | embed ;

bare          = bare-char { bare-char } ;
bare-char     = ? any character except whitespace, quotes, "$", ";", "|", and "&&" ? | escape ;

dq-string     = '"' { dq-char | escape | variable | embed } '"' ;
sq-string     = "'" { sq-char | escape } "'" ;
raw-string    = '"""' { ? any character, newlines included ? } '"""' ;

escape        = "\" ( "n" | "t" | "r" | "0" | "\" | '"' | "'" | "$" | "`"
                    | "u{" hex { hex } "}" | "x" hex hex | newline (* line continuation *)
                    | ? any other character, kept as is ? ) ;

variable      = "$" ( identifier [ call ]            (* $name, $random(1, 10) *)
                    | "$"                             (* $$: result of the last command *)
                    | digit                           (* $1 … $9: alias parameters *)
                    | "@"                             (* $@: all alias parameters *)
                    | ":" identifier ) ;              (* $:12: a value held by the server *)
call          = "(" [ raw-arg { "," raw-arg } ] ")" ;
identifier    = ( letter | "_" ) { letter | digit | "_" } ;

embed         = "${" script "}" ;                    (* runs the script; its result replaces the embed *)

comment       = "#" ( whitespace | end-of-line ) { ? any character ? } end-of-line ;
```

Rules worth knowing:

- **Comments.** `#` starts a comment only when it begins a word *and* is followed by whitespace or the end of the
  line. `#Boss` is a word (the tag selector), `# note` is a comment.
- **Quotes.** `"..."` processes escapes and interpolates `$var` and `${...}`. `'...'` processes escapes only.
  `"""..."""` is raw: no escapes, no interpolation, may span lines. Unterminated quotes are closed at the end of
  input with a diagnostic (so completion keeps working while you type).
- **Quoting disables operators.** A quoted word is always taken literally: `kick "*"` looks for a player named
  `*`.
- **Embeds** run when the surrounding command runs; their final value is substituted. If the whole word is one
  embed, the *typed value* flows into the argument (no round trip through text): `tp Bob ${players ?}`.
- **Newlines** separate statements like `;`. The console input is single line; multi-line pastes are offered as
  a script, and history keeps them as the equivalent one-line command (`echo a; echo b`). A line continuation
  (`\` at the end of a line) joins lines, also inside quotes, where it leaves no trace.

## Statements, chains and pipes

| Syntax | Meaning |
|---|---|
| `a ; b` | Run `a`, then `b` regardless of the outcome |
| `a && b` | Run `b` only if `a` succeeded |
| `a \|\| b` | Run `b` only if `a` failed |
| `a \| b` | Pass `a`'s result to `b`'s pipe argument (type-checked) |

`&&` and `||` have equal precedence and associate left to right; `|` binds tighter than both. Piped values keep
their type: `players --team Red | kick` hands the list of players to `kick` without turning it into text. When a
pipeline crosses from the client to the server, the server re-parses the text and receives server-held values by
reference (`$:id`), never as client-supplied objects.

## Words → arguments

The first word names the command (aliases and subcommands are followed: `ban add Bob`). The remaining words are
classified by the resolver:

| Word | Role |
|---|---|
| `--name` | Flag (sets a boolean argument), or a named argument followed by its value |
| `--name=value` | Named argument |
| `-n value` / `-abc` | Short options; clusters of boolean short flags |
| `name=value` | Named argument (when `name` is an argument of the command) |
| `--` | End of options: every following word is positional |
| `--dry`, `--yes` | Global flags: preview without running / skip confirmations |
| anything else | Positional, bound to positional arguments in declaration order |

Positional binding details:

- A **rest** argument collects every remaining word.
- **Excess words** merge into a trailing string argument, so `announce hello world` needs no quotes.
- **Optional arguments are skipped by type** when there are fewer words than positional arguments and the word
  does not fit the optional argument but fits the next one: with `give [targets = me] <item> [amount]`,
  `give ~sword 3` gives to yourself.
- **Defaults** apply to arguments left out. A default can be a value or the text a player would type, parsed per
  run (`RoShell.Default(Types.Players, "me")`).

## Operators and wildcards

Enumerable types (players, teams, items, enums, instances, anything built with `Type.Choice`, `Type.Map`,
`Type.Dynamic` or `Type.Enumerable`) accept operators. A word that exactly names a candidate is always taken
literally first, so names containing operator characters still work.

| Form | Meaning | Example |
|---|---|---|
| `name` | Exact, then prefix, then fuzzy name match | `kick bob` |
| `.` / `me` | The executor's own value | `bring .` |
| `*` | Every value (lists only) | `heal *` |
| `**` | Everyone except you (lists only) | `kill **` |
| `?` / `?N` | One / N random values | `tp ? .`, `kick ?3` |
| `~text` | Fuzzy: the best match for one value, every strong match in a list | `give ~swrd` |
| `Bo*`, `B?b`, `[a-m]*` | Glob | `kick Guest*` |
| `%Team` | Players on a team | `heal %Red` |
| `#Tag` | Players (or their characters) with a CollectionService tag | `freeze #Boss` |
| `/pattern/` | Luau pattern (types that opt in) | `kick /^Guest%d+$/` |
| `a,b` | List | `heal Bob,Alice` |
| `a+b` | Union | `heal %Red+%Blue` |
| `a-b` | Difference | `kick *-Bob` |
| `a&b` | Intersection (binds tighter than `+`, `-`, `,`) | `heal %Red&%Admins` |
| `!a` | Complement | `kill !%Red` |
| `( )` | Grouping | `kick (*-%Red)&Guest*` |

Number lists accept ranges with an optional step: `setspeed Bo* 16..32/8` sets 16, 24 and 32.

Results keep the candidate enumeration order (except `?`, which is random by design). `help operators` lists the
operators a type supports, and `resolve <type> <text>` shows what any text resolves to.

## Variables and functions

| Form | Value |
|---|---|
| `$name` | A variable set with `set name value` (per player, persisted) |
| `$$` | The result of the previous top-level command |
| `$1` … `$9`, `$@` | Alias parameters (inside `alias` bodies) |
| `$:id` | A value held by the server for this player (used by client → server pipes) |
| `$fn(a, b)` | A function call; arguments are raw text split on commas |

Built-in functions: `$random(max)` / `$random(min, max)`, `$pick(a, b, …)`, `$time()`, `$date(format)`,
`$upper(text)`, `$lower(text)`, `$len(text)`, `$round(n, places)`, `$me()`. Register more with
`registry:RegisterFunction({ Name, Description, Call })`.

## Diagnostics

Every diagnostic carries a severity (`error`, `warning`, `info`), a message and a byte span
(`Start` inclusive, `End` exclusive, 1-based). The console underlines the span, shows the message in the signature
bar, and keeps the word being typed lenient while it still has completions.
