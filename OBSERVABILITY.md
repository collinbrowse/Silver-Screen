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

## Scheduled checks

Two GitHub Actions file issues instead of sending email. Both run from
Actions → Run workflow too.

| Workflow | When | Files |
| --- | --- | --- |
| [`tmdb-health.yml`](.github/workflows/tmdb-health.yml) | Daily, 13:00 UTC | On failure, a comment on the open `tmdb-health` issue, or a new one. Close the issue once it's fixed. |
| [`weekly-digest.yml`](.github/workflows/weekly-digest.yml) | Monday, 15:00 UTC | A `weekly-digest` issue titled “Weekly digest – <date>” for the previous Monday–Sunday |

[`scripts/tmdb_health.py`](scripts/tmdb_health.py) calls the movie, collection,
review, TV series/season/episode, watch provider, person, now playing,
upcoming, on the air, and search endpoints with the same `append_to_response`
sections as the app, and checks every field the DTOs in
`SilverScreen/Data/Networking` decode. When a DTO changes, change its schema
there too.

[`scripts/weekly_digest.py`](scripts/weekly_digest.py) shows week-over-week
change by reading a hidden metrics block from the previous digest issue.
Crash-free change is shown only when both weeks cover the same release. Before
launch the App Store sections say there is no data yet. Preview the body
locally with `python3 scripts/weekly_digest.py --dry-run`.

Repository secrets:

| Secret | Used by | Purpose |
| --- | --- | --- |
| `TMDB_ACCESS_TOKEN` | TMDB health | Same token as the release job |
| `ASC_KEY_ID` / `ASC_ISSUER_ID` / `ASC_API_KEY_P8` | Digest | Same App Store Connect key as the release job. Sales reports need the Admin, Finance, or Sales role. |
| `ASC_VENDOR_NUMBER` | Digest | Sales and Trends vendor number (App Store Connect → Payments and Financial Reports, top left). Without it the digest skips downloads. |
| `SENTRY_AUTH_TOKEN` | Digest | Same token as dSYM upload. Needs `org:read`, `project:read`, `project:releases`, and `event:read`. |
| `SENTRY_ORG` / `SENTRY_PROJECT` | Digest | Organization and project slugs |

`GITHUB_TOKEN` comes from Actions; each workflow asks for `issues: write`.
The average rating comes from the public iTunes lookup API (US storefront),
because the App Store Connect API has reviews but no aggregate rating.

## Alerts (configure in Sentry UI)

- Crash-free session rate drops on a new release.
- Spike in error events tagged `category:networking` or `category:persistence`.

Do not enable Session Replay or user identification without a product decision.
