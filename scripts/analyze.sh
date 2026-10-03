#!/usr/bin/env bash
# Strict type check of the whole tree with the new Luau solver (zero errors expected).
set -euo pipefail
cd "$(dirname "$0")/.."

DEFS=".cache/globalTypes.d.luau"
if [ ! -f "$DEFS" ]; then
	mkdir -p .cache
	curl -fsSL -o "$DEFS" https://raw.githubusercontent.com/JohnnyMorganz/luau-lsp/main/scripts/globalTypes.None.d.luau
fi

rojo sourcemap demo.project.json -o sourcemap.json >/dev/null

if [ "$#" -gt 0 ]; then
	TARGETS=("$@")
else
	TARGETS=(src demo examples tests)
fi

luau-lsp analyze \
	--flag:LuauSolverV2=true \
	--platform=roblox \
	--definitions=@roblox="$DEFS" \
	--sourcemap=sourcemap.json \
	--ignore="**/tests/types/negative/**" \
	"${TARGETS[@]}"
