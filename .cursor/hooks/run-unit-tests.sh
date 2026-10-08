#!/usr/bin/env bash
# stop hook: run TheSilverScreenTests against Xcode's default DerivedData (per-worktree).
# Skip xcodebuild when the relevant sources match the last passing fingerprint.
# Fail-open (print {}) if aborted, missing simulator, or unexpected errors.

set -u

PASS_FINGERPRINT_FILE=".cursor/hooks/.last-unit-test-pass"
LOG="/tmp/silverscreen-stop-tests.log"

emit_empty() {
  printf '%s\n' '{}'
  exit 0
}

emit_followup() {
  python3 -c 'import json,sys; print(json.dumps({"followup_message": sys.argv[1]}))' "$1"
  exit 0
}

# If Cursor kills this hook on timeout, tell the agent instead of looking like a pass.
trap 'emit_followup "TheSilverScreenTests stop hook was interrupted (timeout or signal). Re-run tests, then continue. Log: '"$LOG"'"' TERM INT

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

# Cheap gate before spending a simulator run: empty / placeholder tests.
if ! python3 "$ROOT/scripts/validate-tests.py" >/dev/null 2>&1; then
  DETAIL="$(python3 "$ROOT/scripts/validate-tests.py" 2>&1 || true)"
  emit_followup "Test suite gates failed (empty or placeholder tests). Fix these before continuing.

${DETAIL}"
fi

FINGERPRINT="$(python3 -c '
import hashlib
from pathlib import Path

root = Path(".").resolve()
paths = []
for pattern in (
    "TheSilverScreen/**/*.swift",
    "TheSilverScreenTests/**/*.swift",
):
    paths.extend(sorted(root.glob(pattern)))
for extra in (
    "TheSilverScreen.xcodeproj/project.pbxproj",
    "Version.xcconfig",
):
    path = root / extra
    if path.is_file():
        paths.append(path)

digest = hashlib.sha256()
for path in paths:
    rel = path.relative_to(root).as_posix()
    digest.update(rel.encode())
    digest.update(b"\0")
    digest.update(path.read_bytes())
    digest.update(b"\0")
print(digest.hexdigest())
' 2>/dev/null || true)"

if [[ -n "${FINGERPRINT}" && -f "${PASS_FINGERPRINT_FILE}" ]]; then
  LAST="$(tr -d '[:space:]' < "${PASS_FINGERPRINT_FILE}" 2>/dev/null || true)"
  if [[ -n "${LAST}" && "${LAST}" == "${FINGERPRINT}" ]]; then
    emit_empty
  fi
fi

# Do not pass -derivedDataPath: Xcode's default is hashed per project path, so
# each git worktree stays isolated and warm across agent stops.
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
  if [[ -n "${FINGERPRINT}" ]]; then
    printf '%s\n' "${FINGERPRINT}" > "${PASS_FINGERPRINT_FILE}"
  fi
  emit_empty
fi

SUMMARY="$(python3 -c '
import re, sys
from pathlib import Path

path = Path(sys.argv[1])
try:
    text = path.read_text(errors="replace")
except Exception:
    print("xcodebuild test failed; log unavailable at " + sys.argv[1])
    raise SystemExit(0)

lines = text.splitlines()
interesting = []
for line in lines:
    if re.search(
        r"error:|TEST FAILED|TEST SUCCEEDED|failed \(|\*\* TEST|Test Case .* failed",
        line,
    ):
        interesting.append(line)

# Prefer failed test case names near the end.
failed_cases = [
    line for line in lines
    if "Test Case" in line and " failed (" in line
]

chunks = []
if failed_cases:
    chunks.append("Failed tests:\n" + "\n".join(failed_cases[-40:]))
if interesting:
    chunks.append("Signals:\n" + "\n".join(interesting[-60:]))

tail = "\n".join(lines[-80:])
chunks.append("Log tail (" + sys.argv[1] + "):\n" + tail)
print("\n\n".join(chunks))
' "$LOG" 2>/dev/null || true)"

if [[ -z "${SUMMARY}" ]]; then
  SUMMARY="xcodebuild test failed (exit ${EXIT_CODE}); see ${LOG}"
fi

emit_followup "TheSilverScreenTests failed. Fix the failures, then continue.

${SUMMARY}"
