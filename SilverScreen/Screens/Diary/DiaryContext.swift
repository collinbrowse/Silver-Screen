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
    private(set) var revision = 0
    /// Fetched season posters by series, so reopening a history skips the network.
    private var seasonPosterCache: [Int: [Int: String]] = [:]

    init(
        diary: DiaryRepository,
        lists: ListsRepository,
        logger: any AppLogging,
        annotations: AnnotationsRepository? = nil,
        shows: TVRepository? = nil
    ) {
        self.diary = diary
        self.lists = lists
        self.logger = logger
        self.annotations = annotations
        self.shows = shows
    }

    /// Poster path by season number for one show. A failed fetch (offline, say) returns
    /// none and is retried next time, so rows fall back to the series poster.
    func seasonPosters(seriesID: Int) async -> [Int: String] {
        if let cached = seasonPosterCache[seriesID] { return cached }
        guard let shows, let posters = try? await shows.seasonPosters(seriesID: seriesID) else { return [:] }
        seasonPosterCache[seriesID] = posters
        return posters
    }

    /// Saves `entry`. When it has a score and is now the title's newest watch, that score
    /// also becomes the title's rating, the way Letterboxd's film rating follows your
    /// latest log. Older watches keep their own scores and never change the title's.
    /// An episode entry sets that episode's rating, never the series'; "newest" compares
    /// only entries for the exact same subject.
    /// An unrated watch leaves the title's rating alone. If only the rating copy fails,
    /// it is logged and the saved entry stands.
    @discardableResult
    func save(_ entry: DiaryEntry) async throws -> DiaryEntry {
        let saved = try await diary.save(entry)
        guard let score = saved.score, let annotations else { return saved }
        do {
            let sameSubject = try await diary.entries(for: saved.subject).filter { $0.subject == saved.subject }
            guard sameSubject.first?.id == saved.id else { return saved }
            _ = try await annotations.saveScore(score, for: Self.annotationKey(for: saved.subject))
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            logger.error("Newest watch's rating was not copied to the title", category: .persistence)
        }
        return saved
    }

    func noteChange() {
        revision += 1
    }

    private static func annotationKey(for subject: DiarySubject) -> AnnotationKey {
        if let episode = subject.episode {
            return .episode(seriesID: subject.tmdbID, seasonNumber: episode.seasonNumber, episodeNumber: episode.episodeNumber)
        }
        return subject.kind == .tv ? .series(subject.tmdbID) : .movie(subject.tmdbID)
    }
}
