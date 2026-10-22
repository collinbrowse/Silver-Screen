//
//  WatchedRatings.swift
//  SilverScreen
//
//  A movie with a personal score belongs on Watched. Saving a score adds it there,
//  so this one-time pass only moves scores saved before that rule existed. Notes
//  alone do not count.
//

import Foundation

enum WatchedRatings {
    /// Set once every scored movie has been moved to Watched. After that, removing a
    /// rated movie from Watched is the user's choice and launch must not undo it.
    static let completedKey = "watchedRatingsSyncCompleted"

    /// Adds each scored movie that is not already on Watched, once per install.
    /// A title already on another list reuses that saved snapshot.
    /// Otherwise the movie is loaded so the row has a title and poster.
    /// Disk write is one batched `addToWatched` after drafts are collected.
    /// A read, load, or save failure leaves the pass unfinished so the next launch retries.
    /// Main-actor isolated because it owns the `UserDefaults` flag; the work is awaited
    /// repository calls, so nothing heavy runs on the main thread.
    @MainActor
    static func sync(
        annotations: AnnotationsRepository,
        lists: ListsRepository,
        movies: MovieRepository,
        logger: any AppLogging,
        defaults: UserDefaults = .standard
    ) async {
        guard !defaults.bool(forKey: completedKey) else { return }

        let scored: [MediaAnnotation]
        do {
            scored = try await annotations.saved().filter { record in
                record.key.kind == .movie && record.score.map(UserScore.isValid) == true
            }
        } catch is CancellationError {
            return
        } catch {
            logger.error("Watched ratings sync could not read annotations", category: .persistence)
            return
        }
        guard !scored.isEmpty else {
            defaults.set(true, forKey: completedKey)
            return
        }

        let snapshot: LibrarySnapshot
        do {
            snapshot = try await lists.snapshot()
        } catch is CancellationError {
            return
        } catch {
            logger.error("Watched ratings sync could not read lists", category: .persistence)
            return
        }
        guard let watchedID = snapshot.list(.watched)?.id else { return }
        let watchedKeys = Set(
            snapshot.entries.filter { $0.listID == watchedID }.map(\.itemKey)
        )

        var pending: [(draft: ListItemDraft, date: Date)] = []
        var unresolved = 0
        for record in scored {
            if Task.isCancelled { return }
            let itemKey = ListEntry.itemKey(id: record.key.subjectID, kind: .movie)
            if watchedKeys.contains(itemKey) { continue }

            let draft: ListItemDraft
            if let stored = snapshot.entries.first(where: {
                $0.kind == .movie && $0.itemID == record.key.subjectID
            }) {
                draft = stored.listItem()
            } else {
                do {
                    let detail = try await movies.movieDetail(id: record.key.subjectID)
                    draft = detail.listItem()
                } catch is CancellationError {
                    return
                } catch {
                    logger.error(
                        "Rated movie \(record.key.subjectID) was not added to Watched",
                        category: .persistence
                    )
                    unresolved += 1
                    continue
                }
            }
            pending.append((draft, record.watchedAt ?? Date()))
        }

        if !pending.isEmpty {
            do {
                try await lists.addToWatched(pending)
            } catch is CancellationError {
                return
            } catch {
                logger.error("Watched ratings sync could not save lists", category: .persistence)
                return
            }
        }
        if unresolved == 0 {
            defaults.set(true, forKey: completedKey)
        }
    }
}
