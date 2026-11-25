# Shell progress for long commands

Agents must be able to see progress while `xcodebuild`, installs, and other long jobs run. A pipe that buffers until EOF hides that progress and looks like a hang.

## Do not

- Pipe a long-running command into `tail -N` **without** `-f`. `tail -N` waits for the producer to exit, so the terminal log stays empty for the whole build.
- Pipe `tee` into a filter (`cmd | tee log | grep …`). When `grep` matches rarely (most of an `xcodebuild` compile), the pipe buffer fills, `tee` blocks, and the build looks hung while the log file also stops growing.
- Rely on a filtering pipe alone (`… | grep …`) when you also need a full log for diagnosis — grep’s stdout can look idle during compile, and a failed match leaves you with nothing to inspect.

## Do

- End the live command at `tee` so stdout keeps flowing into the session log **and** a file:

```bash
UDID=$(python3 scripts/worktree-simulator.py)
LOG=/tmp/silverscreen-$(basename "$PWD")-search-tests.log
xcodebuild test -scheme SilverScreen \
  -destination "platform=iOS Simulator,id=$UDID" \
  -only-testing:SilverScreenTests/SearchViewModelTests \
  2>&1 | tee "$LOG"
```

- Name logs per worktree (as above). Parallel sessions share `/tmp`, so a fixed name like `/tmp/search-tests.log` gets overwritten by another session's run.
- After the command finishes (or in a **separate** check while it runs), summarize from the file:

```bash
tail -n 40 "$LOG"
grep -E 'Test Case|TEST SUCCEEDED|TEST FAILED|error:.*\.swift' "$LOG" | tail -n 50
```

`tail -f` on the log file is fine for a live follow. The ban is `tail -N` / `grep` **on the live command pipe**.

## The machine-wide job queue

Many sessions share this Mac. `xcodebuild` builds and tests (via the shim in `~/.claude/bin/shims`), the stop hook, `swift build|test`, and `node --test` wait for CPU credits in `~/.claude/bin/slot` before they start.

- `slot: queued for 4 of 10 CPU credits ...` on stderr means the job is waiting its turn. That is normal: it starts by itself. Do not kill it, retry it, or work around the queue by calling `/usr/bin/xcodebuild` directly.
- Give queued commands a long Bash timeout (up to 600000 ms) or run them in the background; a wait of several minutes is expected under load.
- If the shim is not on your PATH (a shell older than the install), queue explicitly: `~/.claude/bin/slot run --credits 4 -- xcodebuild ...`.
- `slot status` shows what is running and waiting.

## DerivedData and test scope

- Do **not** pass `-derivedDataPath` for normal verification. Use Xcode’s default DerivedData so each git worktree stays isolated and warm across runs. Inventing `/tmp/…` DerivedData forces a cold full rebuild and can take minutes.
- Prefer `xcodebuild build-for-testing` then `xcodebuild test-without-building` over a single `xcodebuild test` — the combined command can hang after codesign with no further log.
- Mid-turn checks may use `-only-testing:SilverScreenTests/<ClassUnderChange>`. That is not “suite green.” The stop hook runs the full `SilverScreenTests` target (and skips only when the source fingerprint matches the last pass). To run the full suite yourself, run the hook: `.claude/hooks/run-unit-tests.sh </dev/null` (queued, per-worktree log; no output means green).
