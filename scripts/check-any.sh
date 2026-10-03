#!/usr/bin/env bash
# Fails when `any` appears as a type anywhere in the library (annotations, casts, returns, generic arguments).
set -euo pipefail
cd "$(dirname "$0")/.."
if grep -rnE '(:|::|->)[[:space:]]*any\b|<<?any\b|\bany>' src --include='*.luau'; then
	echo "error: 'any' types are not allowed in src/" >&2
	exit 1
fi
echo "ok: no 'any' types in src/"
