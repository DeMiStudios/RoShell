"""Runs a Luau entry of this repository headlessly, under the standalone Luau CLI, with Roblox instance requires.

RoShell's code requires modules the way Roblox does (`require(script.Parent.Shared.Fuzzy)`). The Luau CLI only
resolves string requires, has no `script` global and cannot read files, so this script hands it everything at once:

1. It mirrors the Rojo tree of `demo.project.json` (the same tree the sourcemap describes), following Rojo's rules:
   a folder becomes a `Folder`, a folder with an `init.luau` becomes that script with the other files as children,
   `X.luau` becomes a `ModuleScript` named `X`, `X.server.luau` a `Script` and `X.client.luau` a `LocalScript`.
2. It writes `.cache/headless/<entry>.luau`, a generated program holding that tree, the source of every script in
   it, and the loader (`scripts/Headless.luau`), then runs `luau` on it. The loader gives each module a `script`
   proxy and a `require` that loads the module behind an instance proxy once (see `scripts/Headless.luau`).

Usage: python scripts/headless.py <entry.luau> [luau options]
       (or `bash scripts/run.sh <entry.luau> [luau options]`, which finds Python first)

    bash scripts/run.sh tests/cli.luau                        # the test suite (`bash scripts/test.sh`)
    bash scripts/run.sh tests/bench.luau --codegen            # benchmarks with native code
    bash scripts/run.sh scripts/reference.luau > docs/Reference.md

Sources are loaded with `loadstring` under their own path, so errors and tracebacks name the real file and line.
With a `--codegen` option the modules the entry requires are compiled into the generated program instead (the CLI
only compiles files it loads itself to native code), and errors in them name lines of the generated file.
"""

import json
import os
import pathlib
import re
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
PROJECT = ROOT / "demo.project.json"
LOADER = "scripts/Headless.luau"
OUTPUT = ROOT / ".cache" / "headless"

# An instance require relative to `script`: `require(script.Parent.Shared.Fuzzy)`, `require(script.Parent["02-X"])`.
INSTANCE_REQUIRE = re.compile(r'require\(\s*(script(?:\s*\.\s*[A-Za-z_]\w*|\s*\[\s*"[^"]*"\s*\])*)\s*\)')
MEMBER = re.compile(r'\.\s*([A-Za-z_]\w*)|\[\s*"([^"]*)"\s*\]')

# Rojo's script file kinds, longest suffix first.
SCRIPT_SUFFIXES = [
    (".server.luau", "Script"),
    (".client.luau", "LocalScript"),
    (".server.lua", "Script"),
    (".client.lua", "LocalScript"),
    (".luau", "ModuleScript"),
    (".lua", "ModuleScript"),
]


def script_kind(file_name: str) -> tuple[str, str] | None:
    """The instance name and class Rojo gives a script file, or None for files Rojo does not turn into scripts."""
    for suffix, class_name in SCRIPT_SUFFIXES:
        if file_name.endswith(suffix):
            return file_name[: -len(suffix)], class_name
    return None


def relative(path: pathlib.Path) -> str:
    return path.relative_to(ROOT).as_posix()


def from_path(name: str, path: pathlib.Path) -> dict | None:
    """The instance Rojo makes from a file or folder, named `name` (a project key renames it)."""
    if path.is_file():
        kind = script_kind(path.name)
        if kind is None:
            return None
        return {"Name": name, "ClassName": kind[1], "Path": relative(path), "Children": []}
    node = {"Name": name, "ClassName": "Folder", "Path": None, "Children": []}
    entries = sorted(path.iterdir(), key=lambda entry: entry.name)
    for entry in entries:
        kind = script_kind(entry.name) if entry.is_file() else None
        if kind and kind[0] == "init":
            # A folder with an init script is that script; its other files are the script's children.
            node["ClassName"] = kind[1]
            node["Path"] = relative(entry)
    for entry in entries:
        kind = script_kind(entry.name) if entry.is_file() else None
        if kind and kind[0] == "init":
            continue
        child = from_path(kind[0] if kind else entry.name, entry)
        if child is not None:
            node["Children"].append(child)
    return node


def from_project(name: str, description: dict, parent_class: str | None) -> dict:
    """The instance a node of a Rojo project file describes."""
    node = None
    if "$path" in description:
        node = from_path(name, ROOT / description["$path"])
    if node is None:
        # Under the DataModel a key names its service, as Rojo infers.
        default_class = name if parent_class == "DataModel" else "Folder"
        node = {"Name": name, "ClassName": description.get("$className", default_class), "Path": None, "Children": []}
    for key, child in description.items():
        if not key.startswith("$"):
            node["Children"].append(from_project(key, child, node["ClassName"]))
    return node


def long_string(text: str) -> str:
    """`text` as a Luau long string literal (the newline after the opening bracket is not part of the string)."""
    level = 0
    while f"]{'=' * level}]" in text:
        level += 1
    equals = "=" * level
    return f"[{equals}[\n{text}]{equals}]"


def luau_tree(node: dict, depth: int) -> str:
    indent = "\t" * depth
    fields = [f"Name = {json.dumps(node['Name'])}", f"ClassName = {json.dumps(node['ClassName'])}"]
    if node["Path"]:
        fields.append(f"Path = {json.dumps(node['Path'])}")
    if node["Children"]:
        children = ",\n".join(luau_tree(child, depth + 1) for child in node["Children"])
        fields.append(f"Children = {{\n{children},\n{indent}}}")
    return f"{indent}{{ " + ", ".join(fields) + " }"


def script_paths(node: dict, into: set[str]) -> set[str]:
    if node["Path"]:
        into.add(node["Path"])
    for child in node["Children"]:
        script_paths(child, into)
    return into


def find_nodes(node: dict, path: str, parent: dict | None, into: list) -> list:
    """Every instance whose source is the file `path`, with its parent links filled in."""
    node["Parent"] = parent
    if node["Path"] == path:
        into.append(node)
    for child in node["Children"]:
        find_nodes(child, path, node, into)
    return into


def required_closure(entry: dict) -> set[str]:
    """The files `entry` can reach through instance requires written in its source (calls inside functions too)."""
    seen: set[int] = set()
    paths: set[str] = set()
    pending = [entry]
    while pending:
        node = pending.pop()
        if id(node) in seen or not node["Path"]:
            continue
        seen.add(id(node))
        paths.add(node["Path"])
        for match in INSTANCE_REQUIRE.finditer(read_source(node["Path"])):
            target = node
            for member in MEMBER.finditer(match.group(1)[len("script") :]):
                name = member.group(1) or member.group(2)
                if name == "Parent":
                    target = target["Parent"]
                else:
                    target = next((child for child in target["Children"] if child["Name"] == name), None)
                if target is None:
                    break
            if target is not None:
                pending.append(target)
    return paths


def read_source(path: str) -> str:
    text = (ROOT / path).read_text(encoding="utf-8-sig")
    return text.replace("\r\n", "\n")


def generate(entry: str, native: bool) -> str:
    project = json.loads(PROJECT.read_text(encoding="utf-8"))
    tree = from_project(project.get("name", "DataModel"), project["tree"], None)
    paths = sorted(script_paths(tree, set()))
    entries = find_nodes(tree, entry, None, [])
    if len(entries) != 1:
        raise SystemExit(f"{entry} must be exactly one script of the {PROJECT.name} tree, found {len(entries)}")
    # Native code generation gives up on a program past a size limit, so only the modules the entry can reach are
    # compiled into it; any other module stays a source (and runs in the interpreter if something requires it).
    compiled = required_closure(entries[0]) if native else set()

    lines = [
        "-- Generated by scripts/headless.py for one run. Do not edit: it is rebuilt from the files every time.",
        f"local LOADER = {long_string(read_source(LOADER))}",
        "local MODULES = {}",
    ]
    for path in paths:
        source = read_source(path)
        if path in compiled:
            # Compiled with the generated program, so `--codegen` applies. Types and `const` are fine in a body.
            lines.append(f"MODULES[{json.dumps(path)}] = function(script, require, ...)\n{source}\nend")
        else:
            lines.append(f"MODULES[{json.dumps(path)}] = {long_string(source)}")
    lines.append(f"local TREE = {luau_tree(tree, 0)}")
    lines.append(f'local Headless = assert(loadstring(LOADER, "@{LOADER}"))()')
    lines.append(f"Headless.Run(TREE, MODULES, {json.dumps(entry)})")
    return "\n".join(lines) + "\n"


def main(arguments: list[str]) -> int:
    if not arguments or arguments[0].startswith("-"):
        print("usage: python scripts/headless.py <entry.luau> [luau options]", file=sys.stderr)
        return 2
    entry = pathlib.Path(arguments[0]).as_posix().removeprefix("./")
    options = arguments[1:]
    native = any(option.startswith("--codegen") for option in options)

    OUTPUT.mkdir(parents=True, exist_ok=True)
    program = OUTPUT / (entry.replace("/", "-").removesuffix(".luau") + ".luau")
    program.write_text(generate(entry, native), encoding="utf-8", newline="\n")

    luau = os.environ.get("LUAU", "luau")
    return subprocess.run([luau, *options, str(program.relative_to(ROOT))], cwd=ROOT).returncode


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
