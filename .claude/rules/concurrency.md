---
paths:
  - "SilverScreen/**/*.swift"
---

# Concurrency

Code must compile clean under Swift 6 language mode with no concurrency warnings.

- `async`/`await` only. No completion handlers, no `Result` callbacks, no `DispatchQueue.main.async`.
- UI-facing types are `@MainActor`: view models, `AppRouter`, `NavigationRouter`.
- Repositories and services are actors or `Sendable` value types, and never touch UI types.
- Domain models are immutable `Sendable` structs.
- Use structured concurrency for parallel work (`async let`, `withThrowingTaskGroup`) and `.task` for view-lifetime work, so cancellation is automatic.
- Propagate cancellation. Do not translate `CancellationError` into a user-facing error.
- Never reach for `@unchecked Sendable`, `nonisolated(unsafe)`, or `Task.detached` to silence a warning. Fix the ownership instead.

```swift
// ❌ BAD
func getTopMovies(completion: @escaping (Result<[MovieSummary], Error>) -> Void)

// ✅ GOOD
func topMovies() async throws -> [Movie]
```
