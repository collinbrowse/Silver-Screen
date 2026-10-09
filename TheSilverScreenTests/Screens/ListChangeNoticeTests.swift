//
//  ListChangeNoticeTests.swift
//  TheSilverScreenTests
//

import XCTest
@testable import TheSilverScreen

@MainActor
final class ListChangeNoticeTests: XCTestCase {
    func test_annotationKey_mapsMovieAndTVItemKeys() {
        XCTAssertEqual(
            ListChangeNotice.annotationKey(forItemKey: "movie-15"),
            .movie(15)
        )
        XCTAssertEqual(
            ListChangeNotice.annotationKey(forItemKey: "tv-42"),
            .series(42)
        )
        XCTAssertNil(ListChangeNotice.annotationKey(forItemKey: "person-9"))
        XCTAssertNil(ListChangeNotice.annotationKey(forItemKey: "bogus"))
    }

    func test_show_watchedAddWithoutScore_offersAddRating() async throws {
        let lists = ListsRepository(store: InMemoryListsStore(), logger: SilentLogger())
        let annotations = AnnotationsRepository(store: InMemoryAnnotationsStore(), logger: SilentLogger())
        let notice = ListChangeNotice(annotations: annotations)
        let draft = ListItemDraft(
            id: 15,
            kind: .movie,
            title: "Heat",
            imagePath: nil,
            releaseDate: nil,
            genreNames: [],
            voteAverage: 0,
            popularity: 0
        )
        let change = try await lists.addToWatched(draft)

        notice.show(change, using: lists)
        await waitForRatingKey(notice)

        XCTAssertEqual(notice.message, "Added to Watched")
        XCTAssertEqual(notice.ratingKey, .movie(15))
    }

    func test_show_watchedAddWithScore_doesNotOfferAddRating() async throws {
        let lists = ListsRepository(store: InMemoryListsStore(), logger: SilentLogger())
        let annotations = AnnotationsRepository(store: InMemoryAnnotationsStore(), logger: SilentLogger())
        _ = try await annotations.saveScore(8.5, for: .movie(15))
        let notice = ListChangeNotice(annotations: annotations)
        let draft = ListItemDraft(
            id: 15,
            kind: .movie,
            title: "Heat",
            imagePath: nil,
            releaseDate: nil,
            genreNames: [],
            voteAverage: 0,
            popularity: 0
        )
        let change = try await lists.addToWatched(draft)

        notice.show(change, using: lists)
        try await Task.sleep(for: .milliseconds(200))

        XCTAssertEqual(notice.message, "Added to Watched")
        XCTAssertNil(notice.ratingKey)
    }

    func test_saveRating_persistsScoreAndClearsOffer() async throws {
        let lists = ListsRepository(store: InMemoryListsStore(), logger: SilentLogger())
        let annotations = AnnotationsRepository(store: InMemoryAnnotationsStore(), logger: SilentLogger())
        let notice = ListChangeNotice(annotations: annotations)
        let draft = ListItemDraft(
            id: 7,
            kind: .tv,
            title: "Severance",
            imagePath: nil,
            releaseDate: nil,
            genreNames: [],
            voteAverage: 0,
            popularity: 0
        )
        let snapshot = try await lists.snapshot()
        let inProgress = try XCTUnwrap(snapshot.list(.inProgress))
        let change = try await lists.add(draft: draft, listID: inProgress.id)

        notice.show(change, using: lists)
        await waitForRatingKey(notice)
        XCTAssertEqual(notice.ratingKey, .series(7))

        await notice.saveRating(9.0)

        XCTAssertNil(notice.ratingKey)
        let saved = try await annotations.annotation(for: .series(7))
        XCTAssertEqual(saved?.score, 9.0)
    }

    func test_show_preferredEpisodeRatingKey_savesOnEpisodeNotSeries() async throws {
        let lists = ListsRepository(store: InMemoryListsStore(), logger: SilentLogger())
        let annotations = AnnotationsRepository(store: InMemoryAnnotationsStore(), logger: SilentLogger())
        let notice = ListChangeNotice(annotations: annotations)
        let draft = ListItemDraft(
            id: 42,
            kind: .tv,
            title: "Severance",
            imagePath: nil,
            releaseDate: nil,
            genreNames: [],
            voteAverage: 0,
            popularity: 0
        )
        let change = try await lists.addToInProgress(draft)
        let episodeKey = AnnotationKey.episode(seriesID: 42, seasonNumber: 1, episodeNumber: 3)

        notice.show(change, using: lists, ratingKey: episodeKey)
        await waitForRatingKey(notice)
        XCTAssertEqual(notice.ratingKey, episodeKey)

        await notice.saveRating(8.0)

        let episode = try await annotations.annotation(for: episodeKey)
        XCTAssertEqual(episode?.score, 8.0)
        let series = try await annotations.annotation(for: .series(42))
        XCTAssertNil(series?.score)
    }

    func test_presentWatch_withoutMembership_offersEpisodeRating() async throws {
        let lists = ListsRepository(store: InMemoryListsStore(), logger: SilentLogger())
        let annotations = AnnotationsRepository(store: InMemoryAnnotationsStore(), logger: SilentLogger())
        let notice = ListChangeNotice(annotations: annotations)
        let episodeKey = AnnotationKey.episode(seriesID: 42, seasonNumber: 1, episodeNumber: 2)

        notice.presentWatch(
            change: nil,
            ratingKey: episodeKey,
            fallbackMessage: "Episode watched",
            using: lists
        )
        await waitForRatingKey(notice)

        XCTAssertEqual(notice.message, "Episode watched")
        XCTAssertEqual(notice.ratingKey, episodeKey)
        XCTAssertFalse(notice.canUndo)
    }

    func test_presentWatch_afterPriorToast_replacesBanner() async throws {
        let lists = ListsRepository(store: InMemoryListsStore(), logger: SilentLogger())
        let annotations = AnnotationsRepository(store: InMemoryAnnotationsStore(), logger: SilentLogger())
        let notice = ListChangeNotice(annotations: annotations)
        let draft = ListItemDraft(
            id: 42,
            kind: .tv,
            title: "Severance",
            imagePath: nil,
            releaseDate: nil,
            genreNames: [],
            voteAverage: 0,
            popularity: 0
        )
        let first = try await lists.addToInProgress(draft)
        let episode1 = AnnotationKey.episode(seriesID: 42, seasonNumber: 1, episodeNumber: 1)
        let episode2 = AnnotationKey.episode(seriesID: 42, seasonNumber: 1, episodeNumber: 2)

        notice.presentWatch(
            change: first,
            ratingKey: episode1,
            fallbackMessage: "Episode watched",
            using: lists
        )
        await waitForRatingKey(notice)
        let firstPresentation = notice.presentationID
        XCTAssertEqual(notice.message, "Added to In Progress")

        notice.presentWatch(
            change: nil,
            ratingKey: episode2,
            fallbackMessage: "Episode watched",
            using: lists
        )
        await waitForRatingKey(notice)

        XCTAssertEqual(notice.message, "Episode watched")
        XCTAssertEqual(notice.ratingKey, episode2)
        XCTAssertGreaterThan(notice.presentationID, firstPresentation)
    }

    func test_undo_watchedTVMove_restoresLedgerAndInProgress() async throws {
        let lists = ListsRepository(store: InMemoryListsStore(), logger: SilentLogger())
        let tvWatch = TVWatchRepository(
            store: InMemoryTVWatchStore(),
            lists: lists,
            logger: SilentLogger()
        )
        let notice = ListChangeNotice()
        let draft = ListItemDraft(
            id: 12,
            kind: .tv,
            title: "Two Step",
            imagePath: nil,
            releaseDate: nil,
            genreNames: [],
            voteAverage: 0,
            popularity: 0
        )
        let seasons = [
            TVSeasonSummary(
                id: 1,
                name: "Season 1",
                seasonNumber: 1,
                episodeCount: 2,
                airDate: nil,
                posterPath: nil
            ),
        ]
        _ = try await tvWatch.markEpisode(
            seriesID: 12,
            seasonNumber: 1,
            episodeNumber: 1,
            title: "A",
            draft: draft,
            seasons: seasons
        )
        let complete = try await tvWatch.markEpisode(
            seriesID: 12,
            seasonNumber: 1,
            episodeNumber: 2,
            title: "B",
            draft: draft,
            seasons: seasons
        )
        let change = try XCTUnwrap(complete.membershipChange)
        let priorRevision = notice.watchRevision

        notice.show(
            change,
            using: lists,
            tvWatch: tvWatch,
            watchUndo: complete.watchUndo
        )
        XCTAssertTrue(notice.canUndo)

        await notice.undo()

        XCTAssertNil(notice.message)
        XCTAssertGreaterThan(notice.watchRevision, priorRevision)
        let restored = try await tvWatch.state(seriesID: 12)
        let state = try XCTUnwrap(restored)
        XCTAssertFalse(state.isSeriesComplete(against: seasons))
        XCTAssertNil(state.catalogSnapshot)
        let after = try await lists.snapshot()
        let inProgress = try XCTUnwrap(after.list(.inProgress))
        XCTAssertTrue(after.entries.contains { $0.listID == inProgress.id && $0.itemID == 12 })
    }

    private func waitForRatingKey(_ notice: ListChangeNotice) async {
        for _ in 0..<80 {
            if notice.ratingKey != nil { return }
            await Task.yield()
        }
    }
}
