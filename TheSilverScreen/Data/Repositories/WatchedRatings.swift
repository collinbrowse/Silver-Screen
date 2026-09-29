//
//  WatchedRatings.swift
//  TheSilverScreen
//
//  A movie with a personal score belongs on Watched, including scores saved
//  before that rule existed. Notes alone do not count.
//

import Foundation

enum WatchedRatings {
    /// Adds each scored movie that is not already on Watched.
    /// A title already on another list reuses that saved snapshot.
    /// Otherwise the movie is loaded so the row has a title and poster.
    static func sync(
        annotations: AnnotationsRepository,
        lists: ListsRepository,
        movies: MovieRepository,
        logger: any AppLogging
    ) async {
        let scored = await annotations.saved().filter { record in
            record.key.kind == .movie && record.score.map(UserScore.isValid) == true
        }
        guard !scored.isEmpty else { return }

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
                    continue
                }
            }

            do {
                _ = try await lists.addToWatched(draft, at: record.watchedAt ?? Date())
            } catch is CancellationError {
                return
            } catch {
                logger.error(
                    "Rated movie \(record.key.subjectID) was not added to Watched",
                    category: .persistence
                )
            }
        }
    }
}
