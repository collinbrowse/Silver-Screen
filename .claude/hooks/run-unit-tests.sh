#!/usr/bin/env bash
# Claude Code Stop hook: run SilverScreenTests against Xcode's default DerivedData (per-worktree).
# Skip xcodebuild when the relevant sources match the last passing fingerprint.
# Otherwise wait in the machine-wide job queue (~/.claude/bin/slot) for 4 CPU credits, then
# build-for-testing + test-without-building on this checkout's own simulator
# (scripts/worktree-simulator.py). Two runs in the same checkout never overlap.
# Fail-open (exit 0, no output) if there is no simulator or something unexpected breaks.
# A failure blocks the stop with {"decision": "block", "reason": ...} so Claude fixes it.
#
# Run by hand (queued like the hook): .claude/hooks/run-unit-tests.sh </dev/null
# Prints nothing when green, a {"decision": "block"} JSON line with the failures otherwise.

set -u

PASS_FINGERPRINT_FILE=".claude/hooks/.last-unit-test-pass"
SLOT="${SILVERSCREEN_SLOT:-$HOME/.claude/bin/slot}"
RUNNER_PID=""

emit_empty() {
  exit 0
}

emit_followup() {
  python3 -c 'import json,sys; print(json.dumps({"decision": "block", "reason": sys.argv[1]}))' "$1"
  exit 0
}

on_interrupt() {
  if [[ -n "${RUNNER_PID}" ]]; then
    kill -TERM "${RUNNER_PID}" 2>/dev/null || true
    wait "${RUNNER_PID}" 2>/dev/null || true
    RUNNER_PID=""
  fi
  emit_followup "SilverScreenTests stop hook was interrupted (timeout or signal) before the suite finished — do not treat this as green. Do not start an unqueued \`xcodebuild\` yourself. Re-run the hook through the machine queue: \`.claude/hooks/run-unit-tests.sh </dev/null\` with a long Bash timeout (or in the background); \`slot: queued ...\` lines mean it is waiting its turn, which is normal. Log: ${LOG:-the per-checkout /tmp/silverscreen-stop-tests-*.log}"
}

# Internal: the queued job. Runs inside `slot run` so both xcodebuild steps share one slot.
# Exit 0 = green, 3 = build-for-testing failed, 4 = tests failed.
if [[ "${1:-}" == "--queued-run" ]]; then
  UDID="$2"
  LOG="$3"
  CHILD=""
  trap '[[ -n "${CHILD}" ]] && kill -TERM "${CHILD}" 2>/dev/null; wait 2>/dev/null; exit 143' TERM INT HUP
  cd "$(dirname "$0")/../.." || exit 3
  : >"$LOG"
  # Boot the sim up front so install/launch is not starting from a cold device.
  xcrun simctl boot "${UDID}" >/dev/null 2>&1 || true
  # Split build + test. A single `xcodebuild test` often hangs after codesign on this
  # toolchain. -jobs 4 matches the 4 credits this job holds in the queue.
  # Do not pass -derivedDataPath: Xcode's default is hashed per project path.
  xcodebuild build-for-testing \
    -project SilverScreen.xcodeproj \
    -scheme SilverScreen \
    -destination "platform=iOS Simulator,id=${UDID}" \
    -jobs 4 \
    >>"$LOG" 2>&1 &
  CHILD=$!
  wait "${CHILD}" || exit 3
  xcodebuild test-without-building \
    -project SilverScreen.xcodeproj \
    -scheme SilverScreen \
    -only-testing:SilverScreenTests \
    -destination "platform=iOS Simulator,id=${UDID}" \
    -parallel-testing-enabled NO \
    >>"$LOG" 2>&1 &
  CHILD=$!
  wait "${CHILD}" || exit 4
  exit 0
fi

# Claude Code sends TERM on hook timeout. Do not trap INT — a child interrupt must not
# look like a hook timeout and kick off another agent loop.
trap on_interrupt TERM

INPUT="$(cat || true)"

# The hook runs again after Claude fixes a failure (stop_hook_active is true then), so a
# fix is proven before the turn ends. Claude Code caps consecutive blocks, so a failure
# Claude cannot fix still lets the turn end.

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT" || emit_empty
SELF="$ROOT/.claude/hooks/run-unit-tests.sh"

# Fingerprint first: when nothing relevant changed since the last pass, do not queue.
FINGERPRINT="$(python3 -c '
import hashlib
from pathlib import Path

root = Path(".").resolve()
paths = []
for pattern in (
    "SilverScreen/**/*.swift",
    "SilverScreenTests/**/*.swift",
):
    paths.extend(sorted(root.glob(pattern)))
for extra in (
    "SilverScreen.xcodeproj/project.pbxproj",
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

# Cheap gate before spending a simulator run: empty / placeholder tests.
if ! python3 "$ROOT/scripts/validate-tests.py" >/dev/null 2>&1; then
  DETAIL="$(python3 "$ROOT/scripts/validate-tests.py" 2>&1 || true)"
  emit_followup "Test suite gates failed (empty or placeholder tests). Fix these before continuing.

${DETAIL}"
fi

# This checkout's own simulator (`SilverScreen <worktree>`), created on first use.
UDID="$(python3 "$ROOT/scripts/worktree-simulator.py" 2>/dev/null || true)"
if [[ -z "${UDID}" ]]; then
  emit_empty
fi

CHECKOUT="$(python3 "$ROOT/scripts/worktree-simulator.py" --name 2>/dev/null | sed 's/^[^ ]* //; s/[^A-Za-z0-9._-]/_/g')"
CHECKOUT="${CHECKOUT:-main}"
LOG="/tmp/silverscreen-stop-tests-${CHECKOUT}.log"

# Wait for a turn in the machine-wide queue instead of failing fast: under load the run
# just starts later. The lock keeps two runs in this checkout from overlapping.
if [[ -x "${SLOT}" ]]; then
  "${SLOT}" run --credits 4 --lock "silverscreen-${CHECKOUT}" \
    --label "SilverScreen stop-hook unit tests" --kind "xcodebuild test · SilverScreenTests" \
    -- "${SELF}" --queued-run "${UDID}" "${LOG}" &
elif command -v lockf >/dev/null 2>&1; then
  # No queue installed: still one run per checkout (lockf waits for the lock).
  lockf "/tmp/silverscreen-stop-tests-${CHECKOUT}.lock" "${SELF}" --queued-run "${UDID}" "${LOG}" &
else
  "${SELF}" --queued-run "${UDID}" "${LOG}" &
fi
RUNNER_PID=$!
wait "${RUNNER_PID}"
RUN_EXIT=$?
RUNNER_PID=""

if [[ "$RUN_EXIT" -ge 128 ]]; then
  emit_followup "SilverScreenTests run was killed (exit ${RUN_EXIT}) before the suite finished — do not treat this as green. Do not start an unqueued \`xcodebuild\` yourself; re-run the hook through the machine queue: \`.claude/hooks/run-unit-tests.sh </dev/null\` with a long Bash timeout. Log: ${LOG}"
fi

if [[ "$RUN_EXIT" -eq 3 ]]; then
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
  emit_followup "SilverScreenTests build-for-testing failed. Fix the failures, then continue. To re-check before the turn ends, run \`.claude/hooks/run-unit-tests.sh </dev/null\` (queued; long Bash timeout) or a narrowed \`xcodebuild -only-testing:SilverScreenTests/<Class>\` on your worktree simulator.

${SUMMARY:-see ${LOG}}"
fi

if [[ "$RUN_EXIT" -eq 0 ]]; then
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
  SUMMARY="xcodebuild test failed (exit ${RUN_EXIT}); see ${LOG}"
fi

emit_followup "SilverScreenTests failed. Fix the failures, then continue. To re-check before the turn ends, run \`.claude/hooks/run-unit-tests.sh </dev/null\` (queued; long Bash timeout) or a narrowed \`xcodebuild -only-testing:SilverScreenTests/<Class>\` on your worktree simulator.

${SUMMARY}"
