# Observability

Sentry is the only third-party SDK. Agent rules live in
[`.cursor/rules/observability.mdc`](.cursor/rules/observability.mdc).

## Release health

Each TestFlight / App Store build should appear in Sentry as release
`<MARKETING_VERSION>+<BUILD>` (same numbers as `testflight/<marketing>+<build>`).

After a cut uploads:

1. Confirm the release exists and dSYMs are processed.
2. Watch crash-free sessions for that release on TestFlight before `promote`.
3. After App Store phased release starts, watch the same release for regressions.

## Bad build runbook

| Situation | Action |
| --- | --- |
| TestFlight build is bad | Do **not** `promote`. Cut a fix; new `testflight/` tag uploads a new build. |
| App Store phased release is bad | `python3 scripts/release.py rollout --halt` (pauses phased exposure). Fix, cut, upload, promote/retarget as in [`RELEASE.md`](RELEASE.md). |
| Crash spike on a release | Open the Sentry release → top issues → map to changelog PRs for that `testflight/` tag. |

## Alerts (configure in Sentry UI)

- Crash-free session rate drops on a new release.
- Spike in error events tagged `category:networking` or `category:persistence`.

Do not enable Session Replay or user identification without a product decision.
