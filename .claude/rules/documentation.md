# Documentation comments

Prefer code that reads clearly on its own. When it does not, document **what the symbol is and why it exists** so another human (or agent) can navigate the app without reverse-engineering.

## Always comment when not self-explanatory

Add a short `///` (or `//` for file-level context) on:

- Types: `struct`, `class`, `actor`, `enum`, `protocol`
- Functions and methods (including initializers with non-obvious contracts)
- Nested types used as public surface for a screen or layer

Skip noise on names that already state the whole story (`retry()`, `SortOption.alphabetical`). Prefer one or two sentences on *purpose / contract*, not a restatement of the signature.

```swift
// ❌ BAD — restates the name
/// Loads more movies.
func loadMore() async { ... }

// ✅ GOOD — explains the non-obvious contract
/// Fetches the next page while keeping the current list on screen.
/// Concurrent calls are ignored; failures stay on `.loaded` with a failed activity.
func loadMore() async { ... }
```

```swift
// ❌ BAD — unexplained domain enum cases that need product meaning
enum LoadActivity { case none, refreshing, loadingMore, failed(AppError) }

// ✅ GOOD
/// In-flight or soft-failure work while content remains visible.
enum LoadActivity {
    case none
    case refreshing
    case loadingMore
    /// Refresh/page failed; keep showing the last good content.
    case failed(AppError)
}
```

## Variables

Do **not** comment every local or property. Add a brief note only when the name cannot carry the meaning — units, invariants, caches, or “why this exists”:

```swift
/// Deduped favorite movie IDs for cell star state; refreshed on appear.
private var favoriteIDs: Set<Movie.ID> = []
```

## Scope

Apply to new and touched app code under `SilverScreen/` (and tests when a helper’s role is unclear). Do not mass-comment unrelated files in the same change. File headers that already describe purpose count for the type that owns the file.
