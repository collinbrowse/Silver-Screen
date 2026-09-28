//
//  TVEpisodeViewModelTests.swift
//  TheSilverScreenTests
//

import XCTest
@testable import TheSilverScreen

@MainActor
final class TVEpisodeViewModelTests: XCTestCase {

    func test_load_mapsHeaderCastGuestsAndCrew() async {
        let viewModel = TVEpisodeViewModel(
            seriesID: 1396,
            seasonNumber: 1,
            episodeNumber: 1,
            shows: TVRepository.test(client: FakeHTTPClient(stub: .success(TMDBFixtures.tvEpisodePilot))),
            annotations: AnnotationsRepository.empty()
        )

        await viewModel.load()

        guard case .loaded(let content, _) = viewModel.state else {
            return XCTFail("Expected loaded, got \(viewModel.state)")
        }
        XCTAssertEqual(content.title, "Pilot")
        XCTAssertEqual(content.episodeNumberText, "Episode 1")
        XCTAssertEqual(content.formattedAirDate, "Jan 20, 2008")
        XCTAssertEqual(content.formattedRating, "8.2 / 10")
        XCTAssertEqual(content.ratingAccessibilityLabel, "Rated 8.2 out of 10")
        XCTAssertEqual(content.overview, "The first cook.")
        XCTAssertEqual(content.stillPath, "/pilot.jpg")
        XCTAssertEqual(content.cast.map(\.role), ["Walter White"])
        XCTAssertEqual(content.guestStars.map(\.name), ["John Koyama"])
        XCTAssertEqual(content.directorsAndWriters.map(\.name), ["Vince Gilligan", "Story Person", "Screen Person"])
        XCTAssertFalse(content.directorsAndWriters.contains { $0.name == "Script Coordinator" })
        XCTAssertFalse(content.images.isEmpty)
        XCTAssertEqual(content.heroImages.map(\.filePath), ["/pilot.jpg", "/still.jpg"])
        XCTAssertTrue(content.otherEpisodes.isEmpty)
    }

    func test_load_listsTheOtherEpisodesInTheSeason() async {
        let season = Data("""
        {
          "id": 1, "name": "Season 1", "season_number": 1,
          "episodes": [
            {"id": 10, "name": "Pilot", "episode_number": 1, "still_path": "/pilot.jpg"},
            {"id": 11, "name": "Cat's in the Bag...", "episode_number": 2, "still_path": "/e2.jpg"},
            {"id": 12, "name": "...And the Bag's in the River", "episode_number": 3}
          ]
        }
        """.utf8)
        let client = RoutingHTTPClient(routes: [
            "season/1/episode": .success(TMDBFixtures.tvEpisodePilot),
            "season/1": .success(season),
        ])
        let viewModel = TVEpisodeViewModel(
            seriesID: 1396,
            seasonNumber: 1,
            episodeNumber: 1,
            shows: TVRepository.test(client: client),
            annotations: AnnotationsRepository.empty()
        )

        await viewModel.load()

        guard case .loaded(let content, _) = viewModel.state else {
            return XCTFail("Expected loaded, got \(viewModel.state)")
        }
        XCTAssertEqual(content.otherEpisodes.map(\.title), ["Cat's in the Bag...", "...And the Bag's in the River"])
        XCTAssertEqual(content.otherEpisodes.map(\.episodeNumber), [2, 3])
    }

    func test_load_withSavedScoreAndNote_showsThem() async throws {
        let annotations = AnnotationsRepository(store: InMemoryAnnotationsStore(), logger: SilentLogger())
        _ = try await annotations.saveScore(10, for: .episode(seriesID: 1396, seasonNumber: 1, episodeNumber: 1))
        _ = try await annotations.saveNote("The pilot", for: .episode(seriesID: 1396, seasonNumber: 1, episodeNumber: 1))
        let viewModel = TVEpisodeViewModel(
            seriesID: 1396,
            seasonNumber: 1,
            episodeNumber: 1,
            shows: TVRepository.test(client: FakeHTTPClient(stub: .success(TMDBFixtures.tvEpisodePilot))),
            annotations: annotations
        )

        await viewModel.load()

        guard case .loaded(let content, activity: .none) = viewModel.state else {
            return XCTFail("Expected loaded, got \(viewModel.state)")
        }
        XCTAssertEqual(content.formattedUserScore, "10.0 / 10")
        XCTAssertEqual(content.userNote, "The pilot")
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
        {"id": 10, "name": "Pilot", "episode_number": 1, "overview": ""}
        """.utf8)
        let viewModel = TVEpisodeViewModel(
            seriesID: 1396,
            seasonNumber: 1,
            episodeNumber: 1,
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

    func test_saveUserNote_whenPersistenceFails_keepsPreviousNote() async throws {
        let store = InMemoryAnnotationsStore()
        let annotations = AnnotationsRepository(store: store, logger: SilentLogger())
        _ = try await annotations.saveNote("Keep", for: .episode(seriesID: 1396, seasonNumber: 1, episodeNumber: 1))
        let viewModel = TVEpisodeViewModel(
            seriesID: 1396,
            seasonNumber: 1,
            episodeNumber: 1,
            shows: TVRepository.test(client: FakeHTTPClient(stub: .success(TMDBFixtures.tvEpisodePilot))),
            annotations: annotations
        )
        await viewModel.load()
        await store.setSaveError(CocoaError(.fileWriteUnknown))

        let saved = await viewModel.saveUserNote("Nope")

        XCTAssertFalse(saved)
        guard case .loaded(let content, activity: .failed(.persistence)) = viewModel.state else {
            return XCTFail("Expected loaded with persistence failure, got \(viewModel.state)")
        }
        XCTAssertEqual(content.userNote, "Keep")
    }

    func test_openImages_includesTheStillWhenTheGalleryOmitsIt() async {
        let viewModel = TVEpisodeViewModel(
            seriesID: 1396,
            seasonNumber: 1,
            episodeNumber: 1,
            shows: TVRepository.test(client: FakeHTTPClient(stub: .success(TMDBFixtures.tvEpisodePilot))),
            annotations: AnnotationsRepository.empty()
        )
        await viewModel.load()

        viewModel.openImages(initialID: "/pilot.jpg")

        guard case .loaded(let content, _) = viewModel.state else {
            return XCTFail("Expected loaded, got \(viewModel.state)")
        }
        XCTAssertEqual(content.fullscreenImages?.images.map(\.filePath), ["/pilot.jpg", "/still.jpg"])
        XCTAssertEqual(content.fullscreenImages?.initialID, "/pilot.jpg")
    }

    func test_heroImages_keepsTheGalleryWhenItAlreadyContainsTheStill() async {
        let payload = Data("""
        {
          "id": 10, "name": "Pilot", "episode_number": 1,
          "still_path": "/pilot.jpg",
          "images": {"stills": [{"file_path": "/pilot.jpg", "vote_average": 2.0}]}
        }
        """.utf8)
        let viewModel = TVEpisodeViewModel(
            seriesID: 1396,
            seasonNumber: 1,
            episodeNumber: 1,
            shows: TVRepository.test(client: FakeHTTPClient(stub: .success(payload))),
            annotations: AnnotationsRepository.empty()
        )
        await viewModel.load()

        guard case .loaded(let content, _) = viewModel.state else {
            return XCTFail("Expected loaded, got \(viewModel.state)")
        }
        XCTAssertEqual(content.heroImages.map(\.filePath), ["/pilot.jpg"])
    }
}
