#!/usr/bin/env bash
# Claude Code PreToolUse hook (Bash): releases and direct writes to main stay with a human.
# Agents may merge to main only through GitHub auto-merge, behind the main ruleset and
# CODEOWNERS (see .claude/rules/pull-requests.md). Anything that cuts or ships a build,
# pushes a release tag, pushes main, merges past the ruleset, or edits repo protection
# returns "ask", so the person at the keyboard approves it. Everything else returns no
# decision and the normal permission flow applies.

set -u

INPUT="$(cat || true)"

HOOK_STDIN="$INPUT" python3 - <<'PY'
import json, os, re, sys

raw = os.environ.get("HOOK_STDIN", "")
try:
    data = json.loads(raw) if raw.strip() else {}
except Exception:
    data = {}

command = (data.get("tool_input") or {}).get("command") or ""
normalized = " ".join(command.strip().split())


def ask(message):
    print(json.dumps({
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "ask",
            "permissionDecisionReason": message,
        }
    }))
    sys.exit(0)


RELEASE = "Releases are human-gated: "

# release.py subcommands that change versions, tags, uploads, or App Store state.
if re.search(r"\brelease\.py\s+(cut|bump|promote|media\s+.*--apply)\b", normalized) or re.search(
    r"\brelease\.py\s+archive\b.*--upload", normalized
):
    ask(RELEASE + "approve this release.py step.")

MAIN = "Direct pushes to main are human-gated; agents land work through a PR."


def current_branch():
    try:
        import subprocess
        return subprocess.run(
            ["git", "symbolic-ref", "--quiet", "--short", "HEAD"], capture_output=True, text=True, timeout=5
        ).stdout.strip()
    except Exception:
        return ""


for segment in re.split(r"&&|\|\||;|\|", normalized):
    segment = segment.strip()
    push = re.search(r"\bgit\b.*?\bpush\b(.*)", segment)
    if not push:
        continue
    if re.search(r"--tags\b|--follow-tags\b|\btestflight/|\brefs/tags/|(?:\s|:)v\d", segment):
        ask(RELEASE + "approve pushing a release tag.")
    if re.search(r"(?:\s|:)(?:refs/heads/)?main(?=\s|$)", segment):
        ask(MAIN)
    # No refspec (`git push`, `git push origin`) pushes the current branch.
    positional = [arg for arg in push.group(1).split() if not arg.startswith("-")]
    if len(positional) <= 1 and current_branch() == "main":
        ask(MAIN)

# Ways to ship without release.py or a tag push.
if re.search(r"\bgh\s+(workflow|run)\s+(run|rerun)\b", normalized) and re.search(r"release", normalized, re.IGNORECASE) or re.search(
    r"\bgh\s+release\s+(create|delete|edit)\b", normalized
) or re.search(r"\bgh\s+api\b.*\bactions/(workflows/[^\s]*/dispatches|runs/\d+/(rerun|pending_deployments))", normalized):
    ask(RELEASE + "approve running the release workflow or editing a GitHub release.")
if re.search(r"\bgh\s+api\b.*\bgit/(refs|tags)\b", normalized) and re.search(
    r"(?:-X|--method)[\s=]*(POST|PATCH|DELETE)\b|\s(?:-f|-F|--input)\b", normalized, re.IGNORECASE
):
    ask(RELEASE + "approve creating or moving a git ref through the API.")

# Merging immediately (not --auto) uses the admin bypass and skips required checks.
if re.search(r"\bgh\s+pr\s+merge\b", normalized) and not re.search(r"--auto\b", normalized):
    ask("Merging without --auto skips the main ruleset; approve it, or use gh pr merge --auto.")

# Repo protection and merge settings.
PROTECTION = "Changing repo protection or merge settings is human-gated."
if re.search(r"\bgh\s+repo\s+edit\b", normalized):
    ask(PROTECTION)
for segment in re.split(r"&&|\|\||;|\|", normalized):
    if not re.search(r"\bgh\s+api\b", segment):
        continue
    writes = re.search(r"(?:-X|--method)[\s=]*(POST|PUT|PATCH|DELETE)\b|\s(?:-f|-F|--field|--raw-field|--input)\b", segment, re.IGNORECASE)
    repo_root = re.search(r"\brepos/[^/\s]+/[^/\s]+(?:\s|$)", segment)
    if writes and (re.search(r"/rulesets|/protection\b", segment) or repo_root):
        ask(PROTECTION)

sys.exit(0)
PY

exit 0
