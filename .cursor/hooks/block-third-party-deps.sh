#!/usr/bin/env bash
# beforeShellExecution: deny SPM / CocoaPods / Carthage additions.
# Allow xcodebuild (including package resolve for the approved Sentry package).

set -u

INPUT="$(cat || true)"

HOOK_STDIN="$INPUT" python3 - <<'PY'
import json, os, re, sys

raw = os.environ.get("HOOK_STDIN", "")
try:
    data = json.loads(raw) if raw.strip() else {}
except Exception:
    data = {}

command = data.get("command") or ""
normalized = " ".join(command.strip().split())

def allow():
    print(json.dumps({"permission": "allow"}))
    sys.exit(0)

def deny(message):
    print(json.dumps({
        "permission": "deny",
        "user_message": message,
        "agent_message": message,
    }))
    sys.exit(0)

if re.search(r"\bxcodebuild\b", normalized):
    allow()

denials = [
    (r"\bpod\s+(install|init|update|add)\b", "CocoaPods is not allowed (no 3rd-party dependencies except Sentry via SPM)."),
    (r"\bswift\s+package\b", "Use Xcode / xcodebuild for the approved Sentry package only — do not run swift package or add other packages."),
    (r"\bcarthage\b", "Carthage is not allowed (no 3rd-party dependencies except Sentry via SPM)."),
]

for pattern, message in denials:
    if re.search(pattern, normalized, re.IGNORECASE):
        deny(message)

mentions_manifest = re.search(r"(?:^|[\s/])(Podfile|Package\.swift)\b", normalized, re.IGNORECASE)
write_like = re.search(r"(?:\btouch\b|\btee\b|\bcp\b|\bmv\b|\bcat\b|[>]{1,2})", normalized)
if mentions_manifest and write_like:
    deny("Do not add Podfile or Package.swift (Sentry is wired through the Xcode project only).")

allow()
PY

exit 0
