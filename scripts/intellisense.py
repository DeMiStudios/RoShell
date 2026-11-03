"""Intellisense tests: what VS Code (luau-lsp) offers while writing code that uses RoShell.

Each case is a small piece of user code with a cursor (`@@`). The script starts `luau-lsp lsp`, opens the code as a
file in the tests folder (so `require("../src")` resolves to the package), asks for completions or a hover at the
cursor and checks the answer: completions must include `expect` (and none of `reject`), with the given type
(`detail`) and documentation; hovers must contain every `expect` string.

Run with `bash scripts/intellisense.sh` (generates the sourcemap and type definitions first).
"""

import json
import os
import pathlib
import subprocess
import sys
import threading

ROOT = pathlib.Path(__file__).resolve().parent.parent
# Never written to disk: the editor sends its text, as VS Code does for an unsaved file.
PROBE = ROOT / "tests" / "IntellisenseProbe.luau"

HEADER = """--!strict
const RoShell = require("../src")
"""

COMMAND = """
const Mode = RoShell.Type.Choice<<"add" | "set">>({ Name = "mode", Choices = { "add", "set" } })
const give = RoShell.Command({
	Name = "give",
	Args = {
		{ targets = RoShell.Arg(RoShell.Types.Players) },
		{ amount = RoShell.Default(RoShell.Types.Integer, 1) },
		{ mode = RoShell.Optional(Mode) },
		{ silent = RoShell.Flag() },
	},
}):Run(function(ctx, args)
	%s
	return nil
end)
"""

CASES = [
    {
        "name": "module members",
        "code": "RoShell.@@",
        "kind": "completion",
        "expect": ["new", "Command", "Arg", "Optional", "Default", "Rest", "Flag", "Type", "Types", "Permissions",
                   "Storage", "Audit", "Test", "Plugin", "GetShell", "Version"],
    },
    {
        "name": "options of RoShell.new",
        "code": "const shell = RoShell.new({ @@ })",
        "kind": "completion",
        "expect": ["Admins", "Commands", "DefaultCommands", "Storage", "Audit", "RateLimit", "PlaceName",
                   "ActivationKeys", "Keymap", "Settings", "Interface"],
    },
    {
        "name": "shell methods",
        "code": "const shell = RoShell.new()\nshell:@@",
        "kind": "completion",
        "expect": ["Start", "Run", "Broadcast", "SendEvent", "RefreshVisibility", "Execute", "Show", "Hide", "Toggle",
                   "IsVisible", "SetEnabled", "SetTheme", "OnEvent", "GetHistory"],
    },
    {
        "name": "shell fields",
        "code": "const shell = RoShell.new()\nconst _value = shell.@@",
        "kind": "completion",
        "expect": ["Registry", "Permissions", "Dispatcher", "Shell", "Locale", "IsServer", "IsClient", "Scheduler",
                   "Audit", "Settings", "Toggled", "Executed"],
    },
    {
        "name": "registry methods",
        "code": "const shell = RoShell.new()\nshell.Registry:@@",
        "kind": "completion",
        "expect": ["RegisterCommand", "RegisterCommandsIn", "RegisterType", "RegisterHooks", "RegisterPlugin",
                   "GetCommand", "RegisterDefaultCommands"],
    },
    {
        "name": "permission rules",
        "code": "RoShell.Permissions.@@",
        "kind": "completion",
        "expect": ["Everyone", "Users", "Group", "Role", "Predicate", "Any", "All", "Not"],
    },
    {
        "name": "typed arguments in Run",
        "code": COMMAND % "const _value = args.@@",
        "kind": "completion",
        "expect": ["targets", "amount", "mode", "silent"],
    },
    {
        "name": "context methods in Run",
        "code": COMMAND % "ctx:@@",
        "kind": "completion",
        "expect": ["Reply", "Success", "Error", "Warn", "Table", "List", "Prompt", "Confirm", "GetEnv"],
    },
    {
        "name": "a list argument's type",
        "code": COMMAND % "const _value = args.targ@@ets",
        "kind": "hover",
        "expect": ["{Player}"],
    },
    {
        "name": "a choice argument's type",
        "code": COMMAND % "const _value = args.mo@@de",
        "kind": "hover",
        "expect": ['"add"', '"set"'],
    },
    {
        "name": "a default argument's type",
        "code": COMMAND % "const _value = args.amou@@nt",
        "kind": "hover",
        "expect": ["number"],
    },
    {
        "name": "RoShell.new's documentation",
        "code": "const shell = RoShell.ne@@w()",
        "kind": "hover",
        "expect": ["Creates the shell for the side it runs on"],
    },
    {
        "name": "a method's documentation",
        "code": "const shell = RoShell.new()\nshell:Broad@@cast(\"Hi\")",
        "kind": "hover",
        "expect": ["(Server)", "MessagingService"],
    },
    {
        # luau-lsp shows the type of a key typed in a table literal, but not its documentation.
        "name": "an option's type",
        "code": "const shell = RoShell.new({ Adm@@ })",
        "kind": "completion",
        "expect": ["Admins"],
        "detail": {"Admins": "{Permission | number}?"},
    },
    {
        "name": "a field's documentation in completions",
        "code": "const shell = RoShell.new()\nconst _value = shell.@@",
        "kind": "completion",
        "expect": ["Scheduler"],
        "detail": {"Scheduler": "Scheduler?", "Settings": "Settings?", "IsServer": "boolean"},
        "documentation": {"Scheduler": "Nil on clients", "Settings": "Nil on the server"},
    },
    {
        "name": "a method's documentation in completions",
        "code": "const shell = RoShell.new()\nshell:@@",
        "kind": "completion",
        "expect": ["Show"],
        "documentation": {"Show": "Opens the console", "Run": "Runs a command line from code"},
    },
]


class Client:
    def __init__(self, command):
        self.process = subprocess.Popen(command, cwd=ROOT, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                        stderr=None if os.environ.get("INTELLISENSE_DEBUG") else subprocess.DEVNULL)
        self.next_id = 0
        self.responses = {}
        self.condition = threading.Condition()
        threading.Thread(target=self._read, daemon=True).start()

    def _send(self, message):
        body = json.dumps(message).encode("utf-8")
        self.process.stdin.write(f"Content-Length: {len(body)}\r\n\r\n".encode("ascii") + body)
        self.process.stdin.flush()

    def _read(self):
        stream = self.process.stdout
        while True:
            length = None
            while True:
                line = stream.readline()
                if not line:
                    return
                line = line.strip()
                if not line:
                    break
                if line.lower().startswith(b"content-length:"):
                    length = int(line.split(b":")[1])
            message = json.loads(stream.read(length))
            if "id" in message and "method" in message:
                self._answer(message)
            elif "id" not in message and os.environ.get("INTELLISENSE_DEBUG"):
                print("<-", message.get("method"), json.dumps(message.get("params"))[:300], file=sys.stderr)
            elif "id" in message:
                with self.condition:
                    self.responses[message["id"]] = message
                    self.condition.notify_all()

    def _answer(self, request):
        result = None
        if request["method"] == "workspace/configuration":
            result = [SETTINGS if item.get("section") in ("luau-lsp", None) else None
                      for item in request["params"]["items"]]
        self._send({"jsonrpc": "2.0", "id": request["id"], "result": result})

    def request(self, method, params, timeout=60):
        self.next_id += 1
        ident = self.next_id
        self._send({"jsonrpc": "2.0", "id": ident, "method": method, "params": params})
        with self.condition:
            self.condition.wait_for(lambda: ident in self.responses, timeout)
            response = self.responses.pop(ident, None)
        if response is None:
            raise TimeoutError(method)
        return response.get("result")

    def notify(self, method, params):
        self._send({"jsonrpc": "2.0", "method": method, "params": params})


SETTINGS = {
    "platform": {"type": "roblox"},
    "sourcemap": {"enabled": True, "rojoProjectFile": "demo.project.json", "autogenerate": False},
    "fflags": {"enableNewSolver": True},
    "completion": {"enabled": True, "imports": {"enabled": False}},
}


def completion_items(result):
    items = result.get("items", []) if isinstance(result, dict) else (result or [])
    return {item["label"]: item for item in items}


def documentation(client, item):
    docs = item.get("documentation")
    if docs is None:
        docs = (client.request("completionItem/resolve", item) or {}).get("documentation")
    if isinstance(docs, dict):
        return docs.get("value", "")
    return docs or ""


def hover_text(result):
    if not result:
        return ""
    contents = result.get("contents")
    if isinstance(contents, dict):
        return contents.get("value", "")
    if isinstance(contents, list):
        return "\n".join(part if isinstance(part, str) else part.get("value", "") for part in contents)
    return str(contents)


def main():
    definitions = ROOT / ".cache" / "globalTypes.d.luau"
    client = Client([
        "luau-lsp", "lsp", "--stdio",
        f"--definitions=@roblox={definitions}",
        "--flag:LuauSolverV2=true",
    ])
    root_uri = ROOT.as_uri()
    client.request("initialize", {
        "processId": os.getpid(),
        "rootUri": root_uri,
        "workspaceFolders": [{"uri": root_uri, "name": ROOT.name}],
        "capabilities": {
            "workspace": {"configuration": True},
            "textDocument": {
                "completion": {"completionItem": {"documentationFormat": ["markdown", "plaintext"]}},
                "hover": {"contentFormat": ["markdown", "plaintext"]},
            },
        },
        "initializationOptions": {},
    })
    client.notify("initialized", {})
    client.notify("workspace/didChangeConfiguration", {"settings": {"luau-lsp": SETTINGS}})

    uri = PROBE.as_uri()
    failures = 0
    version = 0
    for case in CASES:
        text = HEADER + case["code"]
        cursor = text.index("@@")
        text = text.replace("@@", "", 1)
        line = text.count("\n", 0, cursor)
        character = cursor - (text.rfind("\n", 0, cursor) + 1)
        version += 1
        if version == 1:
            client.notify("textDocument/didOpen", {"textDocument": {"uri": uri, "languageId": "luau", "version": 1,
                                                                    "text": text}})
        else:
            client.notify("textDocument/didChange", {"textDocument": {"uri": uri, "version": version},
                                                     "contentChanges": [{"text": text}]})
        position = {"textDocument": {"uri": uri}, "position": {"line": line, "character": character}}
        if case["kind"] == "completion":
            got = completion_items(client.request("textDocument/completion", position))
            missing = [label for label in case["expect"] if label not in got]
            unwanted = [label for label in case.get("reject", []) if label in got]
            undocumented = [
                label
                for label, snippet in case.get("documentation", {}).items()
                if label not in got or snippet not in documentation(client, got[label])
            ]
            mistyped = [
                label
                for label, snippet in case.get("detail", {}).items()
                if label not in got or snippet not in (got[label].get("detail") or "")
            ]
            ok = not missing and not unwanted and not undocumented and not mistyped
            detail = (
                f"missing {missing}" if missing
                else f"unwanted {unwanted}" if unwanted
                else f"no documentation for {undocumented}" if undocumented
                else f"unexpected types for {[(label, got.get(label, {}).get('detail')) for label in mistyped]}"
                if mistyped
                else ""
            )
        else:
            got_text = hover_text(client.request("textDocument/hover", position))
            missing = [snippet for snippet in case["expect"] if snippet not in got_text]
            ok = not missing
            detail = f"missing {missing} in hover: {got_text[:300]!r}" if missing else ""
        print(f"{'ok  ' if ok else 'FAIL'} {case['name']}" + (f" ({detail})" if detail else ""))
        failures += 0 if ok else 1

    client.request("shutdown", None)
    client.notify("exit", None)
    print(f"{len(CASES) - failures} passed, {failures} failed")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
