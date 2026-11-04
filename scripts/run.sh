#!/usr/bin/env bash
# Runs a Luau entry of this repository headlessly with the Luau CLI: `bash scripts/run.sh <entry.luau> [luau options]`.
# The code uses Roblox instance requires, so scripts/headless.py mirrors the Rojo tree and loads it through
# scripts/Headless.luau. Examples: `bash scripts/run.sh tests/bench.luau --codegen`,
# `bash scripts/run.sh scripts/reference.luau > docs/Reference.md`.
set -euo pipefail
cd "$(dirname "$0")/.."

# `python3` may be a non-functional store alias on Windows; use whichever interpreter actually runs.
for candidate in python3 python; do
	if "$candidate" -c "" >/dev/null 2>&1; then
		exec "$candidate" scripts/headless.py "$@"
	fi
done
echo "Python 3 is required" >&2
exit 2
