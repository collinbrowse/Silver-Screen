//
//  ProSurveyPromptTests.swift
//  SilverScreenTests
//
//  When the Library card shows, and which counts reach analytics.
//

import XCTest
@testable import SilverScreen

@MainActor
final class ProSurveyPromptTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func day(_ value: Int) -> Date {
        Date(timeIntervalSince1970: 1_793_000_000 + TimeInterval(value) * 86_400)
    }

    private func makePrompt(
        store: ProSurveyStore = ProSurveyStore(suiteName: makeTestSuite()),
        analytics: SpyAnalyticsClient = SpyAnalyticsClient(),
        endpoint: URL? = URL(string: "https://proxy.example.workers.dev/survey")!
    ) -> ProSurveyPrompt {
        ProSurveyPrompt(
            repository: ProSurveyRepository(
                client: FakeHTTPClient(stub: .success(Data(), status: 204)),
                endpoint: endpoint,
                store: store,
                appInfo: AppInfo(marketingVersion: "0.1.1", build: "11"),
                isTestMode: true,
                logger: SilentLogger(),
                sleeper: NoopSleeper()
            ),
            store: store,
            analytics: analytics,
            calendar: calendar
        )
    }

    func test_card_onFirstDay_isHidden() {
        let prompt = makePrompt()

        prompt.recordAppOpened(at: day(0))
        prompt.recordAppOpened(at: day(0).addingTimeInterval(3_600))

        XCTAssertFalse(prompt.isCardVisible)
    }

    func test_card_onSecondDay_isVisible() {
        let prompt = makePrompt()

        prompt.recordAppOpened(at: day(0))
        prompt.recordAppOpened(at: day(1))

        XCTAssertTrue(prompt.isCardVisible)
    }

    func test_card_afterDismiss_staysHiddenAcrossLaunches() {
        let store = ProSurveyStore(suiteName: makeTestSuite())
        let prompt = makePrompt(store: store)
        prompt.recordAppOpened(at: day(0))
        prompt.recordAppOpened(at: day(1))

        prompt.dismissCard()
        let relaunched = makePrompt(store: store)
        relaunched.recordAppOpened(at: day(2))

        XCTAssertFalse(prompt.isCardVisible)
        XCTAssertFalse(relaunched.isCardVisible)
    }

    func test_card_withoutWorker_isHidden() {
        let prompt = makePrompt(endpoint: nil)

        prompt.recordAppOpened(at: day(0))
        prompt.recordAppOpened(at: day(1))

        XCTAssertFalse(prompt.isAvailable)
        XCTAssertFalse(prompt.isCardVisible)
    }

    func test_submit_hidesCardAndMarksAnswered() async {
        let spy = SpyAnalyticsClient()
        let prompt = makePrompt(analytics: spy)
        prompt.recordAppOpened(at: day(0))
        prompt.recordAppOpened(at: day(1))
        let viewModel = prompt.makeViewModel(source: .libraryCard)
        viewModel.toggle(.widgets)

        await viewModel.submit()

        XCTAssertTrue(prompt.hasAnswered)
        XCTAssertFalse(prompt.isCardVisible)
        XCTAssertEqual(spy.events, [.proSurveySubmitted])
    }

    func test_cardAppeared_sendsShownOncePerInstall() {
        let store = ProSurveyStore(suiteName: makeTestSuite())
        let spy = SpyAnalyticsClient()
        let prompt = makePrompt(store: store, analytics: spy)
        prompt.recordAppOpened(at: day(0))
        prompt.recordAppOpened(at: day(1))

        prompt.cardAppeared()
        prompt.cardAppeared()
        makePrompt(store: store, analytics: spy).cardAppeared()

        XCTAssertEqual(spy.events, [.proSurveyCardShown])
    }

    func test_makeViewModel_sendsOpenedOnlyWhenScreenAppears() {
        let spy = SpyAnalyticsClient()
        let prompt = makePrompt(analytics: spy)

        let viewModel = prompt.makeViewModel(source: .settings)
        XCTAssertEqual(spy.events, [])
        viewModel.appeared()

        XCTAssertEqual(spy.events, [.proSurveyOpened])
    }
}
