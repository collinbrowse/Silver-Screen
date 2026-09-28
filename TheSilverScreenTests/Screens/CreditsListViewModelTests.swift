//
//  CreditsListViewModelTests.swift
//  TheSilverScreenTests
//

import XCTest
@testable import TheSilverScreen

@MainActor
final class CreditsListViewModelTests: XCTestCase {

    func test_load_cast_filtersCastCreditsAndMapsGenres() async {
        let viewModel = CreditsListViewModel(
            personID: 1922,
            personName: "Morgan Freeman",
            department: .cast,
            people: PersonRepository.test(
                client: FakeHTTPClient(stub: .success(TMDBFixtures.personDetailMorganFreeman))
            )
        )

        await viewModel.load()

        guard case .loaded(let content, _) = viewModel.state else {
            return XCTFail("Expected loaded, got \(viewModel.state)")
        }
        XCTAssertEqual(content.department, .cast)
        XCTAssertEqual(content.items.count, 2)
        XCTAssertEqual(content.items[0].credit.mediaType, .movie)
        XCTAssertEqual(content.items[0].genreNames, ["Drama", "Crime"])
        XCTAssertEqual(content.items[1].credit.mediaType, .tv)
        XCTAssertEqual(content.items[1].genreNames, ["Drama", "Crime"])
        XCTAssertEqual(viewModel.navigationTitle, "Acting Roles")
    }

    func test_load_crew_returnsMergedCrewCredits() async {
        let viewModel = CreditsListViewModel(
            personID: 1922,
            personName: "Morgan Freeman",
            department: .crew,
            people: PersonRepository.test(
                client: FakeHTTPClient(stub: .success(TMDBFixtures.personDetailMorganFreeman))
            )
        )

        await viewModel.load()

        guard case .loaded(let content, _) = viewModel.state else {
            return XCTFail("Expected loaded")
        }
        XCTAssertEqual(content.items.count, 1)
        XCTAssertEqual(content.items[0].credit.title, "Fight Club")
        XCTAssertEqual(viewModel.navigationTitle, "Crew Roles")
    }

    func test_load_whenNoCredits_setsEmpty() async {
        let viewModel = CreditsListViewModel(
            personID: 1,
            personName: "Unknown",
            department: .crew,
            people: PersonRepository.test(
                client: FakeHTTPClient(stub: .success(TMDBFixtures.personDetailSparse))
            )
        )

        await viewModel.load()

        XCTAssertEqual(viewModel.state, .empty)
    }

    func test_load_whenOffline_setsFailed() async {
        let viewModel = CreditsListViewModel(
            personID: 1,
            personName: "Unknown",
            department: .cast,
            people: PersonRepository.test(
                client: FakeHTTPClient(stub: .failure(URLError(.notConnectedToInternet)))
            )
        )

        await viewModel.load()

        XCTAssertEqual(viewModel.state, .failed(.offline))
    }
}
