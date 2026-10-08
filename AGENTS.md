# Silver Screen — agent contract

Architecture conventions live in [`.cursor/rules/architecture.mdc`](.cursor/rules/architecture.mdc) and the scoped rules beside it.

## Ground rules

- All UI work is SwiftUI. Do not add UIKit screens.
- No 3rd-party dependencies.
- Add unit tests for completed work.
- Ship work through pull requests. `main` is the branch that ships.
- **PR bodies must follow** [`.github/pull_request_template.md`](.github/pull_request_template.md) in full — see [`.cursor/rules/pull-requests.mdc`](.cursor/rules/pull-requests.mdc). CI runs [`scripts/validate-pr-body.py`](scripts/validate-pr-body.py).
- Commits stay reviewable: one logical unit each — see [`.cursor/rules/commits.mdc`](.cursor/rules/commits.mdc).
- Long-running shell jobs stay observable: `tee` to a log, never `… | tail -N` without `-f` — see [`.cursor/rules/shell-progress.mdc`](.cursor/rules/shell-progress.mdc).

## Pointers

- Architecture: [`.cursor/rules/architecture.mdc`](.cursor/rules/architecture.mdc) (always on), plus scoped rules for concurrency, SwiftUI, data layer, image loading, secrets, errors and logging, accessibility, documentation comments, formatting, tests, commits, pull requests, and shell progress
- Awards shelves and the weekly catalog: [`AWARDS.md`](AWARDS.md)
- Hooks: [`.cursor/hooks.json`](.cursor/hooks.json)
- Harness gates: [`scripts/validate-rules.py`](scripts/validate-rules.py), [`scripts/validate-tests.py`](scripts/validate-tests.py) (empty tests banned), [`scripts/validate-pr-body.py`](scripts/validate-pr-body.py) (PR template sections required)
- Releases: [`RELEASE.md`](RELEASE.md) and [`scripts/release.py`](scripts/release.py) — dev, TestFlight, and App Store share [`Version.xcconfig`](Version.xcconfig)
- PR template: [`.github/pull_request_template.md`](.github/pull_request_template.md)
