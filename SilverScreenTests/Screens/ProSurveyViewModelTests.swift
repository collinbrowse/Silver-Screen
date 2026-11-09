//
//  ProSurveyViewModelTests.swift
//  SilverScreenTests
//

import XCTest
@testable import SilverScreen

@MainActor
final class ProSurveyViewModelTests: XCTestCase {
    private func makeRepository(
        stub: FakeHTTPClient.Stub = .success(Data(), status: 204),
        store: ProSurveyStore = ProSurveyStore(suiteName: makeTestSuite())
    ) -> ProSurveyRepository {
        ProSurveyRepository(
            client: FakeHTTPClient(stub: stub),
            endpoint: URL(string: "https://proxy.example.workers.dev/survey")!,
            store: store,
            appInfo: AppInfo(marketingVersion: "0.1.1", build: "11"),
            isTestMode: true,
            logger: SilentLogger(),
            sleeper: NoopSleeper()
        )
    }

    func test_canSubmit_withNothingPicked_isFalse() {
        let viewModel = ProSurveyViewModel(repository: makeRepository(), source: .settings)
        viewModel.other = "   "

        XCTAssertFalse(viewModel.canSubmit)
    }

    func test_canSubmit_withOnlyFreeText_isTrue() {
        let viewModel = ProSurveyViewModel(repository: makeRepository(), source: .settings)
        viewModel.other = "Watch parties"

        XCTAssertTrue(viewModel.canSubmit)
    }

    func test_toggle_addsThenRemovesAPick() {
        let viewModel = ProSurveyViewModel(repository: makeRepository(), source: .settings)

        viewModel.toggle(.widgets)
        XCTAssertTrue(viewModel.isSelected(.widgets))
        viewModel.toggle(.widgets)

        XCTAssertFalse(viewModel.isSelected(.widgets))
    }

    func test_submit_whenAccepted_isSentAndReportsSubmitted() async {
        var submitted = 0
        let viewModel = ProSurveyViewModel(repository: makeRepository(), source: .settings, onSubmitted: { submitted += 1 })
        viewModel.toggle(.stats)

        await viewModel.submit()

        XCTAssertEqual(viewModel.state, .sent)
        XCTAssertEqual(submitted, 1)
    }

    func test_submit_whenOffline_failsAndKeepsPicks() async {
        var submitted = 0
        let viewModel = ProSurveyViewModel(
            repository: makeRepository(stub: .failure(URLError(.notConnectedToInternet))),
            source: .settings,
            onSubmitted: { submitted += 1 }
        )
        viewModel.toggle(.sync)

        await viewModel.submit()

        XCTAssertEqual(viewModel.state, .failed(.offline))
        XCTAssertTrue(viewModel.isSelected(.sync))
        XCTAssertTrue(viewModel.canSubmit)
        XCTAssertEqual(submitted, 0)
    }

    func test_toggle_afterFailure_returnsToComposing() async {
        let viewModel = ProSurveyViewModel(
            repository: makeRepository(stub: .failure(URLError(.notConnectedToInternet))),
            source: .settings
        )
        viewModel.toggle(.sync)
        await viewModel.submit()

        viewModel.toggle(.widgets)

        XCTAssertEqual(viewModel.state, .composing)
    }

    func test_init_withEarlierAnswers_prefillsThem() {
        let store = ProSurveyStore(suiteName: makeTestSuite())
        store.saveAnswers(ProSurveyAnswers(features: [.export], other: "CSV please"))

        let viewModel = ProSurveyViewModel(repository: makeRepository(store: store), source: .settings)

        XCTAssertTrue(viewModel.isEditingEarlierAnswers)
        XCTAssertTrue(viewModel.isSelected(.export))
        XCTAssertEqual(viewModel.other, "CSV please")
    }

    func test_other_isCappedAtTheWorkerLimit() {
        let viewModel = ProSurveyViewModel(repository: makeRepository(), source: .settings)

        viewModel.other = String(repeating: "a", count: ProSurvey.otherCharacterLimit + 20)

        XCTAssertEqual(viewModel.other.count, ProSurvey.otherCharacterLimit)
    }

    func test_appeared_reportsOpenOnce() {
        var opened = 0
        let viewModel = ProSurveyViewModel(repository: makeRepository(), source: .settings, onOpened: { opened += 1 })

        viewModel.appeared()
        viewModel.appeared()

        XCTAssertEqual(opened, 1)
    }
}
