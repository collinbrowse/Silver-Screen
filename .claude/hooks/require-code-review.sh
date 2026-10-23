#!/usr/bin/env bash
# PreToolUse hook (Bash and the GitHub create-PR tool): the first time Claude tries to open
# a pull request from a branch, deny it and ask for a /code-review --fix pass first. The
# second attempt from the same branch goes through, so the review runs once per PR without
# anyone typing the command. Branches already reviewed are listed in the worktree's git dir.

set -u

INPUT="$(cat || true)"

HOOK_STDIN="$INPUT" python3 - <<'PY'
import json, os, re, subprocess, sys

try:
    data = json.loads(os.environ.get("HOOK_STDIN") or "{}")
except Exception:
    sys.exit(0)

tool = data.get("tool_name") or ""
tool_input = data.get("tool_input") or {}

if tool == "Bash":
    command = " ".join((tool_input.get("command") or "").split())
    if not re.search(r"\bgh\s+pr\s+create\b", command):
        sys.exit(0)
elif not tool.endswith("create_pull_request"):
    sys.exit(0)

def git(*args):
    return subprocess.run(["git", *args], capture_output=True, text=True).stdout.strip()

branch = tool_input.get("head") or git("rev-parse", "--abbrev-ref", "HEAD")
marker = git("rev-parse", "--git-path", "claude-reviewed-branches")
if not branch or not marker:
    sys.exit(0)

try:
    reviewed = set(open(marker, encoding="utf-8").read().split())
except OSError:
    reviewed = set()

if branch in reviewed:
    sys.exit(0)

with open(marker, "a", encoding="utf-8") as handle:
    handle.write(branch + "\n")

print(json.dumps({
    "hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": "deny",
        "permissionDecisionReason": (
            f"Review before opening a PR: run the code-review skill on branch {branch} with "
            "`--fix` (Skill tool, skill `code-review`, args `--fix`), wait for its findings, "
            "verify and commit the fixes in their own commit, then open the PR again. "
            "This gate asks once per branch; the next attempt goes through."
        ),
    }
}))
PY

exit 0
