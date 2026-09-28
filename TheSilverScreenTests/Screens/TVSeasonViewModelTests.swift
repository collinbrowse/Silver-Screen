//
//  TVSeasonViewModelTests.swift
//  TheSilverScreenTests
//

import XCTest
@testable import TheSilverScreen

@MainActor
final class TVSeasonViewModelTests: XCTestCase {

    func test_load_showsTheSeasonName() async {
        let viewModel = TVSeasonViewModel(
            seriesID: 1396,
            seriesName: "Breaking Bad",
            seasonNumber: 1,
            shows: TVRepository.test(client: FakeHTTPClient(stub: .success(TMDBFixtures.tvSeasonPilot))),
            annotations: AnnotationsRepository.empty()
        )

        await viewModel.load()

        guard case .loaded(let content, _) = viewModel.state else {
            return XCTFail("Expected loaded, got \(viewModel.state)")
        }
        XCTAssertEqual(content.seriesName, "Breaking Bad")
        XCTAssertEqual(content.displayName, "The Beginning")
        XCTAssertEqual(content.formattedAirDate, "Jan 20, 2008")
        XCTAssertEqual(content.formattedRating, "8.4 / 10")
        XCTAssertEqual(content.ratingAccessibilityLabel, "Rated 8.4 out of 10")
        XCTAssertEqual(content.overview, "Walter starts cooking.")
        XCTAssertEqual(content.episodes[0].directorLine, "Director: Vince Gilligan")
        XCTAssertEqual(content.cast[0].name, "Bryan Cranston")
    }

    func test_seasonTitle_usesTheNameWithoutANumberPrefix() {
        XCTAssertEqual(SeasonTitle.display(name: "Season 2", number: 2), "Season 2")
        XCTAssertEqual(SeasonTitle.display(name: "Specials", number: 0), "Specials")
        XCTAssertEqual(SeasonTitle.display(name: "The Beginning", number: 1), "The Beginning")
        XCTAssertEqual(SeasonTitle.display(name: "", number: 0), "Specials")
        XCTAssertEqual(SeasonTitle.display(name: "  ", number: 3), "Season 3")
    }

    func test_openPoster_setsFullscreenPoster() async {
        let viewModel = TVSeasonViewModel(
            seriesID: 1396,
            seriesName: "Breaking Bad",
            seasonNumber: 1,
            shows: TVRepository.test(client: FakeHTTPClient(stub: .success(TMDBFixtures.tvSeasonPilot))),
            annotations: AnnotationsRepository.empty()
        )
        await viewModel.load()

        viewModel.openPoster()

        guard case .loaded(let content, _) = viewModel.state else {
            return XCTFail("Expected loaded, got \(viewModel.state)")
        }
        XCTAssertEqual(content.fullscreenImages?.kind, .poster)
        XCTAssertEqual(content.fullscreenImages?.images.map(\.filePath), ["/s1.jpg"])
        XCTAssertEqual(content.fullscreenImages?.images.count, 1)
    }

    func test_load_withSavedScoreAndNote_showsThem() async throws {
        let annotations = AnnotationsRepository(store: InMemoryAnnotationsStore(), logger: SilentLogger())
        _ = try await annotations.saveScore(8.5, for: .season(seriesID: 1396, seasonNumber: 1))
        _ = try await annotations.saveNote("Slow start", for: .season(seriesID: 1396, seasonNumber: 1))
        let viewModel = TVSeasonViewModel(
            seriesID: 1396,
            seriesName: "Breaking Bad",
            seasonNumber: 1,
            shows: TVRepository.test(client: FakeHTTPClient(stub: .success(TMDBFixtures.tvSeasonPilot))),
            annotations: annotations
        )

        await viewModel.load()

        guard case .loaded(let content, activity: .none) = viewModel.state else {
            return XCTFail("Expected loaded, got \(viewModel.state)")
        }
        XCTAssertEqual(content.formattedUserScore, "8.5 / 10")
        XCTAssertEqual(content.userNote, "Slow start")
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
        {"id": 1, "name": "Season 1", "season_number": 1, "overview": "", "episodes": []}
        """.utf8)
        let viewModel = TVSeasonViewModel(
            seriesID: 1396,
            seriesName: "Breaking Bad",
            seasonNumber: 1,
            shows: TVRepository.test(client: FakeHTTPClient(stub: .success(payload))),
            annotations: AnnotationsRepository.empty()
        )

        await viewModel.load()

        guard case .loaded(let content, _) = viewModel.state else {
            return XCTFail("Expected loaded, got \(viewModel.state)")
        }
        XCTAssertNil(content.userNote)
        XCTAssertEqual(content.overview, "")
        XCTAssertFalse(PersonalDetail(
            formattedUserScore: nil,
            userScoreAccessibilityLabel: content.userScoreAccessibilityLabel,
            userNote: nil,
            formattedRatedOn: nil,
            formattedNotedOn: nil
        ).showsNotesFirst)
    }

    func test_saveUserScore_whenPersistenceFails_keepsPreviousScore() async throws {
        let store = InMemoryAnnotationsStore()
        let annotations = AnnotationsRepository(store: store, logger: SilentLogger())
        _ = try await annotations.saveScore(8.5, for: .season(seriesID: 1396, seasonNumber: 1))
        let viewModel = TVSeasonViewModel(
            seriesID: 1396,
            seriesName: "Breaking Bad",
            seasonNumber: 1,
            shows: TVRepository.test(client: FakeHTTPClient(stub: .success(TMDBFixtures.tvSeasonPilot))),
            annotations: annotations
        )
        await viewModel.load()
        await store.setSaveError(CocoaError(.fileWriteUnknown))

        await viewModel.saveUserScore(10)

        guard case .loaded(let content, activity: .failed(.persistence)) = viewModel.state else {
            return XCTFail("Expected loaded with persistence failure, got \(viewModel.state)")
        }
        XCTAssertEqual(content.formattedUserScore, "8.5 / 10")
    }
}
