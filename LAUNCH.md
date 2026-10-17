# Launch plan

Two lists: what has to happen before the App Store launch, and what comes after it.
Ask Claude to add, remove, move, or check off items ("add widgets to post-launch",
"move onboarding to post-launch", "mark the TMDB logo done") and it edits this file.

## Pre-launch checklist

### Blocker: keep every library change history-safe (done in #37)

Accounts and social come next, and the first sign-in has to upload the library a person
already built, with its real dates. Today every save deletes the whole domain's rows
and inserts them again (`SQLiteLibraryStore.writeLists`, `writeAnnotations`,
`writeTVWatch`). The data itself survives, but the sync columns don't mean anything:

- `updated_at` is reset to "now" on every row whenever anything in that domain is saved,
  so the real date of a rating or review is lost from launch day on. A social feed needs
  that date, and it can't be recovered later.
- `revision` is always 1, so a sync engine can't tell which rows changed.
- Deletes are hard deletes, so there are no tombstones to sync a removal.
- `tv_episode_completed` has no timestamp, so "watched S1E3 on…" is never recorded.

- [x] Change the three writes from delete-and-reinsert to a diff: insert new rows, update
      only rows whose content changed (bump `revision`, set `updated_at`), and tombstone
      removed rows with `deleted_at`. Keep each domain's save one transaction.
- [x] Schema v3: add `created_at` to `library_list` and `annotation`, and `completed_at`
      to `tv_episode_completed`. Backfill from the best date already stored
      (`watched_at`, `added_at`, else the migration time).
- [x] Tests: saving one rating leaves other rows' `updated_at` and `revision` alone;
      removing a list item leaves a tombstone; the v2 to v3 migration keeps every row.
- [x] Update `PERSISTENCE.md` to say rows are now diffed.

### App Store requirements

- [x] Settings screen: feedback, support, privacy policy, data credits, acknowledgements, version
- [x] Privacy manifest declares crash, performance, diagnostic, and feedback data
- [x] `ITSAppUsesNonExemptEncryption = NO`, so uploads skip the export compliance question
- [x] Privacy policy and support pages in `docs/`
- [ ] Turn on GitHub Pages: repo Settings → Pages → Deploy from a branch → `main`, `/docs`.
      Then check that `https://collinbrowse.github.io/Silver-Screen/privacy/` and `/support/` load.
- [ ] Add a support email address to `docs/support.md` (Apple expects contact details on the support URL)
- [ ] Sentry project settings: turn on "Prevent Storing of IP Addresses", so crash reports stay unlinked to a person
- [x] Add the official TMDB logo to Settings → Data Sources (TMDB's attribution rules ask for it)
- [ ] App Store Connect privacy label, matching `PrivacyInfo.xcprivacy`:
      - Not linked to you: Crash Data, Performance Data, Other Diagnostic Data (App Functionality);
        Product Interaction (Analytics)
      - Linked to you: Email Address and Customer Support, only when someone sends feedback with an email (App Functionality)
      - Tracking: none
- [ ] App Store Connect: privacy policy URL, support URL, Entertainment category, copyright, age rating questionnaire
- [ ] App Review notes: no sign-in needed; all data is local
- [ ] Large screens (decided): build the layouts for iPhone Duo first, then use its larger
      screens as the iPad screens. Base each layout on the available width (size classes),
      not on the device model, so one set of views serves both. iPad ships with those layouts
      (`TARGETED_DEVICE_FAMILY` stays `1,2`), and `marketing.py` already captures a 13" iPad set.

### Product

- [ ] Onboarding: a first-launch flow that gets someone to a non-empty library (rate a few
      titles they've seen, start a watchlist) instead of an empty Library tab
- [x] Review prompt: SwiftUI `requestReview` after a good moment, such as the 5th saved rating, at most once per version, never after an error.
      Ratings saved during onboarding (before `onboardingCompletedAt`) do not count.
- [ ] Analytics: pick the tool (see the decision below), then send a handful of anonymous
      events: onboarding finished, first rating, list created, title added to watchlist.
      Declare them on the privacy label as Product Interaction, not linked.
      TelemetryDeck client, events, Settings toggle, and privacy manifest are built. Left:
      create the TelemetryDeck app, set `TELEMETRYDECK_APP_ID` (OBSERVABILITY.md → Product
      analytics), send the onboarding event once onboarding merges, and check signals arrive.

### Infrastructure and automation

- [ ] Move the TMDB token off the device behind a small proxy, so the token can be rotated without an app update:
      1. [x] Write a Cloudflare Worker (free tier) that forwards `/3/*` to `api.themoviedb.org` and adds the bearer token, stored as a Worker secret. Deploy it and set the `TMDB_PROXY_URL` repository variable with [`worker/README.md`](worker/README.md).
      2. [x] Cache responses in the Worker for a few hours, and rate-limit by IP.
      3. [x] Add `TMDB_BASE_URL` to the xcconfig, point `TMDBRequestBuilder` at it, and remove `TMDB_ACCESS_TOKEN` from `Info.plist`. Images keep loading straight from `image.tmdb.org`, which needs no token.
      4. Optional: check an App Attest assertion in the Worker so only the real app can call it.
      5. After the release ships, rotate the token on TMDB, because older test builds contain it.
- [x] Daily TMDB health check: a scheduled GitHub Action calls a few endpoints the app
      uses with the CI token, checks the fields the DTOs decode, and opens an issue on failure
- [x] Weekly digest: a GitHub Action every Monday that pulls downloads, ratings, and new
      reviews from the App Store Connect API, plus crash-free sessions, top issues, and
      feedback count from Sentry, and posts them as a GitHub issue

### Launch

- [ ] Public TestFlight link for a small beta group
- [ ] Apple featuring nomination (App Store Connect → Featuring → Nominations), at least 3 weeks before release day
- [ ] Refresh the `fresh` screenshots in `marketing/titles.json`, then `python3 scripts/marketing.py refresh`
- [ ] No pre-order and no press kit (decided)

### Decision needed: analytics

**Decided (October 16, 2026): TelemetryDeck, through a few lines of `URLSession` against its
v2 ingest API, so Sentry stays the only dependency.** App Store Connect Analytics keeps
covering downloads, conversion, and retention at no cost. Setup and verification are in
[`OBSERVABILITY.md`](OBSERVABILITY.md) under Product analytics.

Sentry reports crashes, errors, and performance. It doesn't do product analytics (funnels,
retention, feature use). Options:

- **App Store Connect Analytics**: free and already there. Downloads, conversion, and
  day-1/7/28 retention for people who share analytics with developers. No code.
- **TelemetryDeck**: privacy-first, made for Apple apps, free tier. It needs either a second
  allowed dependency (its Swift SDK) or a few lines of `URLSession` against its ingest API
  (no new dependency).
- **Your own endpoint**: the Worker from the TMDB proxy could take events too. Cheapest
  over time, but you'd build the dashboards yourself.

Whichever option wins, also keep a metrics history: one place where the weekly digest's
numbers (downloads, ratings, reviews, crash-free rates, feedback) and any product
analytics build up so they can be analyzed and charted over time. It could be plain
storage an AI agent reads to write a report on demand, or a dashboard of its own. Decide
later. Until then, each week's numbers live only in that week's digest issue.

## Post-launch features

### Accounts and social (`ROADMAP.md` phases 2–5)

- [ ] Sync outbox (phase 2), then Sign in with Apple and accounts (phase 3), then sync API (phase 4)
- [ ] First sign-in uploads the whole local library with its original dates. Nothing is lost or reset.
- [ ] Watched and Watchlist merge by kind when someone signs in on a second device
- [ ] Ratings and notes stay private by default. Anything written before accounts existed
      is never published without the person choosing to.
- [ ] Follows, shared lists (with who added each item), public ratings and reviews, activity feed (phase 5)
- [ ] Account deletion inside the app (Apple requires it once accounts exist)

### Growth

- [ ] Import from Letterboxd (CSV), Trakt, IMDb ratings, TV Time
- [ ] Share cards: a rating, review, or list as an image for stories and messages
- [ ] App Store In-App Events for Oscar nominations (late January) and the ceremony (March)

### Retention

- [ ] Diary: watch dates and rewatches (needed before import can keep Letterboxd history)
- [ ] Local notifications: a new episode of a show in progress, a watchlist title arriving on your services
- [ ] "My services": pick your subscriptions and filter Browse and Watchlist to them
- [ ] Widgets: next episode, watchlist pick
- [ ] Stats and Year in Review

### Making money

- [ ] TMDB commercial agreement before any paid tier or ads; ask about JustWatch data at the same time
- [ ] Silver Screen Pro with StoreKit 2 (first-party, no new dependency): widgets, stats, notifications, later sync
- [ ] Pricing: one-time vs. yearly; free trial
- [ ] No ads

### Data

- [ ] Export the library as CSV and JSON for portability (after accounts; iCloud device backups cover phone loss until then)

### Quality

- [ ] Offline handling: a reachability check so the app responds when the network drops
- [ ] Snapshot tests for `Design/` components
- [ ] Localization (TMDB already serves localized titles and overviews)

### Automation

- [ ] Upload App Store metadata and screenshots through the App Store Connect API instead of pasting them
- [ ] Submit for review through the API (`release.py` stops at "submit in App Store Connect" today)
- [ ] Hold the phased rollout automatically if crash-free sessions drop below a threshold
