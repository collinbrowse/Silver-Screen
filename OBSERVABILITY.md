# Observability

Sentry is the only third-party SDK. Product analytics go to TelemetryDeck
through first-party code, with no SDK. Agent rules live in
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
| `SENTRY_READ_TOKEN` | Digest | Read-only Sentry token with `org:read`, `project:read`, and `event:read`. Kept apart from the release job's `SENTRY_AUTH_TOKEN`, which uploads dSYMs and has write access. The workflow passes it to the script as `SENTRY_AUTH_TOKEN`. |
| `SENTRY_ORG` / `SENTRY_PROJECT` | Digest | Organization and project slugs |

`GITHUB_TOKEN` comes from Actions; each workflow asks for `issues: write`.
The average rating comes from the public iTunes lookup API (US storefront),
because the App Store Connect API has reviews but no aggregate rating.

## Product analytics

[TelemetryDeck](https://telemetrydeck.com/) counts sessions and four anonymous
events. The app
posts them to the [v2 ingest API](https://telemetrydeck.com/docs/ingest/v2) with
`URLSession` in
[`TelemetryDeckClient.swift`](SilverScreen/Data/Networking/TelemetryDeckClient.swift);
the events and the opt-out are in [`Analytics.swift`](SilverScreen/Support/Analytics.swift).

| Signal type | Sent when | Sent from |
| --- | --- | --- |
| `TelemetryDeck.Session.started` | Launch, and returning after more than 5 minutes in the background (the SDK's rule) | `AnalyticsSessionTracker`, called by `SceneDelegate` |
| `TelemetryDeck.Acquisition.newInstallDetected` | Just before the first session (again after turning sharing back on) | `TelemetryDeckClient` |
| `Onboarding.finished` | Onboarding's last step is finished (not skipped) | `OnboardingGate.finish()`, once onboarding (#43) merges — see below |
| `Library.firstRatingSaved` | A score is saved and no other title had one | `AnnotationsRepository.save` / `saveScore` |
| `Library.listCreated` | A custom list is created | `ListsRepository.createList` |
| `Library.titleAddedToWatchlist` | A title is newly put on Watchlist | `ListsRepository` add and toggle |

The two `TelemetryDeck.` types use the SDK's names, so the dashboard's built-in
session, active-user, and retention charts work without the SDK. The repositories
send the `Library.*` events after the write is saved, so every screen that saves
reports the same way and a failed save sends nothing.

Each signal carries the app ID, a SHA-256 of a random per-install UUID
(`clientUser`), the session ID (new each session), the type, and these fields,
named as the SDK names them:

| Fields | Values |
| --- | --- |
| `TelemetryDeck.AppInfo.*` | Version and build |
| `TelemetryDeck.Device.*` | Model identifier (`iPhone17,3`; a simulator reports the model it simulates), iOS version, platform, orientation (`Portrait` / `Landscape` / `Unknown`), screen size in points |
| `TelemetryDeck.Acquisition.firstSessionDate` | Day of the first session, `yyyy-MM-dd` |
| `TelemetryDeck.Retention.*` | Total sessions, distinct days used, distinct days in the last 30 |

Never a title, list name, rating, note, or search. A model identifier is shared by
every device of that model, so it does not single anyone out. TelemetryDeck salts
and hashes `clientUser` again on arrival. `SceneDelegate` reports orientation and
screen size (UIKit stays in the delegates); signals sent before it first reports
leave those fields out. Session and day counts live in UserDefaults. Settings →
Share Anonymous Usage turns it all off and forgets the install UUID and the counts,
so turning it back on looks like a new install. Events wait about 5 seconds in memory and
go up as one request. Offline or 5xx uploads retry with backoff (30 s doubling
to 15 min); a 4xx is dropped. Nothing is written to disk, so events queued when
the app is killed are lost — fine for counts.

Debug builds (simulator, Xcode runs, unit tests) send in TelemetryDeck's **test
mode**, so they never reach production charts. Release builds (TestFlight and
App Store) send production signals. Demo launches for marketing screenshots send
nothing. With no app ID, analytics is off and sends nothing.

### Setup

1. In the [TelemetryDeck dashboard](https://dashboard.telemetrydeck.com/), create
   the app "Silver Screen" and copy its **App ID** (a UUID) from the app's settings.
2. Locally, add it to the gitignored `Secrets.xcconfig`:
   `TELEMETRYDECK_APP_ID = <the UUID>` (template:
   [`Secrets.example.xcconfig`](Secrets.example.xcconfig)).
3. For TestFlight and App Store builds, add the repository secret
   `TELEMETRYDECK_APP_ID`. [`release.yml`](.github/workflows/release.yml) writes it
   into `Secrets.xcconfig` and warns when it is missing.
   `scripts/release.py archive` fails if the archived ID is set but is not a UUID.

The app ID is not a credential (it ships in the binary), but it lives with the
other per-environment values so a fresh clone sends nothing.

### Verify signals arrive

1. Build and run a Debug build with the app ID set.
2. Create a list, add a title to Watchlist, and rate a title in a library that has no ratings.
3. Within a few seconds, open TelemetryDeck, turn on **Test Mode** in the dashboard,
   and check Explore → Recent Signals for `TelemetryDeck.Session.started`,
   `TelemetryDeck.Acquisition.newInstallDetected`, and the `Library.*` types. Open
   one and check its payload has the model, orientation, and retention fields.
4. After the first TestFlight build, turn Test Mode off and check the same signals
   arrive from a TestFlight install.

### Onboarding event

Onboarding is in PR #43, not on `main`. After it merges:

1. Add `analytics: any AnalyticsClient` to `OnboardingGate`'s init and pass
   `dependencies.analytics` where `SceneDelegate` builds the gate.
2. In `OnboardingGate.finish()`, call `analytics.send(.onboardingFinished)` after
   `marker.markCompleted()`. Do not send it from `skip()`.
3. Add an `OnboardingGateTests` case with `SpyAnalyticsClient` asserting
   `finish()` sends `[.onboardingFinished]` and `skip()` sends nothing.

### Adding an event

Add a case to `AnalyticsEvent` with a `Scope.eventName` raw value (leave the
`TelemetryDeck.` scope to the SDK names above), send it where the action is saved,
add a test with `SpyAnalyticsClient`, and add it to the table above. Keep it a
bare count: no payload from user content. A new device or app field goes in
`TelemetryDeckSignalFactory.defaultPayload` (fixed per launch) or
`AnalyticsDisplay` (changes during a launch), under the SDK's key when it has one. If it measures a
new kind of data, update `PrivacyInfo.xcprivacy`, the privacy policy in
[`docs/privacy.md`](docs/privacy.md), and the App Store privacy label.

## Alerts (configure in Sentry UI)

- Crash-free session rate drops on a new release.
- Spike in error events tagged `category:networking` or `category:persistence`.

Do not enable Session Replay or user identification without a product decision.
