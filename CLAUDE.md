# Silver Screen — agent contract

Architecture conventions live in [`.claude/rules/architecture.md`](.claude/rules/architecture.md) and the rules beside it. Rules without `paths` frontmatter load every session; the rest load when Claude works on matching files.

## Ground rules

- All UI work is SwiftUI. Do not add UIKit screens.
- No 3rd-party dependencies **except Sentry** (Cocoa via SPM in the Xcode project). See [`.claude/rules/observability.md`](.claude/rules/observability.md).
- Add unit tests for completed work.
- Ship work through pull requests. `main` is the branch that ships.
- Turn on **Auto-fix** for every PR right after opening it — see [`.claude/rules/pull-requests.md`](.claude/rules/pull-requests.md).
- **PR bodies must follow** [`.github/pull_request_template.md`](.github/pull_request_template.md) in full — see [`.claude/rules/pull-requests.md`](.claude/rules/pull-requests.md). CI runs [`scripts/validate-pr-body.py`](scripts/validate-pr-body.py).
- Commits stay reviewable: one logical unit each — see [`.claude/rules/commits.md`](.claude/rules/commits.md).
- **Never push to a branch that has an open PR** unless the user asks for that push or it's an Auto-fix response to a CI-monitor event — commit locally and let them push (each push burns a CI run). See [`.claude/rules/commits.md`](.claude/rules/commits.md#pushing).
- A feature commit does not bump the version. Versions change only through `python3 scripts/release.py` — see [`.claude/rules/releases.md`](.claude/rules/releases.md).
- Long-running shell jobs stay observable: `tee` to a log, never `… | tail -N` without `-f` — see [`.claude/rules/shell-progress.md`](.claude/rules/shell-progress.md).
- For `xcodebuild test`, do **not** pass `-derivedDataPath` (cold rebuilds). Prefer `-only-testing:SilverScreenTests/<Class>` mid-turn; the stop hook still owns the full suite — see [`.claude/rules/shell-progress.md`](.claude/rules/shell-progress.md).

## Pointers

- Launch plan: [`LAUNCH.md`](LAUNCH.md) holds the pre-launch checklist and the post-launch feature list. When the user asks to add, remove, move, or check off an item on either list, edit that file and keep its sections.
- Rules in [`.claude/rules/`](.claude/rules/): architecture, commits, documentation comments, pull requests, shell progress, and simulator are always on. Concurrency, SwiftUI, UIKit, data layer, image loading, secrets, errors and logging, observability, accessibility, formatting, tests, and releases load for the files they cover.
- Awards shelves and the weekly catalog: [`AWARDS.md`](AWARDS.md)
- Hooks: [`.claude/settings.json`](.claude/settings.json) — the Stop hook runs `SilverScreenTests` via [`.claude/hooks/run-unit-tests.sh`](.claude/hooks/run-unit-tests.sh) (warm default DerivedData; skips when the source fingerprint matches the last pass); the PreToolUse Bash hook [`.claude/hooks/block-third-party-deps.sh`](.claude/hooks/block-third-party-deps.sh) blocks non-Sentry third-party deps
- Harness gates: [`scripts/validate-rules.py`](scripts/validate-rules.py) (rule frontmatter, links, hooks, and Sentry-only SPM), [`scripts/validate-tests.py`](scripts/validate-tests.py) (empty tests banned), [`scripts/validate-pr-body.py`](scripts/validate-pr-body.py) (PR template sections required)
- Releases: [`RELEASE.md`](RELEASE.md) and [`scripts/release.py`](scripts/release.py) — dev, TestFlight, and App Store share [`Version.xcconfig`](Version.xcconfig); `testflight/*` tags ship via [`.github/workflows/release.yml`](.github/workflows/release.yml)
- Observability: [`.claude/rules/observability.md`](.claude/rules/observability.md) and [`OBSERVABILITY.md`](OBSERVABILITY.md)
- PR template: [`.github/pull_request_template.md`](.github/pull_request_template.md)
