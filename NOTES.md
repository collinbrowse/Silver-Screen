# Notes

Decisions that are easier to say in prose than to reconstruct from the code. What the app does, and how to run it, is in the [README](README.md).

## Layout

The screens follow a familiar media app: a tab bar, poster rows, and a full-bleed detail page. A personal movie library does not need a new way to move around. The work went into the lists staying in sync, the detail page holding together, and awards showing up on the title they belong to.

## State and dependencies

Strict layering, one direction only:

`View (SwiftUI)` → `ViewModel` → `Repository` → `Service (TMDB / persistence)`

- One `@Observable @MainActor` view model per screen. View models import `Foundation` only.
- One `LoadState`, with `LoadActivity` nested inside `.loaded`. Refresh, paging, and a failed refresh keep the current content on screen. Only a cold failure is full-screen. `empty` is its own case.
- Repositories are concrete. They own mapping, caching, and persistence, and they return domain models or throw `AppError`.
- Dependencies are built once in `AppDependencies` and passed down. No singletons.
- `AppRouter` owns the selected tab and one `NavigationRouter` per tab. Views push routes. They do not construct the destination.
- Protocols exist only where a test has to substitute a boundary: `HTTPClient`, the library store, and `AppLogging`.

## Awards and the API key

TMDB has no awards endpoint. The catalog is a Wikidata snapshot joined to TMDB by IMDb id, compiled by [`scripts/build_awards_catalog.py`](scripts/build_awards_catalog.py) and refreshed from `main` at most weekly. The phone never queries Wikidata. See [`AWARDS.md`](AWARDS.md).

The key lives in a gitignored `Secrets.xcconfig`, is copied into `Info.plist`, and is read at launch. Requests still send it as TMDB’s v3 `api_key` query item. A v4 bearer token would keep the key out of the URL. Logs already omit request URLs. I have not minted a v4 token yet.

## Still open

- Switch TMDB auth to a v4 bearer token.
- Snapshot tests for the components in `Design/`.
- A reachability check, so the interface can respond when the network drops instead of only after a request fails.

## How it was built

The harness is in the repo: rules under `.cursor/rules/`, the contract in [`AGENTS.md`](AGENTS.md), hooks that block a new third-party dependency, and CI checks for empty tests and pull-request bodies. Tests substitute the network and the disk store, then run the real repositories and view models.
