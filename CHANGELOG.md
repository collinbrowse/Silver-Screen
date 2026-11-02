# Changelog

`scripts/release.py cut` records one bullet per merged pull request since the
latest ancestor `testflight/*` tag (PR title from the merge). Optional bullets
under **Unreleased** are prepended when you want curated wording above that
list.

## [Unreleased]

## [0.1.1+9] - 2026-11-02

- Upgrade Sentry Cocoa to 9.30.2.
- Movie/TV tag on full-screen lists, and stack the watched eye at accessibility sizes.
- Marketing pipeline: App Store screenshots and website demo clips.
- Keep every library change history-safe: diffed writes and schema v3.
- Add a daily TMDB health check and a weekly digest.
- Add Settings with in-app feedback, privacy declarations, support pages, and the launch plan.
- Move the TMDB token off the device behind a Cloudflare Worker proxy.
- Add the TMDB logo to Settings and an App Store review prompt.
- Analytics: anonymous TelemetryDeck events with no new dependency.
- Add first-launch onboarding that fills Watched and Watchlist.
- Check off Analytics in LAUNCH.md.
- Review fixes: keep search text out of Sentry, tag debug runs.
- Review fixes: stale image assignment and size-keyed image cache.
- Review fixes: Worker path allow-list, CI supply chain, digest resilience.
- Review fixes: networking cancellation, 4xx retry, and lossy decoding.
- Launch-readiness review (CODE_REVIEW.md) and persistence fixes.
- Onboarding: favor widely seen titles and show the cover from the first frame.
- Diary: log watch dates and rewatches (schema v4).
- Lay out every screen for large screens (iPhone Duo inner screen, iPad).
- Use the app icon's film strip as the loading animation.
- Return a cancelled first load to idle so detail screens don't spin forever.
- Move the agent harness from Cursor to Claude Code, and enforce formatting and pre-PR review with hooks.
- Drop stale award-titles pages when Winners/Nominees changes (S2).
- Fix TMDB health proxy check blocked by Cloudflare Error 1010.
- Keep infinite scroll working after a failure, and stop score stamps reverting pages (S3, S4).
- Make startup failures visible and recoverable (O3).
- Fix two crash traps: duplicate episode numbers and corrupt stored scores (S8, N11).
- Watch logging and diary: rating slider, TV episodes, title history, automatic rewatches.
- Library: open only the tapped list on a multi-column row.
- Start the loading animation the moment it appears.
- One way to log watches.
- Add a New Trailers filter to Browse.
- Remove the Movies / TV picker from In Progress.

## [0.1.1+8] - 2026-10-14

- Reuse one development certificate and fix the TestFlight upload key.
- Fix TestFlight notes sync and Sentry dSYM upload.

## [0.1.1+7] - 2026-10-14

- Replace JSON library files with SQLite Phase 1.
- Stage 3–4: Sentry observability and release automation.
- Authenticate TMDB with a bearer token.

## [0.1.1+6] - 2026-10-13

- Fix Watched toggle flashing Couldn't Save on every successful tap.

## [0.1.1+5] - 2026-10-12

- Collapse long award lists behind Show more.
- Fix blank Watched/Watchlist posters from sparse list snapshots.
- Unified Search: Spotify-style preview, View all, and people-first emphasis.
- Compact hero and catalog metadata for movies and TV.
- Combine rating and note into one editor.
- Add episode-level TV watch progress with In Progress.
- Rename TheSilverScreen to SilverScreen.

## [0.1.1+4] - 2026-10-02

- Movie and TV detail show where a title streams (flatrate providers), with logos you can tap to open the service app or App Store.
- Search adds genre shelves that open a browse-style list for that genre.
- Search no longer crashes when running the iOS app on Mac.

## [0.1.1+3] - 2026-09-28

- A person's page leads with the work they are known for, and credits in that role rank ahead of a guest spot on a popular show.
- Search ranks a near-miss name ahead of other hits, so Christopher Waltz still finds Christoph Waltz.
- A person's prizes show on their page, with the trophy, the category, and the title they were for. Movie and series prizes use that same awards card.
- Saving a personal score adds the movie to Watched, including scores saved before this rule.
- The navigation bar on hero screens blurs only after the title scrolls into it.
- List separators appear only between rows.

## [0.1.1+2] - 2026-09-28

- Browse Oscar, BAFTA, and Emmy winners from Search, and see those awards on the title.
- Save movies, series, and people to a Library of lists: Watched, Watchlist, and lists you create. Favorites is gone, and an existing favorites file is not imported.
- Search keeps the query after you open a result.
- Movie detail stays on screen when a trailer pill is wider than the column beside the poster.
- Detail screens use a full-bleed backdrop. Genre pills sit under the poster and trailer pills under the title. The separate images row is gone.
- A trailer pill shows a spinner as soon as it is tapped.
- Genres show as pills, and each official YouTube trailer plays from its own pill. List rows show genres as comma-separated text.
- Save a personal score and note on movies, series, seasons, and episodes. That score shows again on the lists you return to.
- TV detail shows the TMDB user score, or that none is available, and opens series and season posters full screen. Season titles no longer repeat the number TMDB already includes.

## [0.1.1] - 2026-09-27

- Starting point for the release system. Build 1 has not been uploaded.
