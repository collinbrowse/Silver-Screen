//
//  OnboardingGateTests.swift
//  SilverScreenTests
//
//  Who sees onboarding, and that skip and finish both write the marker the
//  review prompt reads.
//

import XCTest
@testable import SilverScreen

@MainActor
final class OnboardingGateTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "test.onboarding.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    // MARK: - Who sees it

    func test_shouldPresent_emptyLibraryNoRatingsNoMarker_isTrue() {
        XCTAssertTrue(
            OnboardingGate.shouldPresent(
                snapshot: LibrarySnapshot(lists: [], entries: []),
                annotations: [],
                completedAt: nil,
                isDemo: false
            )
        )
    }

    func test_shouldPresent_libraryHasEntry_isFalse() async throws {
        let lists = ListsRepository.empty()
        _ = try await lists.addToWatched(OnboardingFixtures.movieDraft(id: 1))
        let snapshot = try await lists.snapshot()

        XCTAssertFalse(
            OnboardingGate.shouldPresent(snapshot: snapshot, annotations: [], completedAt: nil, isDemo: false)
        )
    }

    func test_shouldPresent_ratingSaved_isFalse() {
        let rating = MediaAnnotation(key: .movie(1), score: 7, note: nil, watchedAt: nil)

        XCTAssertFalse(
            OnboardingGate.shouldPresent(
                snapshot: LibrarySnapshot(lists: [], entries: []),
                annotations: [rating],
                completedAt: nil,
                isDemo: false
            )
        )
    }

    func test_shouldPresent_markerSet_isFalse() {
        XCTAssertFalse(
            OnboardingGate.shouldPresent(
                snapshot: LibrarySnapshot(lists: [], entries: []),
                annotations: [],
                completedAt: Date(),
                isDemo: false
            )
        )
    }

    func test_shouldPresent_demoMode_isFalse() {
        XCTAssertFalse(
            OnboardingGate.shouldPresent(
                snapshot: LibrarySnapshot(lists: [], entries: []),
                annotations: [],
                completedAt: nil,
                isDemo: true
            )
        )
    }

    func test_evaluate_emptyLibrary_presents() async {
        let gate = makeGate()

        await gate.evaluate()

        XCTAssertTrue(gate.isPresented)
    }

    func test_evaluate_existingLibrary_doesNotPresent() async throws {
        let lists = ListsRepository.empty()
        _ = try await lists.addToWatched(OnboardingFixtures.movieDraft(id: 1))
        let gate = makeGate(lists: lists)

        await gate.evaluate()

        XCTAssertFalse(gate.isPresented)
    }

    func test_evaluate_afterMarker_doesNotPresent() async {
        OnboardingMarkerStore(defaults: defaults).markCompleted()
        let gate = makeGate()

        await gate.evaluate()

        XCTAssertFalse(gate.isPresented)
    }

    func test_evaluate_demoMode_doesNotPresent() async {
        let gate = makeGate(isDemo: true)

        await gate.evaluate()

        XCTAssertFalse(gate.isPresented)
    }

    // MARK: - Closing

    func test_skip_writesMarkerAndDismisses() {
        let gate = makeGate()
        gate.reopen()

        gate.skip()

        XCTAssertNotNil(defaults.object(forKey: "onboardingCompletedAt") as? Date)
        XCTAssertFalse(gate.isPresented)
    }

    func test_finish_writesMarkerAndOpensLibraryRoot() async {
        let router = AppRouter()
        router.favorites.push(.libraryList(id: UUID()))
        let gate = makeGate(router: router)
        gate.reopen()

        await gate.finish()

        XCTAssertNotNil(defaults.object(forKey: "onboardingCompletedAt") as? Date)
        XCTAssertFalse(gate.isPresented)
        XCTAssertEqual(router.selectedTab, .library)
        XCTAssertTrue(router.favorites.path.isEmpty)
    }

    func test_viewModelSkip_writesMarker() {
        let viewModel = OnboardingFixtures.flow(gate: makeGate())

        viewModel.skip()

        XCTAssertNotNil(OnboardingMarkerStore(defaults: defaults).completedAt())
    }

    func test_viewModelFinish_writesMarker() async {
        let viewModel = OnboardingFixtures.flow(gate: makeGate())
        viewModel.getStarted()
        viewModel.continueToWatchlist()

        await viewModel.finish()

        XCTAssertNotNil(OnboardingMarkerStore(defaults: defaults).completedAt())
    }

    func test_viewModelSteps_goForwardAndBack() {
        let viewModel = OnboardingFixtures.flow(gate: makeGate())

        viewModel.getStarted()
        viewModel.continueToWatchlist()
        viewModel.back()

        XCTAssertEqual(viewModel.step, .seen)
    }

    private func makeGate(
        lists: ListsRepository = .empty(),
        isDemo: Bool = false,
        router: AppRouter = AppRouter()
    ) -> OnboardingGate {
        OnboardingGate(
            marker: OnboardingMarkerStore(defaults: defaults),
            lists: lists,
            annotations: .empty(),
            isDemo: isDemo,
            router: router
        )
    }
}

/// Shared builders for the onboarding tests.
@MainActor
enum OnboardingFixtures {
    static func movieDraft(id: Int, title: String = "Movie", popularity: Double = 1) -> ListItemDraft {
        ListItemDraft(
            id: id,
            kind: .movie,
            title: title,
            imagePath: "/p.jpg",
            releaseDate: nil,
            genreNames: [],
            voteAverage: 7,
            popularity: popularity
        )
    }

    static func seriesDraft(id: Int, title: String = "Series") -> ListItemDraft {
        ListItemDraft(
            id: id,
            kind: .tv,
            title: title,
            imagePath: "/s.jpg",
            releaseDate: nil,
            genreNames: [],
            voteAverage: 8,
            popularity: 1
        )
    }

    static func flow(gate: OnboardingGate) -> OnboardingViewModel {
        let client = FakeHTTPClient(stub: .failure(URLError(.notConnectedToInternet)))
        let lists = ListsRepository.empty()
        return OnboardingViewModel(
            movies: .test(client: client),
            shows: .test(client: client),
            lists: lists,
            annotations: .empty(),
            tvWatch: TVWatchRepository(store: InMemoryTVWatchStore(), lists: lists, logger: SilentLogger()),
            awards: AwardsRepository(catalog: .empty),
            gate: gate
        )
    }
}
