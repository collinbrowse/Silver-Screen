//
//  TVSeriesViewModelTests.swift
//  TheSilverScreenTests
//

import XCTest
@testable import TheSilverScreen

@MainActor
final class TVSeriesViewModelTests: XCTestCase {

    func test_load_formatsHeaderAndSortsSeasons() async {
        let client = RoutingHTTPClient(routes: [
            "/tv/1396/reviews": .success(TMDBFixtures.movieReviewsPage1),
            "/tv/1396": .success(TMDBFixtures.tvSeriesBreakingBad),
            ])
        let viewModel = TVSeriesViewModel(seriesID: 1396, shows: TVRepository.test(client: client),
            annotations: AnnotationsRepository.empty(),
            lists: ListsRepository.empty()
        )

        await viewModel.load()

        guard case .loaded(let content, _) = viewModel.state else {
            return XCTFail("Expected loaded, got \(viewModel.state)")
        }
        XCTAssertEqual(content.detail.name, "Breaking Bad")
        XCTAssertEqual(content.heroMetadataLine, "2 Seasons · Drama · 2008 - 2013")
        XCTAssertEqual(content.heroMetadataAccessibilityLabel, "2 Seasons, Drama, 2008 to 2013")
        XCTAssertEqual(content.formattedRating, "8.9 / 10")
        XCTAssertEqual(content.ratingAccessibilityLabel, "Rated 8.9 out of 10")
        XCTAssertEqual(content.seasons.map(\.seasonNumber), [1, 2])
        XCTAssertEqual(content.seasons.map(\.name), ["The Beginning", "Season 2"])
        XCTAssertEqual(content.seasons[0].episodeCountText, "7 episodes")
        XCTAssertEqual(content.recommendations.map(\.name), ["Better Call Saul"])
        XCTAssertEqual(content.reviews?.items.count, 1)
    }

    func test_loadMoreReviews_appendsNextPage() async {
        let client = SequencingHTTPClient(stubs: [
            .success(TMDBFixtures.tvSeriesBreakingBad),
            .success(TMDBFixtures.movieReviewsPage1),
            .success(TMDBFixtures.movieReviewsPage2),
            ])
        let viewModel = TVSeriesViewModel(seriesID: 1396, shows: TVRepository.test(client: client),
            annotations: AnnotationsRepository.empty(),
            lists: ListsRepository.empty()
        )
        await viewModel.load()

        await viewModel.loadMoreReviews()

        guard case .loaded(let content, _) = viewModel.state else {
            return XCTFail("Expected loaded, got \(viewModel.state)")
        }
        XCTAssertEqual(content.reviews?.items.map(\.id), ["rev-1", "rev-2"])
        XCTAssertEqual(content.reviews?.hasMore, false)
    }

    func test_loadMoreReviews_keepsTheListWhenTheNextPageFails() async {
        let client = SequencingHTTPClient(stubs: [
            .success(TMDBFixtures.tvSeriesBreakingBad),
            .success(TMDBFixtures.movieReviewsPage1),
            .failure(URLError(.notConnectedToInternet)),
            ])
        let viewModel = TVSeriesViewModel(seriesID: 1396, shows: TVRepository.test(client: client),
            annotations: AnnotationsRepository.empty(),
            lists: ListsRepository.empty()
        )
        await viewModel.load()

        await viewModel.loadMoreReviews()

        guard case .loaded(let content, _) = viewModel.state else {
            return XCTFail("Expected loaded, got \(viewModel.state)")
        }
        XCTAssertEqual(content.reviews?.items.map(\.id), ["rev-1"])
        XCTAssertEqual(content.reviews?.pageError, .offline)
    }

    func test_refresh_keepsTheSeriesWhenTheRequestFails() async {
        let client = SequencingHTTPClient(stubs: [
            .success(TMDBFixtures.tvSeriesBreakingBad),
            .success(TMDBFixtures.movieReviewsPage1),
            .failure(URLError(.notConnectedToInternet)),
            ])
        let viewModel = TVSeriesViewModel(seriesID: 1396, shows: TVRepository.test(client: client),
            annotations: AnnotationsRepository.empty(),
            lists: ListsRepository.empty()
        )
        await viewModel.load()

        await viewModel.refresh()

        guard case .loaded(let content, let activity) = viewModel.state else {
            return XCTFail("Expected loaded, got \(viewModel.state)")
        }
        XCTAssertEqual(content.detail.name, "Breaking Bad")
        XCTAssertEqual(activity, .failed(.offline))
    }

    func test_load_whenSparseSeries_omitsHeroMetadataParts() async {
        let payload = Data("""
            {"id": 1, "name": "Untitled", "overview": "", "created_by": []}
            """.utf8)
        let client = SequencingHTTPClient(stubs: [
            .success(payload),
            .failure(URLError(.notConnectedToInternet)),
            ])
        let viewModel = TVSeriesViewModel(seriesID: 1, shows: TVRepository.test(client: client),
            annotations: AnnotationsRepository.empty(),
            lists: ListsRepository.empty()
        )

        await viewModel.load()

        guard case .loaded(let content, _) = viewModel.state else {
            return XCTFail("Expected loaded, got \(viewModel.state)")
        }
        XCTAssertEqual(content.heroMetadataLine, "")
        XCTAssertEqual(content.formattedRating, "Unavailable")
        XCTAssertEqual(content.ratingAccessibilityLabel, "TMDB rating unavailable")
    }

            func test_openPoster_setsFullscreenPoster() async {
            let client = RoutingHTTPClient(routes: [
                "/tv/1396/reviews": .success(TMDBFixtures.movieReviewsPage1),
                "/tv/1396": .success(TMDBFixtures.tvSeriesBreakingBad),
                ])
            let viewModel = TVSeriesViewModel(seriesID: 1396, shows: TVRepository.test(client: client),
                annotations: AnnotationsRepository.empty(),
                lists: ListsRepository.empty()
                )
            await viewModel.load()

            viewModel.openPoster()

            guard case .loaded(let content, _) = viewModel.state else {
            return XCTFail("Expected loaded, got \(viewModel.state)")
            }
            XCTAssertEqual(content.fullscreenImages?.kind, .poster)
            XCTAssertEqual(content.fullscreenImages?.images.map(\.filePath), ["/bb.jpg"])
            XCTAssertEqual(content.fullscreenImages?.images.count, 1)
            }

            func test_load_marksCompletedSeasonAndScoreForCarouselBadge() async throws {
                let lists = ListsRepository(store: InMemoryListsStore(), logger: SilentLogger())
                let tvWatch = TVWatchRepository(
                    store: InMemoryTVWatchStore(),
                    lists: lists,
                    logger: SilentLogger()
                )
                let annotations = AnnotationsRepository(store: InMemoryAnnotationsStore(), logger: SilentLogger())
                let draft = ListItemDraft(
                    id: 1396,
                    kind: .tv,
                    title: "Breaking Bad",
                    imagePath: nil,
                    releaseDate: nil,
                    genreNames: [],
                    voteAverage: 0,
                    popularity: 0
                )
                let seasons = [
                    TVSeasonSummary(
                        id: 1,
                        name: "The Beginning",
                        seasonNumber: 1,
                        episodeCount: 7,
                        airDate: nil,
                        posterPath: nil
                    ),
                    TVSeasonSummary(
                        id: 2,
                        name: "Season 2",
                        seasonNumber: 2,
                        episodeCount: 13,
                        airDate: nil,
                        posterPath: nil
                    ),
                ]
                _ = try await tvWatch.markSeason(
                    seriesID: 1396,
                    seasonNumber: 1,
                    episodeCount: 7,
                    draft: draft,
                    seasons: seasons
                )
                _ = try await annotations.saveScore(8.5, for: .season(seriesID: 1396, seasonNumber: 1))
                let client = RoutingHTTPClient(routes: [
                    "/tv/1396/reviews": .success(TMDBFixtures.movieReviewsEmpty),
                    "/tv/1396": .success(TMDBFixtures.tvSeriesBreakingBad),
                ])
                let viewModel = TVSeriesViewModel(
                    seriesID: 1396,
                    shows: TVRepository.test(client: client),
                    annotations: annotations,
                    lists: lists,
                    tvWatch: tvWatch
                )

                await viewModel.load()

                XCTAssertTrue(viewModel.watchedSeasonNumbers.contains(1))
                XCTAssertFalse(viewModel.watchedSeasonNumbers.contains(2))
                XCTAssertEqual(viewModel.seasonScores[1], "8.5 / 10")
            }

            func test_reloadNextUp_refreshesSeasonBadgesAfterWatchChange() async throws {
                let lists = ListsRepository(store: InMemoryListsStore(), logger: SilentLogger())
                let tvWatch = TVWatchRepository(
                    store: InMemoryTVWatchStore(),
                    lists: lists,
                    logger: SilentLogger()
                )
                let client = RoutingHTTPClient(routes: [
                    "/tv/1396/reviews": .success(TMDBFixtures.movieReviewsEmpty),
                    "/tv/1396": .success(TMDBFixtures.tvSeriesBreakingBad),
                ])
                let viewModel = TVSeriesViewModel(
                    seriesID: 1396,
                    shows: TVRepository.test(client: client),
                    annotations: AnnotationsRepository.empty(),
                    lists: lists,
                    tvWatch: tvWatch
                )
                await viewModel.load()
                XCTAssertTrue(viewModel.watchedSeasonNumbers.isEmpty)

                let draft = ListItemDraft(
                    id: 1396,
                    kind: .tv,
                    title: "Breaking Bad",
                    imagePath: nil,
                    releaseDate: nil,
                    genreNames: [],
                    voteAverage: 0,
                    popularity: 0
                )
                let seasons = [
                    TVSeasonSummary(
                        id: 1,
                        name: "The Beginning",
                        seasonNumber: 1,
                        episodeCount: 7,
                        airDate: nil,
                        posterPath: nil
                    ),
                    TVSeasonSummary(
                        id: 2,
                        name: "Season 2",
                        seasonNumber: 2,
                        episodeCount: 13,
                        airDate: nil,
                        posterPath: nil
                    ),
                ]
                _ = try await tvWatch.markSeason(
                    seriesID: 1396,
                    seasonNumber: 1,
                    episodeCount: 7,
                    draft: draft,
                    seasons: seasons
                )

                await viewModel.reloadNextUp()

                XCTAssertTrue(viewModel.watchedSeasonNumbers.contains(1))
                XCTAssertFalse(viewModel.watchedSeasonNumbers.contains(2))
            }

            func test_load_withSavedScoreAndNote_showsThem() async throws {
            let annotations = AnnotationsRepository(store: InMemoryAnnotationsStore(), logger: SilentLogger())
            _ = try await annotations.saveScore(9, for: .series(1396))
            _ = try await annotations.saveNote("Peak television", for: .series(1396))
            let client = RoutingHTTPClient(routes: [
                "/tv/1396/reviews": .success(TMDBFixtures.movieReviewsEmpty),
                "/tv/1396": .success(TMDBFixtures.tvSeriesBreakingBad),
                ])
            let viewModel = TVSeriesViewModel(
                seriesID: 1396,
                shows: TVRepository.test(client: client),
                annotations: annotations,
                lists: ListsRepository.empty()
                )

            await viewModel.load()

            guard case .loaded(let content, activity: .none) = viewModel.state else {
            return XCTFail("Expected loaded, got \(viewModel.state)")
            }
            XCTAssertEqual(content.formattedUserScore, "9.0 / 10")
            XCTAssertEqual(content.userNote, "Peak television")
            XCTAssertTrue(PersonalDetail(
                formattedUserScore: content.formattedUserScore,
                userScoreAccessibilityLabel: content.userScoreAccessibilityLabel,
                userNote: content.userNote,
                formattedRatedOn: content.formattedRatedOn,
                formattedNotedOn: content.formattedNotedOn
                ).showsNotesFirst)
            }

            func test_load_withoutNote_andEmptyOverview_staysOnDescription() async {
            let payload = Data("""
                {"id": 1, "name": "Untitled", "overview": "", "created_by": []}
                """.utf8)
                let viewModel = TVSeriesViewModel(
                    seriesID: 1,
                    shows: TVRepository.test(client: SequencingHTTPClient(stubs: [.success(payload)])),
                    annotations: AnnotationsRepository.empty(),
                    lists: ListsRepository.empty()
                    )

                await viewModel.load()

                guard case .loaded(let content, _) = viewModel.state else {
                return XCTFail("Expected loaded, got \(viewModel.state)")
                }
                XCTAssertNil(content.userNote)
                XCTAssertEqual(content.detail.overview, "")
                XCTAssertFalse(PersonalDetail(
                    formattedUserScore: nil,
                    userScoreAccessibilityLabel: content.userScoreAccessibilityLabel,
                    userNote: nil,
                    formattedRatedOn: nil,
                    formattedNotedOn: nil
                    ).showsNotesFirst)
                }

                func test_saveUserNote_whenPersistenceFails_keepsPreviousNote() async throws {
                let store = InMemoryAnnotationsStore()
                let annotations = AnnotationsRepository(store: store, logger: SilentLogger())
                _ = try await annotations.saveNote("Keep this", for: .series(1396))
                let client = RoutingHTTPClient(routes: [
                    "/tv/1396/reviews": .success(TMDBFixtures.movieReviewsEmpty),
                    "/tv/1396": .success(TMDBFixtures.tvSeriesBreakingBad),
                    ])
                let viewModel = TVSeriesViewModel(
                    seriesID: 1396,
                    shows: TVRepository.test(client: client),
                    annotations: annotations,
                    lists: ListsRepository.empty()
                    )
                await viewModel.load()
                await store.setSaveError(CocoaError(.fileWriteUnknown))

                let saved = await viewModel.saveUserNote("Replacement")

                XCTAssertFalse(saved)
                guard case .loaded(let content, activity: .failed(.persistence)) = viewModel.state else {
                return XCTFail("Expected loaded with persistence failure, got \(viewModel.state)")
                }
                XCTAssertEqual(content.userNote, "Keep this")
                }
                }
