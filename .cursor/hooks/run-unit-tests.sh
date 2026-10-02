#!/usr/bin/env bash
# stop hook: run TheSilverScreenTests. Fail-open (print {}) if aborted, missing simulator, or unexpected errors.

set -u

emit_empty() {
  printf '%s\n' '{}'
  exit 0
}

INPUT="$(cat || true)"

STATUS="$(printf '%s' "$INPUT" | python3 -c '
import json, sys
raw = sys.stdin.read()
try:
    data = json.loads(raw) if raw.strip() else {}
except Exception:
    data = {}
print(data.get("status", "") or "")
' 2>/dev/null || true)"

case "$STATUS" in
  aborted|error) emit_empty ;;
esac

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT" || emit_empty

UDID="$(python3 -c '
import json, subprocess, sys

PREFERRED = "iPhone 17e"

try:
    raw = subprocess.check_output(
        ["xcrun", "simctl", "list", "devices", "available", "-j"],
        stderr=subprocess.DEVNULL,
        text=True,
    )
    data = json.loads(raw)
except Exception:
    sys.exit(0)

by_name = {}
for runtime, devices in (data.get("devices") or {}).items():
    if "iOS" not in runtime:
        continue
    for device in devices or []:
        if device.get("isAvailable") is False:
            continue
        name = device.get("name") or ""
        udid = device.get("udid") or ""
        if name == PREFERRED and udid:
            by_name[PREFERRED] = udid
            break
    if PREFERRED in by_name:
        break

chosen = by_name.get(PREFERRED, "")
if chosen:
    print(chosen)
' 2>/dev/null || true)"

if [[ -z "${UDID}" ]]; then
  emit_empty
fi

# Cheap gate before spending a simulator boot: empty / placeholder tests.
if ! python3 "$ROOT/scripts/validate-tests.py" >/dev/null 2>&1; then
  DETAIL="$(python3 "$ROOT/scripts/validate-tests.py" 2>&1 || true)"
  python3 -c '
import json, sys
print(json.dumps({
    "followup_message": "Test suite gates failed (empty or placeholder tests). Fix these before continuing.\n\n" + sys.argv[1]
}))
' "$DETAIL"
  exit 0
fi

LOG="$(mktemp -t urbnflicks-tests.XXXXXX)"
trap 'rm -f "$LOG"' EXIT

set +e
xcodebuild test \
  -project TheSilverScreen.xcodeproj \
  -scheme TheSilverScreen \
  -only-testing:TheSilverScreenTests \
  -destination "platform=iOS Simulator,id=${UDID}" \
  >"$LOG" 2>&1
EXIT_CODE=$?
set -e

if [[ "$EXIT_CODE" -eq 0 ]]; then
  emit_empty
fi

python3 -c '
import json, sys

path = sys.argv[1]
try:
    with open(path, "r", errors="replace") as handle:
        text = handle.read()
except Exception:
    text = "xcodebuild test failed; log unavailable."

limit = 4000
if len(text) > limit:
    text = text[-limit:]
    text = "(truncated)\n" + text

print(json.dumps({
    "followup_message": "TheSilverScreenTests failed. Fix the failures, then continue.\n\n" + text
}))
' "$LOG"

exit 0
