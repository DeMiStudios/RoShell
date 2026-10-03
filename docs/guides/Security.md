# Security model

A console is a remote execution surface. RoShell treats every client as hostile and keeps all authority on the
server.

## The client sends text, never values

A remote run request carries only the command line, the global flags (`--dry`, `--yes`), an opaque `Data` payload
from the command's own collector, and — for pipes — a reference to a value the **server** produced earlier for the
same player (`$:id`). The server re-lexes, re-parses and re-resolves the text against its own registry and its own
view of the world. Client-side parsing exists only for the UI (highlighting, completion, previews).

## Narrowing at the boundary

Everything received from the network arrives as `unknown` and is narrowed field by field in `Shared/Net.luau`:
types are checked, strings are length-limited (command lines to 8 192 bytes), integers are range-checked, and
unknown fields are ignored. Values sent the other way are sanitized: functions, threads and buffers are dropped,
tables are copied with bounded depth and size.

## Permissions are checked three times

1. When the client connects, it receives only the names of commands it may **see** (completion, help and the
   palette never reveal the rest).
2. Before the server parses a request's arguments — so autocomplete-style probing cannot learn anything about
   commands you may not run.
3. Right before execution, with the parsed arguments available to predicates.

The default is deny ([Permissions](Permissions.md)). Studio bypass applies only in Studio and can be disabled.

## Rate limits and resource bounds

- A token bucket per player covers every remote request (default burst 20, 6 per second).
- Per-command `Cooldown` and `RateLimit`.
- Commands time out (default 60 s; `Timeout = 0` disables) and are cancellable; the server cancels a player's
  running commands and pending prompts when they leave.
- Scripts and aliases are bounded: at most 256 commands per script, 16 levels of alias nesting and 8 levels of
  embedding.
- Prompts time out (60 s by default) and resolve as cancelled.
- Saved user data is size-checked before it reaches storage.

## No dynamic code

RoShell never uses `loadstring`, `getfenv`/`setfenv`, or `require` by asset id. `run-script` runs command lines
from ModuleScripts/StringValues you place in a folder you choose (`server.Registry:AddEnv(RoShell.Keys.Scripts,
folder)`), not Luau code. Command modules are loaded only from containers you register.

## Output is escaped

All user-supplied text shown in the console (player names, messages, values) is RichText-escaped. Commands opt in
to RichText explicitly (`Rich = true` on a text block).

## Auditing

Every server-side execution is written to the audit sink with the executor, the raw line, the parsed arguments,
the outcome and the duration. Combine sinks with `RoShell.Audit.Fanout` (memory for the `audit` command, a
DataStore for history, a webhook for moderators).

## What remains your responsibility

- Grant groups deliberately; prefer roles over user lists.
- Treat `ctx:GetData()` as untrusted input: it comes from the client's `Data` collector and is only sanitized, not
  validated.
- Commands that touch persistent data should be `Destructive` and support `--dry`.
