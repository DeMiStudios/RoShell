#!/usr/bin/env bash
# Unit tests, headless: every spec in tests/Specs.luau under the Luau CLI (engine-only specs are skipped).
set -euo pipefail
exec bash "$(dirname "$0")/run.sh" tests/cli.luau "$@"
