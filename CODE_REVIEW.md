# Launch-readiness code review

Review of `main` at `1efacdd` (2026-10-16). It covers `SilverScreen/Data`, `Support`, `Design`, `App`, `Navigation`, `worker/`, `scripts/` and `.github/workflows`, plus a report-only pass over `SilverScreen/Screens`.

Every finding below was confirmed by reading the code at the cited line; anything that could not be confirmed was dropped. Line numbers refer to `1efacdd`.

**Status values**

- **Fixed in …**: fixed in that PR or branch, with a regression test that fails without the fix.
  - Persistence: this PR, `claude/review-persistence`.
  - Networking: [#47](https://github.com/collinbrowse/Silver-Screen/pull/47), `claude/review-networking`.
  - Observability: `claude/review-observability`.
  - Image loading: `claude/review-images`.
  - Worker, scripts and CI: `claude/review-ci-worker`.

  The last three open as PRs after this one.
- **Reported**: not fixed in this pass. Screens and App navigation belong to other in-flight work. Low-severity items and repository-setting decisions are left for the owner.

## Summary

| Severity | Found | Fixed | Reported |
| --- | --- | --- | --- |
| Critical | 0 | 0 | 0 |
| High | 6 | 4 | 2 |
| Medium | 19 | 15 | 4 |
| Low | 36 | 1 | 35 |

**Highest-impact items:**

- Cancelled requests are logged as errors and sent to Sentry as error events (one per scrolled-away poster). They can also surface as "Something Went Wrong".
- Search text the user types reaches Sentry through network breadcrumbs.
- Concurrent launch bootstraps can tombstone a TestFlight tester's migrated library.
- Detail screens can stay on a spinner forever after a tab switch (Screens, reported).

---

## Persistence (`Data/Persistence`, `Data/Repositories`)

### P1 · High · Concurrent `bootstrap()` runs the legacy JSON import twice and can tombstone the imported library

**Status:** Fixed in this PR

**Where:**
- `SilverScreen/Data/Persistence/SQLiteLibraryStore.swift:57-62, 323-327, 364-413`
- `SilverScreen/App/SceneDelegate.swift:42-62`

**How it fails:**
1. Launch starts `bootstrap()`, `lists.loadIndex()`, `WatchedRatings.sync` and `TVWatchReconcile` at the same time, and each of them calls `ensureBootstrapped()`.
2. `didBootstrap` only becomes true after `importLegacyJSONIfNeeded()` returns. That function suspends three times while it reads the legacy JSON files, so actor reentrancy lets a second bootstrap start in between.
3. Bootstrap B reads `stamp == nil` and counts zero rows. Bootstrap A then imports and renames the JSON files to `*.imported`.
4. B's remaining file reads find no file and return empty. B's transaction runs `writeAnnotations([])` and `writeTVWatch([])`, which tombstone everything A just imported.

**Who is affected:** every TestFlight tester upgrading from a JSON-era build (before `a97e6c2`).

**Fix:**
- Callers share one stored bootstrap `Task`. A failed run clears the task so the next call retries.
- The legacy JSON readers are now injected through the initializer, defaulting to the file stores. This lets the test hold the second import's read until the files are renamed, so the race reproduces every time.
- The importer also no longer builds its own stores, which `architecture.mdc` asks for.

**Test:** `SQLiteLibraryStoreTests.test_bootstrap_concurrentCallers_importLegacyJSONOnce`

### P2 · Medium · Rated movies the user removed from Watched come back on every launch

**Status:** Fixed in this PR

**Where:**
- `SilverScreen/Data/Repositories/WatchedRatings.swift:16-77`
- called from `SilverScreen/App/SceneDelegate.swift:46`

**How it fails:**
1. The user rates a movie, which puts it on Watched.
2. The user removes it with the eye toggle (`ListsRepository.toggleWatched`) or a swipe. Neither touches the score.
3. On the next cold launch, `WatchedRatings.sync` finds a scored movie that is not on Watched and adds it back. It also removes the movie from Watchlist.

**Why it happens:** the pass was written as a migration for scores saved before the "rated means watched" rule, but nothing records that it already ran. It also read annotations through `saved()`, which turned an unreadable store into an empty list.

**Fix:**
- The pass now runs once per install, behind a `UserDefaults` flag.
- The flag is set only after every scored movie was resolved and saved. A failed movie load or save leaves it unset, so the next launch retries.
- `AnnotationsRepository.saved()` now throws instead of returning `[]` on a read failure.

**Tests:**
- `ListsRepositoryTests.test_sync_afterUserRemovesRatedMovieFromWatched_doesNotAddItBack`
- `ListsRepositoryTests.test_sync_whenAMovieCannotBeLoaded_retriesOnTheNextLaunch`

### P3 · Low · `LibrarySQLDate` builds `ISO8601DateFormatter`s on every call

**Status:** Reported

**Where:** `SilverScreen/Data/Persistence/LibrarySchema.swift:199-217`

**Detail:**
- `fetchSnapshot` decodes `release_date` and `added_at` per row, so a 1,000-entry library builds about 2,000 formatters on each load.
- `data-layer.mdc` says to build formatters once.
- `Date.ISO8601FormatStyle(includingFractionalSeconds: true)` held in a `static let` is a `Sendable` replacement.

### P4 · Low · `fetchSnapshot` / `fetchAnnotations` drop undecodable rows silently

**Status:** Reported

**Where:** `SilverScreen/Data/Persistence/SQLiteLibraryStore.swift:75-85, 120-127, 151-160, 194-199`

**Detail:**
- A row with an unknown `segment`, `sort` or `kind` raw value is skipped with no log and no count.
- `data-layer.mdc` asks for a logged count. The store has no logger today.

### P5 · Low · Persistence catch sites drop the root cause, and `TVWatchRepository.save` turns cancellation into `.persistence`

**Status:** Reported

**Where:**
- `TVWatchRepository.swift:539, 602-610`
- `AnnotationsRepository.swift:215, 224-226`
- `ListsRepository.swift:550`

**Detail:** these sites log a fixed string without `\(error)`, against `errors-logging.mdc`. `ListsRepository.persist` (line 564) is the one site that does it correctly.

### P6 · Low · Reconcile can re-add a series the user just removed from Watched

**Status:** Reported

**Where:** `TVWatchRepository.swift:346-364`

**Detail:**
- `reconcileCatalog` checks Watched membership, suspends to persist, and then calls `lists.addToInProgress`.
- A swipe-delete that lands in between brings the series back on In Progress with no progress.
- The window is launch-only and small.
- Fix: do the check and the move inside one `ListsRepository` write.

### P7 · Low · `clearSeries` rollback is partial when the second list write fails

**Status:** Reported

**Where:** `TVWatchRepository.swift:302-320, 458-471`

**Detail:**
- `removeFromSystemLists` removes the series from Watched and from In Progress as two separate writes. If the second write fails, the Watched removal stays.
- It also returns only the last change, so Undo restores one list.

### P8 · Low · `AnnotationsRepository.serializeWrite` forwards cancellation, so rollback writes become no-ops

**Status:** Reported

**Where:** `AnnotationsRepository.swift:171-186`

**Detail:**
- `MovieDetailViewModel` calls `restore` from a cancelled task. `onCancel` then cancels the inner write immediately, so the rollback never runs.
- `ListsRepository` and `TVWatchRepository` do not forward cancellation, so the three repositories behave differently.

### P9 · Low · `AwardsRepository.downloadIfStale` writes the weekly stamp before downloading

**Status:** Reported

**Where:** `AwardsRepository.swift:236-242`

**Detail:** a failed or offline download is not retried for seven days.

### P10 · Low · Dead waiter path in `AwardsRepository.ensureLoaded`

**Status:** Reported

**Where:** `AwardsRepository.swift:84-97`

**Detail:** `loadLocalCatalog()` is synchronous, so the `isLoadingLocal` / `localWaiters` path can never run.

### P11 · Low · TV episode cast is capped at 20, not the intended 30, and the cap log is wrong

**Status:** Reported

**Where:**
- `TVRepository.swift:605-629`
- `MovieRepository.swift:394`

**Detail:**
- `mapCast` already applies `.prefix(20)`, so `credits.count == 30` never triggers.
- The "Capped at 30" log fires only when duplicate ids were dropped.

---

## Networking and domain (`Data/Networking`, `Data/Domain`, `Data/Repositories`)

### N1 · High · A cancelled request is logged as an error, sent to Sentry, retried, and can reach the UI as `.unknown`

**Status:** Fixed in #47

**Where:**
- `SilverScreen/Data/Networking/HTTPTransport.swift:29-41, 86-95`
- `SilverScreen/Support/AppLogging.swift:28-32`

**How it fails:**
1. `URLSession.data(for:)` reports task cancellation as `URLError(.cancelled)`, not `CancellationError`, so the `CancellationError` arm never fires.
2. The error goes through `logger.error`, and `OSAppLogger.error` sends it to Sentry as an error event. That covers every poster scrolled off screen (`ImageLoader` cancels the shared fetch), every superseded search, and every popped detail screen.
3. The error maps to `.unknown`, which is auto-retried.
4. If cancellation lands on the last attempt, `AppError.unknown` is thrown and the view model shows "Something Went Wrong".

**Why tests missed it:** the test fakes throw `CancellationError`, which the real `URLSession` never does.

**Fix:**
- `URLError(.cancelled)` becomes `CancellationError` with no log and no retry.
- Each attempt checks for cancellation first.
- The retry delay no longer indexes past `retryDelays` when a caller asks for more than three attempts (latent trap, low).

**Tests:**
- `MovieRepositoryTests.test_topMovies_whenURLSessionCancelsTheRequest_throwsCancellationWithoutRetryOrErrorLog`
- `test_retryDelay_pastTheListedDelays_holdsAtTheLastOne`

### N2 · Medium · A 404 shows "Server Error… try again later" with a Retry button that can never succeed

**Status:** Fixed in #47

**Where:**
- `HTTPTransport.swift:111-113`
- `SilverScreen/Support/AppError.swift:51, 65-71`

**How it fails:**
- Every non-2xx status other than 401/403 becomes `.server(status:)`, and `.server` is always `isRetryable`.
- Example: a library row or award link to a title TMDB removed gives the user a permanent retry loop.
- `data-layer.mdc` names `isRetryable` as the single source of truth and says never to retry 4xx.

**Fix:**
- A 4xx other than 429 is no longer retryable.
- It gets its own message.

**Tests:**
- `test_topMovies_whenNotFound_throwsNonRetryableServerError`
- `test_serverError_retryableOnlyForServerFaultsAndRateLimits`

### N3 · Medium · A `null` or number in a movie page's `results` crashes the app

**Status:** Fixed in #47

**Where:** `SilverScreen/Data/Repositories/MovieRepository.swift:550-553`

**Why it crashes:**
- `JSONSerialization.data(withJSONObject:)` raises an Objective-C `NSInvalidArgumentException` for a non-collection top-level value.
- Swift `catch` cannot handle that exception.
- `TMDBPageDecoding` already guards with `isValidJSONObject`; `decodeMovies` did not.

**Fix:** the same guard.

**Test:** `test_topMovies_whenAResultIsNotAnObject_skipsItInsteadOfCrashing`

### N4 · Medium · One malformed element fails a whole movie, collection, TV or person screen

**Status:** Fixed in #47

**Where:**
- `MovieDetailDTO.swift:23-28, 70-73, 87-101, 133-172` (synthesized `Decodable` on `similar`, `credits`, `images`, `genres`, collection `parts`)
- `TVSeriesDTO.swift:223-225, 305, 378-379`
- `PersonDetailDTO.swift:16-18, 64-67`

**How it fails:**
- Example: one "similar" movie with `"title": null`, or one backdrop without `file_path`, throws `DecodingError`.
- The user then sees "Unexpected Data" instead of the movie.
- This breaks `data-layer.mdc`: "One malformed element must not discard the other nineteen".

**Fix:**
- New `KeyedDecodingContainer.decodeLossyArrayIfPresent`, which skips a bad element and keeps the rest.
- Applied to those arrays.

**Tests:**
- `test_movieDetail_keepsTheMovieWhenOneSimilarCastImageOrGenreIsMalformed`
- `test_collection_keepsGoodPartsWhenOneIsMalformed`

### N5 · Medium · Streaming providers fall back to another country when the user's region is missing

**Status:** Fixed in #47

**Where:** `SilverScreen/Data/Networking/TMDBWatchProvidersDecoding.swift:28-34`

**How it fails:**
- With region `IE` and a payload that only has `US` and `CA`, the hero shows US Netflix/Hulu, and the deep link opens a service that does not carry the title.
- With neither `US` nor the user's region, it picks the alphabetically first country.

**Fix:**
- Only the device region is used; the result is empty when that region is missing.
- A locale with no region still uses US.

**Test:** `TMDBWatchProvidersDecodingTests.test_make_whenDeviceRegionIsMissing_returnsNoProvidersFromOtherRegions`

### N6 · Medium · Shipped builds stop taking award catalog updates once the catalog gains a new prize body

**Status:** Fixed in #47

**Where:** `SilverScreen/Data/Domain/AwardsCatalog.swift:209-221, 288-299`

**How it fails:**
- `AwardsCatalog.credits` decodes strictly, and `AwardCredit.family` / `AwardWork.kind` are closed enums.
- The remote catalog is `main`'s JSON. One `"family": "goldenGlobe"` there makes every installed build fail the weekly decode.
- Those builds then keep the bundled catalog forever and log a Sentry error each week.

**Fix:** credits decode lossily, so an unknown credit is skipped.

**Test:** `AwardsRepositoryTests.test_decode_skipsACreditFromAPrizeBodyThisBuildDoesNotKnow`

### N7 · Medium · Cold-launch TV reconcile downloads full series detail for every finished show

**Status:** Fixed in #47

**Where:**
- `SilverScreen/Data/Repositories/TVWatchReconcile.swift:98`
- `TVRepository.swift:142-154`

**How it fails:**
- `reconcileOne` only needs `seasons`, but it called `series(id:)`, which appends images, aggregate credits, recommendations, videos and watch providers.
- With 150 finished shows that is 150 heavy payloads on every launch, often on cellular.

**Fix:** a new `TVRepository.seriesCatalog(id:)` with no `append_to_response`.

**Test:** `TVRepositoryTests.test_seriesCatalog_requestsNoAppendedSectionsAndKeepsSeasons`

### N8 · Low · Worst case of about 47 s of spinner on a stalled server

**Status:** Reported

**Where:**
- `URLSessionHTTPClient.swift:65`
- `HTTPTransport.swift:11-12`

**Detail:** `.timedOut` gets three attempts at 15 s each, plus backoff. Consider one retry for timeouts.

### N9 · Low · A combo provider row gives each split service the combo logo

**Status:** Reported

**Where:** `TMDBWatchProvidersDecoding.swift:53-57, 75`

### N10 · Low · `normalizeTierSuffix` strips a tier word from the middle of a name

**Status:** Reported

**Where:** `StreamingProviderCore.swift:67`

**Detail:** `range(of:options:)` has no `.anchored`.

### N11 · Low · `UserScore.isValid` traps on a huge finite score from disk

**Status:** Reported

**Where:** `MediaAnnotation.swift:53-56`

**Detail:**
- `Int(steps)` traps when `steps > Int.max`.
- A corrupt stored score of `1e300` would crash every launch.
- Fix: check the range before converting.

### N12 · Low · `TMDBConnection.resolve` compares the host case-sensitively

**Status:** Reported

**Where:** `TMDBConnection.swift:52`

### N13 · Low · Date parsing builds formatters and calendars per row and accepts impossible dates

**Status:** Reported

**Where:**
- `MovieRepository.swift:510-538`
- `AwardsCatalog.swift:500-512`

**Detail:** `"2024-02-30"` rolls over to March 1.

### N14 · Low · Dead code

**Status:** Reported

**Detail:**
- `MovieListDTO` (`MovieSummaryDTO.swift:8-20`) and `NoopSleeper` are referenced only by tests.
- `decodeMovies` duplicates `TMDBPageDecoding.decode`.

---

## Observability and support (`Support`, `App`)

### O1 · High · Search terms reach Sentry through network breadcrumbs, spans and failed-request events

**Status:** Fixed in `claude/review-observability`

**Where:**
- `SilverScreen/Support/SentryBootstrap.swift:64-76`
- search requests at `MovieRepository.swift:109`, `TVRepository.swift:118`, `PersonRepository.swift:77`

**How it leaks:**
- The SDK defaults keep network breadcrumbs, network tracking and failed-request capture on.
- sentry-cocoa 9.30.2 copies the URL query into breadcrumb data (`SentryNetworkTracker.swift:620-621`), into span data (`:219`), and into a failed request's `queryString` (`:491`).
- A search request's `query=` is what the user typed. It rides along on every later event, which breaks `observability.mdc` ("No user content (search queries…)").

**Fix:**
- `beforeBreadcrumb` and `beforeSendSpan` drop `http.query` / `http.fragment`.
- Failed-request capture is off; 5xx is already reported through `AppLogging` with the path only.

**Test:** `SentryBootstrapTests.test_configure_dropsSearchQueryFromHTTPBreadcrumbs`

### O2 · Medium · Debug and test-host runs report as production under the shipping release

**Status:** Fixed in `claude/review-observability`

**Where:** `SentryBootstrap.swift:64-76`

**How it fails:**
- `environment` is never set, so it defaults to `production`.
- `Version.xcconfig` is shared by dev, TestFlight and App Store, so a Debug run with a DSN reports sessions under release `0.1.1+8`.
- That skews the crash-free numbers that the `OBSERVABILITY.md` runbook uses to promote or halt a release.

**Fix:** set `environment` to `debug` under `#if DEBUG`.

**Test:** `test_configure_sendsNoFailedRequestEventsAndTagsDebugRuns`

### O3 · Medium · Startup failures are silent and too broad

**Status:** Reported (App composition, owned by the large-screen work)

**Where:**
- `SilverScreen/App/SceneDelegate.swift:42, 97-107`
- `SilverScreen/App/AppDependencies.swift:46, 67`

**Problems:**
- Any non-`AppError` failure shows "The app could not start." with nothing logged or sent to Sentry. That includes `SQLiteDatabaseError.openFailed`, an Application Support failure, and the awards cache directory.
- The startup failure screen has no retry.
- `AwardsRepository.cacheURL()` is only a cache path, yet if it throws the whole app is dead.
- `Task { try? await …bootstrap() }` discards migration errors.

**Fix:** log and capture in the `catch`, make the awards cache optional, and log bootstrap errors.

### O4 · Low · Review prompt fires on an edit, not just a new rating

**Status:** Reported

**Where:** `SilverScreen/Support/ReviewPrompt.swift:88-104`

**Detail:**
- Every successful save counts, and the count is by `created_at`.
- So editing any rating while the count is exactly 5 prompts. One way to get there: delete one of six ratings, then edit another.

### O5 · Low · Dead code

**Status:** Reported

**Detail:**
- `NavigationRouter.pop()`, `popToRoot()`, `pop(toDepth:)`
- `AppRouter.openLibrary()`
- `RouterStateStore.clear()`
- `StreamingProviderLaunch.queriedURLSchemes`
- `ImageLoader.prefetch` / `cancelPrefetch`: no production callers

---

## Image loading (`Support/ImageLoader.swift`, `Design`)

### I1 · Medium · A cancelled or stale image task wipes an image that already loaded

**Status:** Fixed in `claude/review-images`

**Where:**
- `SilverScreen/Design/RemoteImageView.swift:47-66`
- `MoviePosterView.swift:43-60`
- `StreamingProviderLogoRow.swift:120-138`

**How it fails:**
- `guard expected == path` compares a value-type snapshot with itself, so it never blocks.
- On an identity change, `.task(id:)` cancels the old task and the new task sets the image (often straight from cache). The old task then resumes with `nil` from `try?` and clears it, or with the previous path's image.
- The result is a visible row showing a placeholder or the wrong poster. `images.mdc` calls this out explicitly.

**Fix:**
- A new `ImageLoader.displayImage` returns nil for a failed load, and for a load whose task was cancelled.
- The three views assign only a non-nil result.
- Each load still starts by clearing the image.

**Test:** `ImageLoaderTests.test_displayImage_whenTheViewTaskWasCancelled_returnsNilEvenOnACacheHit`

### I2 · Medium · Decoded-image cache and coalescing are keyed by URL only, so the first caller's size wins

**Status:** Fixed in `claude/review-images`

**Where:** `SilverScreen/Support/ImageLoader.swift:52-73`

**How it fails:**
- On a 3x device, the episode still is shown at 120 pt in `TVSeasonView` and at 200 pt in `TVEpisodeView`, and both resolve to `w780`.
- Whichever decodes first (360 px) is reused and upscaled in the 200 pt card.
- This misses `images.mdc`'s "Cache keys include the requested size".

**Fix:** the cache and in-flight keys are URL plus pixel size.

**Test:** `ImageLoaderTests.test_image_sameURLAtTwoSizes_decodesEachSizeInsteadOfReusingTheFirst`

### I3 · Low · No `totalCostLimit` on the decoded-image `NSCache`

**Status:** Reported

**Where:** `ImageLoader.swift:37`

### I4 · Low · A failed prefetch leaves its failed task in `inFlight` for later real callers

**Status:** Reported

**Where:** `ImageLoader.swift:89-93`

**Detail:** latent; `prefetch` has no production callers.

### I5 · Low · `RemoteImageView` does not reload when `width` or `displayScale` changes

**Status:** Reported

**Where:** `RemoteImageView.swift:43`

### I6 · Low · Two poster URL builders disagree (`w500` vs `w780` cap), and `sizeToken`'s `.poster` branch is unreachable

**Status:** Reported

**Where:** `ImageLoader.swift:143-187`

---

## Worker, scripts and CI

### C1 · High · The awards-catalog workflow cannot update its branch after the first run

**Status:** Fixed in `claude/review-ci-worker` (push); PR creation reported

**Where:** `.github/workflows/awards-catalog.yml:42-55`

**How it fails:**
- `actions/checkout` fetches only `main`, so bare `--force-with-lease` expects `awards-catalog` not to exist on the remote.
- The branch is not deleted on merge, so every later weekly push is rejected (reproduced against a shallow clone).

**Fix:**
- The lease now uses the remote tip from `git ls-remote`.
- The PR step now prints a clear error.

**Owner decision:** the repository setting "Allow GitHub Actions to create and approve pull requests" is off, so `gh pr create` with `GITHUB_TOKEN` still fails. Turn it on, or use a GitHub App / PAT token.

### C2 · Medium · The Worker's fetch cache can cache TMDB 404s for four hours

**Status:** Fixed in `claude/review-ci-worker`

**Where:** `worker/src/index.js:87-91`

**How it fails:** `cf.cacheTtl` with `cacheEverything` applies to non-200 statuses too, which contradicts the README's "Errors are not cached".

**Fix:** `cacheTtlByStatus` caches 2xx only.

### C3 · Medium · Any caller can use the Worker as a general TMDB proxy on the owner's token and daily quota

**Status:** Fixed in `claude/review-ci-worker`

**Where:** `worker/src/index.js:17-23, 58-101`

**How it fails:**
- Every GET under `/3/*` is forwarded with the owner's token. The only gate is a per-IP rate limit, which IP rotation gets around.
- Encoded separators such as `%2f` were forwarded undecoded.

**Fix:**
- Allow-list the path shapes the app uses: `movie`, `tv`, `person`, `collection`, `search/{movie,tv,person}`, `discover/{movie,tv}`.
- Reject `%2f` / `%5c` / `%2e`.
- Return a 502 JSON response when TMDB is unreachable.

**Deploy:** the Worker must be redeployed (`npx wrangler@4 deploy`).

### C4 · Medium · The release job runs an unpinned `curl … | bash` with signing secrets in scope

**Status:** Fixed in `claude/review-ci-worker`

**Where:** `.github/workflows/release.yml:154`

**Fix:** download a pinned `sentry-cli` 3.8.0 binary and verify it against a SHA-256.

### C5 · Medium · One network blip kills the weekly digest

**Status:** Fixed in `claude/review-ci-worker`

**Where:**
- `scripts/asc_api.py:115-139`
- `scripts/weekly_digest.py:281`

**How it fails:**
- Only `HTTPError` is caught. A `URLError`, `TimeoutError` or reset propagates.
- `guarded()` does not catch `OSError`.

**Fix:** these are now wrapped in `ASCError` / `SourceError`, and `guarded()` catches `OSError`.

### C6 · Medium · Nothing monitors the Worker that release builds depend on

**Status:** Fixed in `claude/review-ci-worker`

**Where:** `scripts/tmdb_health.py:33`

**Detail:** the daily check calls TMDB directly, so it misses:
- an expired Worker secret
- a 429 from the rate limiter
- an exhausted quota

**Fix:** when `TMDB_PROXY_URL` is set, also GET `<proxy>/movie/550` without a token.

### C7 · Medium · The weekly digest posts business data and unescaped review text to a public repo

**Status:** Reported (owner decision)

**Where:** `scripts/weekly_digest.py:261-271, 329-334, 461-469`

**Detail:**
- The repo is public, so these appear in public issues:
  - download counts
  - crash-free rates
  - verbatim review text, where an `@user` pings that user
  - Sentry issue titles
- Options: post to a private repo or to the job summary, or at least wrap untrusted text in code spans.

### C8 · Low · A failed release run uploads the `.xcarchive` as a downloadable artifact on a public repo

**Status:** Reported

**Where:** `release.yml:167-173`

### C9 · Low · The release job doesn't confirm CI passed on the tagged commit

**Status:** Reported

**Where:** `ci.yml:10-12`, `release.yml:132-133`

**Detail:** `cancel-in-progress` on `main` can cancel the CI run for the commit being tagged.

### C10 · Low · `validate-tests.py` can false-pass

**Status:** Reported

**Where:** `scripts/validate-tests.py:85-89`

**Detail:**
- It searches the body that still contains comments, so a commented-out `XCTAssert` counts as an assertion.
- Brace matching ignores string literals.

### C11 · Low · `validate-pr-body.py` accepts the untouched template placeholder text

**Status:** Reported

**Where:** `scripts/validate-pr-body.py:93-104`

### C12 · Low · The credential scan covers only `*.swift`

**Status:** Reported

**Where:** `scripts/validate-rules.py:107-109`

### C13 · Low · `scripts/validate-streaming-providers.py` is unused and crashes with proxy-style secrets

**Status:** Reported

### C14 · Low · "Wikidata query failed" hides the cause

**Status:** Fixed in `claude/review-ci-worker`

**Where:** `scripts/build_awards_catalog.py:833`

**Detail:** both recorded failed runs show only this message.

### C15 · Low · Actions are pinned to major tags rather than SHAs

**Status:** Reported

---

## Overlap with open PRs #44, #45 and #46

None of the fixes here depend on those PRs.

- **#46 (Diary, schema v4)** edits `SQLiteLibraryStore.swift`, `SceneDelegate.swift` and `SQLiteLibraryStoreTests.swift`.
  - Whichever of #46 and this PR merges second gets a textual conflict around the store's initializer and properties.
  - P1's shared bootstrap task also covers the diary domain, because the v4 migration runs inside `bootstrap()`.
  - O3 (silent startup failures) lives in `SceneDelegate`, which #46 also changes. That is one reason it is reported here and not fixed.
- **#45 (Analytics)** edits `AnnotationsRepository.swift` and `ListsRepository.swift`, but does not call `AnnotationsRepository.saved()`. P2 makes `saved()` throw.
  - Expect a small textual conflict in `AnnotationsRepository.swift` at most.
- **#44 (large screens)** owns `Screens/` and App navigation. Findings S1–S10 and O3 sit in files it touches, so they are reported for that work rather than changed here.

## Screens (report only)

These are owned by in-flight Screens work and were not changed here.

### S1 · High · A first load cancelled by a tab switch leaves the screen on a spinner forever

**Status:** Reported

**Where:**
- `MovieDetailViewModel.swift:39-74`
- `PersonDetailViewModel.swift:65-73`
- `CollectionViewModel.swift:33-55`
- `CreditsListViewModel.swift:55-80`
- `TVSeriesViewModel.swift:108-120`
- `TVSeasonViewModel.swift:88-112`
- `TVEpisodeViewModel.swift:84-116`

**How it fails:**
1. `load()` sets `.loading` and returns on `CancellationError` without resetting the state.
2. The view runs `.task { if case .idle = viewModel.state { await viewModel.load() } }`, and the view model lives in `@State` in the route view.
3. When the user switches tabs before the load finishes, `.task` is cancelled. On return the state is `.loading`, not `.idle`, so `load()` never runs again.

**Fix:** on `CancellationError`, set the state back to `.idle` if it is still `.loading`.

### S2 · High · AwardTitles has no stale-result guard

**Status:** Reported

**Where:** `AwardTitlesViewModel.swift:106-144`

**How it fails:**
- Switching Winners/Nominees while `loadMore` is hydrating lets the late page overwrite the new selection.
- It also bumps `nextPage`, so a page is skipped.
- `reload` clears `isPaging` mid-flight, which allows a second concurrent `loadMore`.

**Fix:** a generation token, as `BrowseListViewModel` uses.

### S3 · Medium · After any `.failed` activity, infinite scroll stops for good

**Status:** Reported

**Where:**
- `SearchViewModel.swift:272`
- `BrowseListViewModel.swift:108`
- `GenreBrowseViewModel.swift:95`
- `AwardTitlesViewModel.swift:115`

**How it fails:**
- `loadMore` requires `activity == .none`.
- `.failed` is set by a failed page fetch and by `noteListSaveFailed()`, and only a refresh or a selection change clears it.

### S4 · Medium · Score-stamping helpers write back a snapshot captured before their awaits

**Status:** Reported

**Where:**
- `SearchViewModel.swift:254-261`
- `BrowseListViewModel.swift:330-343`
- `GenreBrowseViewModel.swift:289-302`
- `AwardTitlesViewModel.swift:152-157`
- `CollectionViewModel.swift:74-89`

**How it fails:**
- A page appended while the stamp is suspended is reverted.
- A captured `.loadingMore` sticks, which then trips S3.

### S5 · Low · AwardTitles never re-stamps user scores on return, and keeps stale "Next up" captions

**Status:** Reported

**Where:** `AwardTitlesViewModel.swift:152-192`

### S6 · Low · TV `reloadPersonalFromStore` blanks the score and note on a read failure

**Status:** Reported

**Where:**
- `TVSeriesViewModel.swift:317-327`
- `TVSeasonViewModel.swift:190-200`
- `TVEpisodeViewModel.swift:303-312`

### S7 · Low · A partially failed Search `loadMore` leaves the cache out of sync with the screen

**Status:** Reported

**Where:** `SearchViewModel.swift:281-323`

### S8 · Low · `Dictionary(uniqueKeysWithValues:)` traps on a duplicate episode number

**Status:** Reported

**Where:** `TVSeasonViewModel.swift:245, 297`

**Detail:** `TVRepository.mapSeason` sorts episodes but does not dedupe them.

### S9 · Low · Award views' retry buttons call a `load()` that only runs from `.idle`, and their `.failed` branches are dead

**Status:** Reported

**Where:** `AwardTitlesView.swift:62`, `AwardFamilyView.swift:67`

### S10 · Low · `TVSeriesViewModel.refresh()` failure paths restore a pre-refresh snapshot

**Status:** Reported

**Where:** `TVSeriesViewModel.swift:350-372`

---

## Checked and sound

**Persistence**
- SQLite migrations run one version per transaction, and unknown versions throw.
- v3 backfills keep the best date already stored.
- Diffed upserts revive tombstones with a fresh `created_at`.
- Annotation and membership ids have used the same deterministic formula since v1, so `ON CONFLICT(id)` never collides with the `UNIQUE` keys.

**Repositories**
- `ListsRepository` / `TVWatchRepository` writes are serialized, and the in-memory cache updates only after a successful save.
- No titles, notes or search text appear in log messages.

**Networking and credentials**
- The token goes only in the `Authorization` header and never to the proxy.
- No URL is interpolated into a log line.
- `release.py`'s proxy-token guard works.

**CI**
- No `pull_request_target`.
- No `${{ github.event.* }}` is interpolated into `run:`.

**Domain and Screens**
- Domain types are `Sendable` values, with no `@unchecked`, `nonisolated(unsafe)` or `Task.detached`.
- `ForEach` ids are unique across paging.
- Search and Browse discard stale results.

## Test-coverage gaps worth filling next

- **HTTPTransport:** `URLError(.cancelled)` and 4xx mapping are covered now. Still missing:
  - retry exhaustion on `.timedOut`
  - 429 mapping
- **ListsRepository:** no tests for:
  - `moveLists`, `moveEntries`, `setSort`
  - Undo of `.removed`
  - `addToInProgress` rejecting non-TV
- **TVWatchReconcile.refreshWatchedCatalogs:** untested, including the concurrency cap, cancellation and the toast.
- **AwardsRepository:** no tests for:
  - the stamp throttle
  - a non-2xx response
  - `remote.generatedAt <= local`
- **Screens:** no tests for:
  - cancelled cold loads (S1)
  - Winners/Nominees toggles (S2)
  - `loadMore` after a `.failed` activity (S3)
  - `AwardFamilyViewModel`
- **Worker:** no tests for:
  - a cache hit that bypasses the limiter
  - HEAD/OPTIONS
- **Validators:** `validate-tests.py` and `validate-pr-body.py` have no tests.
