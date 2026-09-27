//
//  PersonDetailViewModelTests.swift
//  TheSilverScreenTests
//

import XCTest
@testable import TheSilverScreen

@MainActor
final class PersonDetailViewModelTests: XCTestCase {

    func test_load_whenClientSucceeds_setsLoadedContent() async {
        let viewModel = makeViewModel(stub: .success(TMDBFixtures.personDetailMorganFreeman))

        await viewModel.load()

        guard case .loaded(let content, let activity) = viewModel.state else {
            return XCTFail("Expected loaded, got \(viewModel.state)")
        }
        XCTAssertEqual(activity, .none)
        XCTAssertEqual(content.detail.name, "Morgan Freeman")
        XCTAssertEqual(content.formattedBirthday, "Jun 1, 1937")
        XCTAssertNil(content.formattedDeathday)
        XCTAssertEqual(content.placeOfBirth, "Memphis, Tennessee, USA")
        XCTAssertNotNil(content.images)
        XCTAssertEqual(content.images?.items.count, 2)
        XCTAssertEqual(content.cast?.preview.count, 2)
        XCTAssertFalse(content.cast?.showsViewAll ?? true)
        XCTAssertEqual(content.crew?.preview.count, 1)
        XCTAssertEqual(content.detail.imdbID, "nm0000151")
    }

    func test_load_whenSparse_hidesSectionsAndOptionalFacts() async {
        let viewModel = makeViewModel(stub: .success(TMDBFixtures.personDetailSparse))

        await viewModel.load()

        guard case .loaded(let content, _) = viewModel.state else {
            return XCTFail("Expected loaded")
        }
        XCTAssertNil(content.images)
        XCTAssertNil(content.cast)
        XCTAssertNil(content.crew)
        XCTAssertNil(content.formattedBirthday)
        XCTAssertNil(content.formattedDeathday)
        XCTAssertNil(content.placeOfBirth)
        XCTAssertNil(content.detail.imdbID)
    }

    func test_load_whenDeceased_formatsDeathday() async {
        let viewModel = makeViewModel(stub: .success(TMDBFixtures.personDetailManyCredits))

        await viewModel.load()

        guard case .loaded(let content, _) = viewModel.state else {
            return XCTFail("Expected loaded")
        }
        XCTAssertEqual(content.formattedDeathday, "Dec 31, 2020")
        XCTAssertEqual(content.cast?.totalCount, 12)
        XCTAssertTrue(content.cast?.showsViewAll ?? false)
        XCTAssertEqual(content.cast?.preview.count, 5)
    }

    func test_load_whenOffline_setsFailedOffline() async {
        let viewModel = makeViewModel(stub: .failure(URLError(.notConnectedToInternet)))

        await viewModel.load()

        XCTAssertEqual(viewModel.state, .failed(.offline))
    }

    func test_retry_afterFailure_loadsDetail() async {
        let switchable = SwitchableHTTPClient(stub: .failure(URLError(.notConnectedToInternet)))
        let people = PersonRepository.test(client: switchable)
        let viewModel = PersonDetailViewModel(personID: 1922, people: people)

        await viewModel.load()
        XCTAssertEqual(viewModel.state, .failed(.offline))

        await switchable.setStub(.success(TMDBFixtures.personDetailMorganFreeman))
        await viewModel.retry()

        guard case .loaded(let content, _) = viewModel.state else {
            return XCTFail("Expected loaded after retry")
        }
        XCTAssertEqual(content.detail.id, 1922)
    }

    func test_openImages_setsFullscreenSelection() async {
        let viewModel = makeViewModel(stub: .success(TMDBFixtures.personDetailMorganFreeman))
        await viewModel.load()

        viewModel.openImages(initialID: "/profile2.jpg")

        guard case .loaded(let content, _) = viewModel.state else {
            return XCTFail("Expected loaded")
        }
        XCTAssertEqual(content.fullscreenImages?.initialID, "/profile2.jpg")
        XCTAssertEqual(content.fullscreenImages?.kind, .profile)
        XCTAssertEqual(content.fullscreenImages?.images.count, 2)
    }

    func test_openProfile_setsFullscreenProfile() async {
        let viewModel = makeViewModel(stub: .success(TMDBFixtures.personDetailMorganFreeman))
        await viewModel.load()

        viewModel.openProfile()

        guard case .loaded(let content, _) = viewModel.state else {
            return XCTFail("Expected loaded")
        }
        XCTAssertEqual(content.fullscreenImages?.kind, .profile)
        XCTAssertEqual(content.fullscreenImages?.images.count, 1)
    }

    func test_genreNames_usesTVCatalogForTVCredits() {
        let credit = PersonCredit(
            mediaType: .tv,
            mediaID: 1,
            title: "Show",
            posterPath: nil,
            releaseDate: nil,
            genreIDs: [18, 10765],
            roleLabel: "",
            popularity: 1,
            voteAverage: 0
        )
        XCTAssertEqual(
            PersonDetailViewModel.genreNames(for: credit),
            ["Drama", "Sci-Fi & Fantasy"]
        )
    }

    // MARK: - Helpers

    private func makeViewModel(stub: FakeHTTPClient.Stub) -> PersonDetailViewModel {
        let people = PersonRepository.test(client: FakeHTTPClient(stub: stub))
        return PersonDetailViewModel(personID: 1922, people: people)
    }
}

/// Mutable stub used to simulate retry after a failure.
private actor SwitchableHTTPClient: HTTPClient {
    private var stub: FakeHTTPClient.Stub

    init(stub: FakeHTTPClient.Stub) {
        self.stub = stub
    }

    func setStub(_ stub: FakeHTTPClient.Stub) {
        self.stub = stub
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        try await FakeHTTPClient(stub: stub).data(for: request)
    }
}
