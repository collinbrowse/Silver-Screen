#!/usr/bin/env bash
# stop hook: run TheSilverScreenTests against Xcode's default DerivedData (per-worktree).
# Skip xcodebuild when the relevant sources match the last passing fingerprint.
# Fail-open (print {}) if aborted, missing simulator, or unexpected errors.

set -u

PASS_FINGERPRINT_FILE=".cursor/hooks/.last-unit-test-pass"
LOCK_DIR="/tmp/silverscreen-stop-tests.lock"
LOG="/tmp/silverscreen-stop-tests.log"
XCODEBUILD_PID=""
LOCK_HELD=0

emit_empty() {
  printf '%s\n' '{}'
  exit 0
}

emit_followup() {
  python3 -c 'import json,sys; print(json.dumps({"followup_message": sys.argv[1]}))' "$1"
  exit 0
}

release_lock() {
  if [[ "${LOCK_HELD}" -eq 1 ]]; then
    rm -rf "${LOCK_DIR}" 2>/dev/null || true
    LOCK_HELD=0
  fi
}

on_interrupt() {
  if [[ -n "${XCODEBUILD_PID}" ]]; then
    kill "${XCODEBUILD_PID}" 2>/dev/null || true
    wait "${XCODEBUILD_PID}" 2>/dev/null || true
    XCODEBUILD_PID=""
  fi
  release_lock
  emit_followup "TheSilverScreenTests stop hook was interrupted (timeout or signal). The suite did not finish — do not treat this as green. Re-run \`xcodebuild test\` for TheSilverScreenTests (no -derivedDataPath), then continue. Log: ${LOG}"
}

# Cursor sends TERM on hook timeout. Do not trap INT — a child interrupt must not
# look like a hook timeout and kick off another agent loop.
trap on_interrupt TERM
trap release_lock EXIT

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

# One stop-hook xcodebuild at a time across chats/worktrees sharing this Mac.
# mkdir is atomic; clear a stale lock if the recorded pid is dead.
if ! mkdir "${LOCK_DIR}" 2>/dev/null; then
  OLD_PID="$(cat "${LOCK_DIR}/pid" 2>/dev/null || true)"
  if [[ -n "${OLD_PID}" ]] && ! kill -0 "${OLD_PID}" 2>/dev/null; then
    rm -rf "${LOCK_DIR}" 2>/dev/null || true
  fi
  if ! mkdir "${LOCK_DIR}" 2>/dev/null; then
    emit_followup "TheSilverScreenTests stop hook skipped: another unit-test run already holds ${LOCK_DIR}. Wait for it to finish (or inspect ${LOG}), then continue."
  fi
fi
printf '%s\n' "$$" > "${LOCK_DIR}/pid"
LOCK_HELD=1

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

# Boot preferred sim up front so install/launch is not starting from a cold device.
xcrun simctl boot "${UDID}" >/dev/null 2>&1 || true

# Split build + test. A single `xcodebuild test` often hangs after codesign on this
# toolchain (no further log until Cursor's stop-hook timeout). build-for-testing +
# test-without-building completes in tens of seconds once DerivedData is warm.
# Do not pass -derivedDataPath: Xcode's default is hashed per project path.
: >"$LOG"
set +e
xcodebuild build-for-testing \
  -project TheSilverScreen.xcodeproj \
  -scheme TheSilverScreen \
  -destination "platform=iOS Simulator,id=${UDID}" \
  >>"$LOG" 2>&1 &
XCODEBUILD_PID=$!
wait "${XCODEBUILD_PID}"
BUILD_EXIT=$?
XCODEBUILD_PID=""
set -e

if [[ "$BUILD_EXIT" -ne 0 ]]; then
  SUMMARY="$(python3 -c '
import re, sys
from pathlib import Path
path = Path(sys.argv[1])
try:
    text = path.read_text(errors="replace")
except Exception:
    print("build-for-testing failed; log unavailable at " + sys.argv[1])
    raise SystemExit(0)
lines = text.splitlines()
interesting = [line for line in lines if re.search(r"error:|BUILD FAILED|\*\* BUILD|BUILD INTERRUPTED", line)]
chunks = []
if interesting:
    chunks.append("Signals:\n" + "\n".join(interesting[-60:]))
chunks.append("Log tail (" + sys.argv[1] + "):\n" + "\n".join(lines[-80:]))
print("\n\n".join(chunks))
' "$LOG" 2>/dev/null || true)"
  emit_followup "TheSilverScreenTests build-for-testing failed. Fix the failures, then continue.

${SUMMARY:-see ${LOG}}"
fi

set +e
xcodebuild test-without-building \
  -project TheSilverScreen.xcodeproj \
  -scheme TheSilverScreen \
  -only-testing:TheSilverScreenTests \
  -destination "platform=iOS Simulator,id=${UDID}" \
  -parallel-testing-enabled NO \
  >>"$LOG" 2>&1 &
XCODEBUILD_PID=$!
wait "${XCODEBUILD_PID}"
EXIT_CODE=$?
XCODEBUILD_PID=""
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
        r"error:|TEST FAILED|TEST SUCCEEDED|failed \(|\*\* TEST|Test Case .* failed|BUILD INTERRUPTED",
        line,
    ):
        interesting.append(line)

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
