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
        XCTAssertEqual(content.creditSections.map(\.title), ["Acting", "Crew"])
        XCTAssertEqual(content.creditSections[0].preview.count, 2)
        XCTAssertFalse(content.creditSections[0].showsViewAll)
        XCTAssertEqual(content.creditSections[1].preview.count, 1)
        XCTAssertEqual(content.detail.imdbID, "nm0000151")
    }

    func test_load_whenSparse_hidesSectionsAndOptionalFacts() async {
        let viewModel = makeViewModel(stub: .success(TMDBFixtures.personDetailSparse))

        await viewModel.load()

        guard case .loaded(let content, _) = viewModel.state else {
            return XCTFail("Expected loaded")
        }
        XCTAssertNil(content.images)
        XCTAssertTrue(content.creditSections.isEmpty)
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
        XCTAssertEqual(content.creditSections.map(\.title), ["Acting"])
        XCTAssertEqual(content.creditSections[0].totalCount, 12)
        XCTAssertTrue(content.creditSections[0].showsViewAll)
        XCTAssertEqual(content.creditSections[0].preview.count, 5)
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

    func test_load_whenKnownForDirecting_ordersDirectingThenActingThenCrew() async {
        let viewModel = makeViewModel(stub: .success(TMDBFixtures.personDetailDirector))

        await viewModel.load()

        guard case .loaded(let content, _) = viewModel.state else {
            return XCTFail("Expected loaded, got \(viewModel.state)")
        }
        XCTAssertEqual(content.creditSections.map(\.title), ["Directing", "Acting", "Crew"])
        XCTAssertEqual(content.creditSections[0].preview.map(\.title), ["Inception", "Interstellar"])
        XCTAssertEqual(content.creditSections[0].preview.map(\.roleLabel), ["Director", "Director"])
        XCTAssertEqual(content.creditSections[2].preview.map(\.roleLabel), ["Screenplay", "Producer"])
    }

    func test_makeContent_whenKnownForDirecting_leadsWithDirectedFilms() {
        let content = PersonDetailViewModel.makeContent(detail: person(
            knownFor: "Directing",
            cast: [credit(id: 3, title: "Cameo", popularity: 10, role: "Man")],
            crew: [
                credit(id: 1, title: "Inception", popularity: 100, jobs: [
                    PersonCreditJob(department: "Directing", job: "Director"),
                    PersonCreditJob(department: "Writing", job: "Screenplay"),
                ]),
                credit(id: 2, title: "Interstellar", popularity: 80, jobs: [
                    PersonCreditJob(department: "Directing", job: "Director"),
                ]),
                credit(id: 4, title: "Produced", popularity: 50, jobs: [
                    PersonCreditJob(department: "Production", job: "Producer"),
                ]),
            ]
        ))

        XCTAssertEqual(content.creditSections.map(\.title), ["Directing", "Acting", "Crew"])
        XCTAssertEqual(content.creditSections[0].preview.map(\.title), ["Inception", "Interstellar"])
        XCTAssertEqual(content.creditSections[0].preview.map(\.roleLabel), ["Director", "Director"])
        XCTAssertEqual(content.creditSections[1].preview.map(\.title), ["Cameo"])
        XCTAssertEqual(content.creditSections[2].preview.map(\.title), ["Inception", "Produced"])
        XCTAssertEqual(content.creditSections[2].preview.map(\.roleLabel), ["Screenplay", "Producer"])
    }

    func test_makeContent_whenKnownForWriting_leadsWithWritingCredits() {
        let content = PersonDetailViewModel.makeContent(detail: person(
            knownFor: "Writing",
            cast: [],
            crew: [
                credit(id: 1, title: "Inception", popularity: 90, jobs: [
                    PersonCreditJob(department: "Directing", job: "Director"),
                    PersonCreditJob(department: "Writing", job: "Screenplay"),
                ]),
                credit(id: 2, title: "Memento", popularity: 40, jobs: [
                    PersonCreditJob(department: "Writing", job: "Story"),
                    PersonCreditJob(department: "Writing", job: "Script Coordinator"),
                ]),
            ]
        ))

        XCTAssertEqual(content.creditSections.map(\.title), ["Writing", "Crew"])
        XCTAssertEqual(content.creditSections[0].preview.map(\.title), ["Inception", "Memento"])
        XCTAssertEqual(content.creditSections[0].preview.map(\.roleLabel), ["Screenplay", "Story"])
        XCTAssertEqual(content.creditSections[1].preview.map(\.roleLabel), ["Director", "Script Coordinator"])
    }

    func test_makeContent_whenKnownForProduction_leadsWithThatDepartment() {
        let content = PersonDetailViewModel.makeContent(detail: person(
            knownFor: "Production",
            cast: [credit(id: 2, title: "Cameo", popularity: 5, role: "Guest")],
            crew: [
                credit(id: 1, title: "Dune", popularity: 70, jobs: [
                    PersonCreditJob(department: "Production", job: "Producer"),
                    PersonCreditJob(department: "Directing", job: "Director"),
                ]),
            ]
        ))

        XCTAssertEqual(content.creditSections.map(\.title), ["Production", "Acting", "Crew"])
        XCTAssertEqual(content.creditSections[0].department, .named("Production"))
        XCTAssertEqual(content.creditSections[0].preview.map(\.roleLabel), ["Producer"])
        XCTAssertEqual(content.creditSections[2].preview.map(\.roleLabel), ["Director"])
    }

    func test_makeContent_whenDirectorHasNoDirectorJobs_fallsBackToActingThenCrew() {
        let content = PersonDetailViewModel.makeContent(detail: person(
            knownFor: "Directing",
            cast: [credit(id: 2, title: "Cameo", popularity: 5, role: "Man")],
            crew: [
                credit(id: 1, title: "Second Unit", popularity: 20, jobs: [
                    PersonCreditJob(department: "Directing", job: "Assistant Director"),
                ]),
            ]
        ))

        XCTAssertEqual(content.creditSections.map(\.title), ["Acting", "Crew"])
        XCTAssertEqual(content.creditSections[1].preview.map(\.roleLabel), ["Assistant Director"])
    }

    func test_makeContent_viewAllThresholdIsPerSection() {
        let directed = (1...12).map { index in
            credit(id: index, title: "Film \(index)", popularity: Double(100 - index), jobs: [
                PersonCreditJob(department: "Directing", job: "Director"),
            ])
        }
        let content = PersonDetailViewModel.makeContent(detail: person(
            knownFor: "Directing",
            cast: [credit(id: 99, title: "Cameo", popularity: 1, role: "Man")],
            crew: directed
        ))

        XCTAssertEqual(content.creditSections.map(\.title), ["Directing", "Acting"])
        XCTAssertEqual(content.creditSections[0].preview.count, 5)
        XCTAssertEqual(content.creditSections[0].totalCount, 12)
        XCTAssertTrue(content.creditSections[0].showsViewAll)
        XCTAssertFalse(content.creditSections[1].showsViewAll)
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

    private func person(
        knownFor: String?,
        cast: [PersonCredit],
        crew: [PersonCredit]
    ) -> PersonDetail {
        PersonDetail(
            id: 1,
            name: "Person",
            biography: "",
            birthday: nil,
            deathday: nil,
            placeOfBirth: nil,
            profilePath: nil,
            knownForDepartment: knownFor,
            imdbID: nil,
            images: [],
            castCredits: cast,
            crewCredits: crew,
            popularity: 0
        )
    }

    private func credit(
        id: Int,
        title: String,
        popularity: Double,
        role: String = "",
        jobs: [PersonCreditJob] = []
    ) -> PersonCredit {
        PersonCredit(
            mediaType: .movie,
            mediaID: id,
            title: title,
            posterPath: nil,
            releaseDate: nil,
            genreIDs: [],
            roleLabel: role,
            jobs: jobs,
            popularity: popularity,
            voteAverage: 0
        )
    }

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
