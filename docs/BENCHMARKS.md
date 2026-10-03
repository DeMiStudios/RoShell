# Benchmarks

Budgets come from the specification (§7.2, §11): one keystroke's completion work ≤ 1 ms median with ≤ 500
commands and ≤ 200 candidates, ≤ 4 ms with 10 000 candidates; 10 000 fuzzy candidates scored in under 4 ms.

Run them yourself:

```bash
luau --codegen tests/bench.luau     # native code generation
luau tests/bench.luau               # interpreter (what Roblox clients run)
```

or in Studio from the command bar:

```lua
local root = game.ServerStorage.RoShellDev.tests.benchmarks
local Bench = require(root.Bench)
print(Bench.Report("Fuzzy", require(root.FuzzyBench).Run()))
print(Bench.Report("Pipeline", require(root.PipelineBench).Run()))
```

`tests/bench.luau` exits with an error when a median exceeds its budget. Each benchmark runs three warm-up
iterations (which also fill the prepared-string caches, as a live registry would) and then 30–200 timed iterations.

Results below: AMD Ryzen 9 9950X3D, Luau 0.741 and Roblox Studio 0.741 (October 2026).

## Roblox Studio (server, engine VM)

| Benchmark | Median (ms) | p99 (ms) | Budget (ms) |
|---|---:|---:|---:|
| Fuzzy.Filter 10k "sw" | 1.579 | 2.053 | 4.00 |
| Fuzzy.Filter 10k "frost bl" | 0.678 | 0.712 | 4.00 |
| Fuzzy.Filter 10k "gdh" | 0.715 | 0.853 | 4.00 |
| Fuzzy.Filter 10k "mythic staff 9" | 0.668 | 1.782 | 4.00 |
| Fuzzy.Filter 10k "zzq" | 0.535 | 0.551 | 4.00 |
| Fuzzy.Filter 200 "sw" | 0.039 | 0.049 | 1.00 |
| Lexer.Tokenize 2.3 KB script | 0.376 | 1.865 | 4.00 |
| Parser.Parse 2.3 KB script | 0.862 | 3.966 | 8.00 |
| Evaluate (500 cmds, 200 candidates) | 0.018 | 0.025 | 1.00 |
| Complete argument (500 cmds, 200 candidates) | 0.041 | 0.052 | 1.00 |
| Complete command name (500 cmds) | 0.398 | 1.293 | 1.00 |
| Complete argument (10 000 candidates) | 0.782 | 0.973 | 4.00 |

## Luau CLI, native code generation

| Benchmark | Median (ms) | p99 (ms) | Budget (ms) |
|---|---:|---:|---:|
| Fuzzy.Filter 10k "sw" | 1.661 | 2.469 | 4.00 |
| Fuzzy.Filter 10k "frost bl" | 0.560 | 0.587 | 4.00 |
| Fuzzy.Filter 10k "gdh" | 0.598 | 1.934 | 4.00 |
| Fuzzy.Filter 10k "mythic staff 9" | 0.623 | 1.996 | 4.00 |
| Fuzzy.Filter 10k "zzq" | 0.493 | 2.078 | 4.00 |
| Fuzzy.Filter 200 "sw" | 0.039 | 0.064 | 1.00 |
| Lexer.Tokenize 2.3 KB script | 0.201 | 0.704 | 4.00 |
| Parser.Parse 2.3 KB script | 0.647 | 2.468 | 8.00 |
| Evaluate (500 cmds, 200 candidates) | 0.016 | 0.049 | 1.00 |
| Complete argument (500 cmds, 200 candidates) | 0.034 | 0.122 | 1.00 |
| Complete command name (500 cmds) | 0.277 | 0.917 | 1.00 |
| Complete argument (10 000 candidates) | 0.644 | 0.703 | 4.00 |

## Luau CLI, interpreter

| Benchmark | Median (ms) | p99 (ms) | Budget (ms) |
|---|---:|---:|---:|
| Fuzzy.Filter 10k "sw" | 3.176 | 4.029 | 4.00 |
| Fuzzy.Filter 10k "frost bl" | 0.936 | 0.984 | 4.00 |
| Fuzzy.Filter 10k "gdh" | 0.985 | 1.041 | 4.00 |
| Fuzzy.Filter 10k "mythic staff 9" | 0.987 | 1.030 | 4.00 |
| Fuzzy.Filter 10k "zzq" | 0.723 | 0.777 | 4.00 |
| Fuzzy.Filter 200 "sw" | 0.056 | 0.074 | 1.00 |
| Lexer.Tokenize 2.3 KB script | 0.279 | 0.771 | 4.00 |
| Parser.Parse 2.3 KB script | 0.743 | 2.445 | 8.00 |
| Evaluate (500 cmds, 200 candidates) | 0.018 | 0.028 | 1.00 |
| Complete argument (500 cmds, 200 candidates) | 0.062 | 0.116 | 1.00 |
| Complete command name (500 cmds) | 0.407 | 1.057 | 1.00 |
| Complete argument (10 000 candidates) | 0.637 | 0.705 | 4.00 |

## Notes

- **`"sw"` over 10 000 candidates is the worst case**: almost every candidate contains an `s` and a `w`, so the
  bitmask pre-filter rejects little and every candidate goes through the dynamic program. It led to the current
  scoring loop (first row computed separately, row buffers swapped instead of copied, row `i` starting at column
  `i`), which took the interpreted median from 4.05 ms to 3.2 ms. Selective queries are rejected by the
  character-mask pre-filter and the subsequence check before any scoring.
- **Top-K, not sorting.** `Fuzzy.Filter` keeps the best `limit` results in a binary heap and computes highlight
  positions only for those.
- **Caching.** Prepared candidates (code points, lower-case forms, boundary bonuses, character masks) are cached
  per string (bounded), `Dynamic` types cache their candidates for `CacheSeconds`, and the parser memoizes the last
  input, since moving the caret is far more frequent than editing.
- **One update per frame.** The console coalesces evaluation, completion and highlighting into one deferred update
  per frame, however many input events arrive.
- **UI virtualization.** The log measures each entry once per width and binds only the visible rows (plus 240 px of
  overscan) to pooled instances; suggestion and palette lists do the same with fixed-height rows. Neither creates
  instances per keystroke.
