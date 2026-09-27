# The Silver Screen — agent contract

This file is the source of truth for the assessment constraints. Follow them. Architecture conventions live in [`.cursor/rules/architecture.mdc`](.cursor/rules/architecture.mdc) and the scoped rules beside it. Do not add optional epic recommendations beyond what Nuuly already wrote.

## Required work (in order)

Only the following is required. Everything else in [`Requirements/`](Requirements/README.md) is optional.

1. Complete the [Top Movies](Requirements/top-movies.md) epic first.
2. Then complete stories **1 and 2** of [Favorites & Bookmarking](Requirements/favorites.md).

Do **not** try to finish the backlog. Judgment and craft matter more than completion count.

## Ground rules

- All **new** work is SwiftUI.
- The app UI is SwiftUI. Do not add UIKit screens. Top Movies is no longer a visible screen.
- No 3rd-party dependencies.
- Add unit tests for completed work.
- Tick `Done` on a story (and update the progress table in [`Requirements/README.md`](Requirements/README.md)) only after verification: unit tests plus a visual check.

## How we work in this repo

- This harness lives in the repo and is part of the workflow.
- PRs are encouraged. Reviewers look at `main`, so completed work must land there.
- **PR bodies must follow** [`.github/pull_request_template.md`](.github/pull_request_template.md) in full — see [`.cursor/rules/pull-requests.mdc`](.cursor/rules/pull-requests.mdc). CI runs [`scripts/validate-pr-body.py`](scripts/validate-pr-body.py).
- Commits stay reviewable: one story or logical unit each — see [`.cursor/rules/commits.mdc`](.cursor/rules/commits.mdc).

## Pointers (do not duplicate architecture here)

- Architecture: [`.cursor/rules/architecture.mdc`](.cursor/rules/architecture.mdc) (always on), plus scoped rules for concurrency, SwiftUI, data layer, image loading, secrets, errors and logging, accessibility, documentation comments, tests, commits, and pull requests
- Skills: [`.cursor/skills/implement-story/`](.cursor/skills/implement-story/SKILL.md), [`.cursor/skills/visual-qa/`](.cursor/skills/visual-qa/SKILL.md)
- Hooks: [`.cursor/hooks.json`](.cursor/hooks.json)
- Harness gates: [`scripts/validate-rules.py`](scripts/validate-rules.py), [`scripts/validate-tests.py`](scripts/validate-tests.py) (empty tests banned; Done requires test changes), [`scripts/validate-pr-body.py`](scripts/validate-pr-body.py) (PR template sections required)
- Releases: [`RELEASE.md`](RELEASE.md) and [`scripts/release.py`](scripts/release.py) — dev, TestFlight, and App Store share [`Version.xcconfig`](Version.xcconfig)
- PR template: [`.github/pull_request_template.md`](.github/pull_request_template.md)
