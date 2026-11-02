//
//  DiaryContext.swift
//  SilverScreen
//
//  What diary screens need, installed once in the environment at the root. Passing it
//  this way keeps the diary out of every route view's initializer.
//

import Foundation

/// Narrows the diary screen to one title's watch history.
struct DiaryScope: Sendable, Equatable {
    let subject: DiarySubject
    /// The title's name, used as the screen title.
    let title: String
}

/// Diary dependencies plus a change counter. Any screen that writes an entry calls
/// `noteChange()`, and any screen that shows entries reloads when `revision` moves, so
/// a watch logged on a movie appears in an open diary (and the reverse).
/// Screens save entries through `save(_:)` so the title's rating follows its newest watch.
@Observable
@MainActor
final class DiaryContext {
    let diary: DiaryRepository
    /// Logging a watch also puts the title on Watched.
    let lists: ListsRepository
    let logger: any AppLogging
    /// The title ratings a newest watch's score is copied to. Nil in tests that skip it.
    let annotations: AnnotationsRepository?
    /// Season posters for a show's watch history. Nil in tests that skip it.
    let shows: TVRepository?
    /// Deletes a watch and anything that depended on it. Nil in tests that skip it.
    let watches: WatchRepository?
    private(set) var revision = 0
    /// Fetched season posters by series, so reopening a history skips the network.
    private var seasonPosterCache: [Int: [Int: String]] = [:]

    init(
        diary: DiaryRepository,
        lists: ListsRepository,
        logger: any AppLogging,
        annotations: AnnotationsRepository? = nil,
        shows: TVRepository? = nil,
        watches: WatchRepository? = nil
    ) {
        self.diary = diary
        self.lists = lists
        self.logger = logger
        self.annotations = annotations
        self.shows = shows
        self.watches = watches
    }

    /// Poster path by season number for one show. A failed fetch (offline, say) returns
    /// none and is retried next time, so rows fall back to the series poster.
    func seasonPosters(seriesID: Int) async -> [Int: String] {
        if let cached = seasonPosterCache[seriesID] { return cached }
        guard let shows, let posters = try? await shows.seasonPosters(seriesID: seriesID) else { return [:] }
        seasonPosterCache[seriesID] = posters
        return posters
    }

    /// Saves `entry`, then points the title's rating at its newest rated watch, the way
    /// Letterboxd's film rating follows your latest log. Older watches keep their own
    /// scores. An episode entry sets that episode's rating, never the series'.
    /// If only the rating update fails, it is logged and the saved entry stands.
    @discardableResult
    func save(_ entry: DiaryEntry) async throws -> DiaryEntry {
        let saved = try await diary.save(entry)
        guard let annotations else { return saved }
        do {
            let sameSubject = try await diary.entries(for: saved.subject).filter { $0.subject == saved.subject }
            try await annotations.syncRating(from: WatchRepository.ratedWatch(in: sameSubject), for: saved.subject)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            logger.error("Newest watch's rating was not copied to the title", category: .persistence)
        }
        return saved
    }

    /// Deletes one watch. A title's last watch takes it off Watched, and an episode's
    /// takes it out of TV progress, because a title is watched exactly when it has a watch.
    func deleteWatch(_ entry: DiaryEntry) async throws {
        if let watches {
            try await watches.deleteWatch(entry)
        } else {
            try await diary.delete(id: entry.id)
        }
    }

    func noteChange() {
        revision += 1
    }
}
