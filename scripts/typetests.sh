#!/usr/bin/env bash
# Positive type tests are part of scripts/analyze.sh (zero errors). This runs the negative ones: each marked line
# must fail to type-check, proving the typing actually rejects mistakes.
set -euo pipefail
cd "$(dirname "$0")/.."

DEFS=".cache/globalTypes.d.luau"
if [ ! -f "$DEFS" ]; then
	mkdir -p .cache
	curl -fsSL -o "$DEFS" https://raw.githubusercontent.com/JohnnyMorganz/luau-lsp/main/scripts/globalTypes.None.d.luau
fi
rojo sourcemap demo.project.json -o sourcemap.json >/dev/null

# `python3` may be a non-functional store alias on Windows; use whichever interpreter actually runs.
for candidate in python3 python; do
	if "$candidate" -c "" >/dev/null 2>&1; then
		exec "$candidate" scripts/typetests.py
	fi
done
echo "Python 3 is required" >&2
exit 2
