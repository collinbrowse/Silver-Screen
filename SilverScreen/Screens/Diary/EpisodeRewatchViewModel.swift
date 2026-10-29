//
//  EpisodeRewatchViewModel.swift
//  SilverScreen
//

import Foundation

/// Log a Rewatch on an episode page. The episode's first viewing is its check-off in TV
/// progress; each rewatch is a diary entry about that one episode, with its own date,
/// rating, and review. Saving never touches TV progress or lists.
@Observable
@MainActor
final class EpisodeRewatchViewModel {
    /// The sheet for a new rewatch, or nil.
    var editor: DiaryEditorSession?

    let title: LogWatchTitle
    private let context: DiaryContext
    private let now: @Sendable () -> Date

    init(title: LogWatchTitle, context: DiaryContext, now: @escaping @Sendable () -> Date = { Date() }) {
        self.title = title
        self.context = context
        self.now = now
    }

    /// Opens the sheet for a new, unrated rewatch dated today.
    func begin() {
        editor = .logging(title, currentScore: nil, now: now())
    }

    func dismissEditor() {
        editor = nil
    }

    /// Saves the rewatch. Its rating becomes the episode's rating when it is that episode's
    /// newest watch (`DiaryContext.save`); the series' rating is never touched.
    func save(_ draft: DiaryEntryDraft) async -> AnnotationEditorWriteResult {
        guard let session = editor else { return .cancelled }
        do {
            try await context.save(session.entry(from: draft, now: now()))
        } catch is CancellationError {
            return .cancelled
        } catch {
            return .failed
        }
        editor = nil
        context.noteChange()
        return .succeeded
    }
}

extension LogWatchTitle {
    /// One episode of a series, logged under the series' name and poster so the diary row
    /// reads like the show's other rows. `listItem` is the series; an episode rewatch
    /// never adds it to a list.
    init(episode: TVEpisodeRef, seriesID: Int, seriesName: String, posterPath: String?) {
        self.init(
            subject: .episode(seriesID: seriesID, season: episode.seasonNumber, episode: episode.episodeNumber),
            title: seriesName,
            releaseYear: nil,
            posterPath: posterPath,
            listItem: ListItemDraft(
                id: seriesID,
                kind: .tv,
                title: seriesName,
                imagePath: posterPath,
                releaseDate: nil,
                genreNames: [],
                voteAverage: 0,
                popularity: 0
            )
        )
    }
}
