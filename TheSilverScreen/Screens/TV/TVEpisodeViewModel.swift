//
//  TVEpisodeViewModel.swift
//  TheSilverScreen
//

import Foundation

struct TVEpisodeContent: Sendable, Equatable {
    let title: String
    let episodeNumberText: String
    let overview: String
    let formattedAirDate: String
    let formattedRating: String
    let ratingAccessibilityLabel: String
    let userScore: Double?
    let formattedUserScore: String?
    let userScoreAccessibilityLabel: String
    let userNote: String?
    let formattedRatedOn: String?
    let formattedNotedOn: String?
    let stillPath: String?
    let images: [MovieImage]
    let cast: [TVCredit]
    let guestStars: [TVCredit]
    let directorsAndWriters: [TVCredit]
    /// The rest of this season, in episode order. The episode on screen is left out.
    let otherEpisodes: [TVEpisodeSummary]
    let trailers: [MediaTrailer]
    let streamingProviders: [StreamingProvider]
    var fullscreenImages: FullscreenImages?

    /// Stills for the hero. The episode still leads when the gallery does not already include it.
    var heroImages: [MovieImage] {
        guard let stillPath, !stillPath.isEmpty, !images.contains(where: { $0.filePath == stillPath }) else {
            return images
        }
        return [MovieImage(filePath: stillPath, voteAverage: 0)] + images
    }
}

/// One episode, opened from the episode list on a season.
@Observable
@MainActor
final class TVEpisodeViewModel {
    private(set) var state: LoadState<TVEpisodeContent> = .idle
    /// Prizes for this episode, newest ceremony first. The section is hidden when empty.
    private(set) var awardRows: [AwardRow] = []
    /// Series fields for list membership. Filled from the route, or from a series fetch when empty.
    private(set) var seriesSnapshot: SeriesListSnapshot
    /// Combined rating and note editor. Cleared on save, delete, or dismiss.
    private(set) var annotationEditor: AnnotationEditorSession?

    private let seriesID: Int
    private let seasonNumber: Int
    private let episodeNumber: Int
    private let shows: TVRepository
    private let annotations: AnnotationsRepository
    private let awards: AwardsRepository

    init(
        seriesID: Int,
        seasonNumber: Int,
        episodeNumber: Int,
        seriesSnapshot: SeriesListSnapshot = .empty,
        shows: TVRepository,
        annotations: AnnotationsRepository,
        awards: AwardsRepository = AwardsRepository(catalog: .empty)
    ) {
        self.seriesID = seriesID
        self.seasonNumber = seasonNumber
        self.episodeNumber = episodeNumber
        self.seriesSnapshot = seriesSnapshot
        self.shows = shows
        self.annotations = annotations
        self.awards = awards
    }

    func load() async {
        state = .loading
        do {
            async let episodeCall = shows.episode(
                seriesID: seriesID,
                seasonNumber: seasonNumber,
                episodeNumber: episodeNumber
            )
            async let othersCall = otherEpisodes()
            async let providersCall = shows.streamingProviders(seriesID: seriesID)
            async let snapshotCall = resolveSeriesSnapshot()
            let episode = try await episodeCall
            let others = try await othersCall
            let streamingProviders = await providersCall
            seriesSnapshot = await snapshotCall
            let personal = try await personalDetail()
            awardRows = await awards.episodeAwards(
                seriesID: seriesID,
                seasonNumber: seasonNumber,
                episodeNumber: episodeNumber
            )
            state = .loaded(
                Self.makeContent(
                    episode,
                    otherEpisodes: others,
                    personal: personal.detail,
                    streamingProviders: streamingProviders
                ),
                activity: personal.activity
            )
        } catch is CancellationError {
            return
        } catch let error as AppError {
            state = .failed(error)
        } catch {
            state = .failed(.unknown)
        }
    }

    /// Awards deep links arrive without series art; load it once for the membership draft.
    private func resolveSeriesSnapshot() async -> SeriesListSnapshot {
        guard seriesSnapshot.isEmpty else { return seriesSnapshot }
        do {
            let detail = try await shows.series(id: seriesID)
            return SeriesListSnapshot(detail: detail)
        } catch is CancellationError {
            return seriesSnapshot
        } catch {
            return seriesSnapshot
        }
    }

    func retry() async {
        await load()
    }

    /// Opens the combined rating and note editor from the current personal values.
    /// Does not invent a score; the sheet requires an explicit rating before Save.
    func openAnnotationEditor() {
        guard case .loaded(let content, _) = state else { return }
        annotationEditor = DetailAnnotationWriter.session(
            score: content.userScore,
            note: content.userNote
        )
    }

    /// Clears the editor after cancel or swipe-to-dismiss.
    func dismissAnnotationEditor() {
        annotationEditor = nil
    }

    /// Saves score and note together. Episode ratings do not auto-add Watched.
    @discardableResult
    func saveUserAnnotation(score: Double, note: String) async -> AnnotationEditorWriteResult {
        guard case .loaded = state else { return .failed }
        let key = AnnotationKey.episode(
            seriesID: seriesID,
            seasonNumber: seasonNumber,
            episodeNumber: episodeNumber
        )
        let (result, saved) = await DetailAnnotationWriter.save(
            score: score,
            note: note,
            for: key,
            annotations: annotations
        )
        return finishAnnotationWrite(result, annotation: saved)
    }

    /// Removes the note and leaves the score.
    @discardableResult
    func deleteUserNote() async -> AnnotationEditorWriteResult {
        guard case .loaded = state else { return .failed }
        let key = AnnotationKey.episode(
            seriesID: seriesID,
            seasonNumber: seasonNumber,
            episodeNumber: episodeNumber
        )
        let (result, saved) = await DetailAnnotationWriter.deleteNote(
            for: key,
            annotations: annotations
        )
        return finishAnnotationWrite(result, annotation: saved)
    }

    /// Removes the score and note.
    @discardableResult
    func clearUserAnnotation() async -> AnnotationEditorWriteResult {
        guard case .loaded = state else { return .failed }
        let key = AnnotationKey.episode(
            seriesID: seriesID,
            seasonNumber: seasonNumber,
            episodeNumber: episodeNumber
        )
        let result = await DetailAnnotationWriter.clear(
            for: key,
            annotations: annotations
        )
        return finishAnnotationWrite(result, annotation: nil, cleared: true)
    }

    private func finishAnnotationWrite(
        _ result: AnnotationEditorWriteResult,
        annotation: MediaAnnotation?,
        cleared: Bool = false
    ) -> AnnotationEditorWriteResult {
        switch result {
            case .succeeded:
                apply(cleared ? .empty : PersonalDetail(annotation: annotation))
                annotationEditor = nil
            case .cancelled:
                break
            case .failed:
                markPersistenceFailure()
        }
        return result
    }

    private func personalDetail() async throws -> (detail: PersonalDetail, activity: LoadActivity) {
        do {
            let record = try await annotations.annotation(
                for: .episode(seriesID: seriesID, seasonNumber: seasonNumber, episodeNumber: episodeNumber)
            )
            return (PersonalDetail(annotation: record), .none)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return (.empty, .failed(.persistence))
        }
    }

    private func apply(_ personal: PersonalDetail) {
        guard case .loaded(let content, let activity) = state else { return }
        state = .loaded(content.withPersonal(personal), activity: AnnotationActivity.afterSuccess(activity))
    }

    func noteListSaveFailed() {
        markPersistenceFailure()
    }

    private func markPersistenceFailure() {
        guard case .loaded(let content, _) = state else { return }
        state = .loaded(content, activity: .failed(.persistence))
    }

    func openImages(initialID: String) {
        guard case .loaded(var content, let activity) = state else { return }
        let images = content.heroImages
        guard !images.isEmpty else { return }
        content.fullscreenImages = FullscreenImages(
            initialID: initialID,
            images: images,
            kind: .backdrop
        )
        state = .loaded(content, activity: activity)
    }

    func dismissImages() {
        guard case .loaded(var content, let activity) = state else { return }
        content.fullscreenImages = nil
        state = .loaded(content, activity: activity)
    }

    /// Season list is extra. A failure here leaves the episode on screen with no carousel.
    private func otherEpisodes() async throws -> [TVEpisodeSummary] {
        do {
            let season = try await shows.season(seriesID: seriesID, seasonNumber: seasonNumber)
            return season.episodes.filter { $0.episodeNumber != episodeNumber }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return []
        }
    }

    private static func makeContent(
        _ episode: TVEpisodeDetail,
        otherEpisodes: [TVEpisodeSummary],
        personal: PersonalDetail,
        streamingProviders: [StreamingProvider]
    ) -> TVEpisodeContent {
        TVEpisodeContent(
            title: episode.title,
            episodeNumberText: "Episode \(episode.episodeNumber)",
            overview: episode.overview,
            formattedAirDate: DisplayDate.day(episode.airDate),
            formattedRating: TMDBRating.formatted(episode.voteAverage),
            ratingAccessibilityLabel: TMDBRating.accessibilityLabel(episode.voteAverage),
            userScore: personal.userScore,
            formattedUserScore: personal.formattedUserScore,
            userScoreAccessibilityLabel: personal.userScoreAccessibilityLabel,
            userNote: personal.userNote,
            formattedRatedOn: personal.formattedRatedOn,
            formattedNotedOn: personal.formattedNotedOn,
            stillPath: episode.stillPath,
            images: episode.images,
            cast: episode.cast,
            guestStars: episode.guestStars,
            directorsAndWriters: episode.directorsAndWriters,
            otherEpisodes: otherEpisodes,
            trailers: episode.trailers,
            streamingProviders: streamingProviders,
            fullscreenImages: nil
        )
    }
}

private extension TVEpisodeContent {
    func withPersonal(_ personal: PersonalDetail) -> TVEpisodeContent {
        TVEpisodeContent(
            title: title,
            episodeNumberText: episodeNumberText,
            overview: overview,
            formattedAirDate: formattedAirDate,
            formattedRating: formattedRating,
            ratingAccessibilityLabel: ratingAccessibilityLabel,
            userScore: personal.userScore,
            formattedUserScore: personal.formattedUserScore,
            userScoreAccessibilityLabel: personal.userScoreAccessibilityLabel,
            userNote: personal.userNote,
            formattedRatedOn: personal.formattedRatedOn,
            formattedNotedOn: personal.formattedNotedOn,
            stillPath: stillPath,
            images: images,
            cast: cast,
            guestStars: guestStars,
            directorsAndWriters: directorsAndWriters,
            otherEpisodes: otherEpisodes,
            trailers: trailers,
            streamingProviders: streamingProviders,
            fullscreenImages: fullscreenImages
        )
    }
}
