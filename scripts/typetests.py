"""Negative type tests: each file in tests/types/negative must produce a type error on exactly the lines marked
`-- expect-error` (and nowhere else). Usage: python scripts/typetests.py (after scripts/analyze.sh set up .cache)."""
import pathlib
import re
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
DEFS = ROOT / ".cache" / "globalTypes.d.luau"
ERROR = re.compile(r"^(?P<path>.+?)(?: \[[^\]]*\])?\((?P<line>\d+),(?P<column>\d+)\): (?P<kind>TypeError|SyntaxError): (?P<message>.*)$")


def analyze(path: pathlib.Path) -> dict[int, list[str]]:
    result = subprocess.run(
        [
            "luau-lsp",
            "analyze",
            "--flag:LuauSolverV2=true",
            "--platform=roblox",
            f"--definitions=@roblox={DEFS}",
            "--sourcemap=sourcemap.json",
            str(path.relative_to(ROOT)),
        ],
        cwd=ROOT,
        capture_output=True,
        text=True,
    )
    errors: dict[int, list[str]] = {}
    for line in (result.stdout + result.stderr).splitlines():
        match = ERROR.match(line.strip())
        if match:
            errors.setdefault(int(match["line"]), []).append(match["message"])
    return errors


def main() -> int:
    if not DEFS.exists():
        print("Run scripts/analyze.sh once first (it downloads the Roblox definitions).", file=sys.stderr)
        return 2
    failures = 0
    files = sorted((ROOT / "tests" / "types" / "negative").glob("*.luau"))
    for path in files:
        expected = {
            number
            for number, text in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1)
            if text.rstrip().endswith("-- expect-error")
        }
        errors = analyze(path)
        missing = sorted(expected - errors.keys())
        unexpected = sorted(errors.keys() - expected)
        name = path.relative_to(ROOT).as_posix()
        if missing or unexpected:
            failures += 1
            print(f"FAIL {name}")
            for number in missing:
                print(f"  line {number}: expected a type error, got none")
            for number in unexpected:
                print(f"  line {number}: unexpected error: {errors[number][0]}")
        else:
            print(f"ok   {name} ({len(expected)} expected errors)")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
