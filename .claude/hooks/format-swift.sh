#!/usr/bin/env bash
# PostToolUse hook (Edit|Write): apply the switch-indent rule in .claude/rules/formatting.md
# to the Swift file Claude just changed, so the rule enforces itself instead of relying on
# Claude remembering it. Silent when the file needed no change.

set -u

INPUT="$(cat || true)"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

HOOK_STDIN="$INPUT" HOOK_ROOT="$ROOT" python3 - <<'PY'
import json, os, subprocess, sys

try:
    data = json.loads(os.environ.get("HOOK_STDIN") or "{}")
except Exception:
    sys.exit(0)

path = (data.get("tool_input") or {}).get("file_path") or ""
root = os.environ["HOOK_ROOT"]
if not path.endswith(".swift") or not os.path.isfile(path):
    sys.exit(0)
if not os.path.realpath(path).startswith(os.path.realpath(root) + os.sep):
    sys.exit(0)

result = subprocess.run(
    [sys.executable, os.path.join(root, "scripts", "reindent_switch_cases.py"), path],
    capture_output=True,
    text=True,
)
if result.returncode == 0 and result.stdout.strip():
    rel = os.path.relpath(path, root)
    print(json.dumps({
        "hookSpecificOutput": {
            "hookEventName": "PostToolUse",
            "additionalContext": f"{rel} was reindented to the switch-case rule in .claude/rules/formatting.md. Re-read it before editing it again.",
        }
    }))
PY

exit 0
