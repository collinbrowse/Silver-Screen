//
//  TVSeasonViewModel.swift
//  TheSilverScreen
//

import Foundation

struct TVSeasonContent: Sendable, Equatable {
    let seriesName: String
    let displayName: String
    let overview: String
    let formattedAirDate: String
    let formattedRating: String
    let ratingAccessibilityLabel: String
    let formattedUserScore: String?
    let userScoreAccessibilityLabel: String
    let userNote: String?
    let formattedRatedOn: String?
    let formattedNotedOn: String?
    let posterPath: String?
    let images: [MovieImage]
    let cast: [TVCredit]
    let directorsAndWriters: [TVCredit]
    let episodes: [TVEpisodeSummary]
    let trailers: [MediaTrailer]
    var fullscreenImages: FullscreenImages?
}

/// One season, opened from the seasons carousel on a series.
@Observable
@MainActor
final class TVSeasonViewModel {
    private(set) var state: LoadState<TVSeasonContent> = .idle
    /// Prizes for this season, newest ceremony first. The section is hidden when empty.
    private(set) var awardRows: [AwardRow] = []

    private let seriesID: Int
    private let seriesName: String
    private let seasonNumber: Int
    private let shows: TVRepository
    private let annotations: AnnotationsRepository
    private let awards: AwardsRepository

    init(
        seriesID: Int,
        seriesName: String,
        seasonNumber: Int,
        shows: TVRepository,
        annotations: AnnotationsRepository,
        awards: AwardsRepository = AwardsRepository(catalog: .empty)
    ) {
        self.seriesID = seriesID
        self.seriesName = seriesName
        self.seasonNumber = seasonNumber
        self.shows = shows
        self.annotations = annotations
        self.awards = awards
    }

    func load() async {
        state = .loading
        do {
            let season = try await shows.season(seriesID: seriesID, seasonNumber: seasonNumber)
            let personal = try await personalDetail()
            awardRows = await awards.seasonAwards(seriesID: seriesID, seasonNumber: seasonNumber)
            state = .loaded(
                Self.makeContent(season: season, seriesName: seriesName, personal: personal.detail),
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

    func retry() async {
        await load()
    }

    /// Saves a half-point score. A failure keeps the score already on screen.
    func saveUserScore(_ score: Double) async {
        guard case .loaded = state else { return }
        do {
            let saved = try await annotations.saveScore(
                score,
                for: .season(seriesID: seriesID, seasonNumber: seasonNumber)
            )
            apply(PersonalDetail(annotation: saved))
        } catch is CancellationError {
            return
        } catch {
            markPersistenceFailure()
        }
    }

    /// Saves a note. Returns false when the write fails so the editor can stay open.
    func saveUserNote(_ note: String) async -> Bool {
        guard case .loaded = state else { return false }
        do {
            let saved = try await annotations.saveNote(
                note,
                for: .season(seriesID: seriesID, seasonNumber: seasonNumber)
            )
            apply(PersonalDetail(annotation: saved))
            return true
        } catch is CancellationError {
            return false
        } catch {
            markPersistenceFailure()
            return false
        }
    }

    /// Removes the note and leaves the score. Returns false when the write fails.
    func deleteUserNote() async -> Bool {
        guard case .loaded = state else { return false }
        do {
            let saved = try await annotations.deleteNote(
                for: .season(seriesID: seriesID, seasonNumber: seasonNumber)
            )
            apply(PersonalDetail(annotation: saved))
            return true
        } catch is CancellationError {
            return false
        } catch {
            markPersistenceFailure()
            return false
        }
    }

    private func personalDetail() async throws -> (detail: PersonalDetail, activity: LoadActivity) {
        do {
            let record = try await annotations.annotation(
                for: .season(seriesID: seriesID, seasonNumber: seasonNumber)
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
        guard case .loaded(var content, let activity) = state, !content.images.isEmpty else { return }
        content.fullscreenImages = FullscreenImages(
            initialID: initialID,
            images: content.images,
            kind: .backdrop
        )
        state = .loaded(content, activity: activity)
    }

    func dismissImages() {
        guard case .loaded(var content, let activity) = state else { return }
        content.fullscreenImages = nil
        state = .loaded(content, activity: activity)
    }

    /// Opens the season poster. A missing path leaves the screen as it is.
    func openPoster() {
        guard case .loaded(var content, let activity) = state,
              let path = content.posterPath,
              !path.isEmpty else { return }
        content.fullscreenImages = FullscreenImages(
            initialID: path,
            images: [MovieImage(filePath: path, voteAverage: 0)],
            kind: .poster
        )
        state = .loaded(content, activity: activity)
    }

    private static func makeContent(
        season: TVSeasonDetail,
        seriesName: String,
        personal: PersonalDetail
    ) -> TVSeasonContent {
        TVSeasonContent(
            seriesName: seriesName,
            displayName: SeasonTitle.display(name: season.name, number: season.seasonNumber),
            overview: season.overview,
            formattedAirDate: DisplayDate.day(season.airDate),
            formattedRating: TMDBRating.formatted(season.voteAverage),
            ratingAccessibilityLabel: TMDBRating.accessibilityLabel(season.voteAverage),
            formattedUserScore: personal.formattedUserScore,
            userScoreAccessibilityLabel: personal.userScoreAccessibilityLabel,
            userNote: personal.userNote,
            formattedRatedOn: personal.formattedRatedOn,
            formattedNotedOn: personal.formattedNotedOn,
            posterPath: season.posterPath,
            images: season.images,
            cast: season.cast,
            directorsAndWriters: season.directorsAndWriters,
            episodes: season.episodes,
            trailers: season.trailers,
            fullscreenImages: nil
        )
    }
}

private extension TVSeasonContent {
    func withPersonal(_ personal: PersonalDetail) -> TVSeasonContent {
        TVSeasonContent(
            seriesName: seriesName,
            displayName: displayName,
            overview: overview,
            formattedAirDate: formattedAirDate,
            formattedRating: formattedRating,
            ratingAccessibilityLabel: ratingAccessibilityLabel,
            formattedUserScore: personal.formattedUserScore,
            userScoreAccessibilityLabel: personal.userScoreAccessibilityLabel,
            userNote: personal.userNote,
            formattedRatedOn: personal.formattedRatedOn,
            formattedNotedOn: personal.formattedNotedOn,
            posterPath: posterPath,
            images: images,
            cast: cast,
            directorsAndWriters: directorsAndWriters,
            episodes: episodes,
            trailers: trailers,
            fullscreenImages: fullscreenImages
        )
    }
}
