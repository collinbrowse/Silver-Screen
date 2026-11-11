//
//  ProSurveyRepositoryTests.swift
//  SilverScreenTests
//
//  The survey POST, its error translation, and what the device remembers.
//  Real repository and store over a fake HTTP client and a throwaway defaults suite.
//

import XCTest
@testable import SilverScreen

final class ProSurveyRepositoryTests: XCTestCase {
    private let endpoint = URL(string: "https://proxy.example.workers.dev/survey")!
    private let answers = ProSurveyAnswers(features: [.widgets, .stats], other: "Watch parties")

    private func makeRepository(
        client: any HTTPClient,
        store: ProSurveyStore = ProSurveyStore(suiteName: makeTestSuite()),
        endpoint: URL? = URL(string: "https://proxy.example.workers.dev/survey")!
    ) -> ProSurveyRepository {
        ProSurveyRepository(
            client: client,
            endpoint: endpoint,
            store: store,
            appInfo: AppInfo(marketingVersion: "0.1.1", build: "11"),
            isTestMode: true,
            logger: SilentLogger(),
            sleeper: NoopSleeper()
        )
    }

    // MARK: - Endpoint

    func test_endpoint_forProxy_isSurveyPathOnProxyHost() throws {
        let connection = TMDBConnection.proxy(baseURL: URL(string: "https://proxy.example.workers.dev/3")!)

        XCTAssertEqual(ProSurveyRequest.endpoint(for: connection), endpoint)
    }

    func test_endpoint_forDirectTMDB_isNil() {
        let connection = TMDBConnection.direct(accessToken: "token")

        XCTAssertNil(ProSurveyRequest.endpoint(for: connection))
    }

    func test_isAvailable_withoutEndpoint_isFalse() {
        let repository = makeRepository(client: FakeHTTPClient(stub: .success(Data(), status: 204)), endpoint: nil)

        XCTAssertFalse(repository.isAvailable)
    }

    // MARK: - Submit

    func test_submit_postsSortedFeaturesAndBuildDetails() async throws {
        let client = RecordingHTTPClient(stub: .success(Data(), status: 204))
        let store = ProSurveyStore(suiteName: makeTestSuite())
        let repository = makeRepository(client: client, store: store)

        try await repository.submit(answers, source: .libraryCard)

        let requests = await client.requests
        let request = try XCTUnwrap(requests.last)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url, endpoint)
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
        let body = try XCTUnwrap(request.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["surveyID"] as? String, ProSurvey.id)
        XCTAssertEqual(json["responseID"] as? String, store.responseID().lowercased())
        XCTAssertEqual(json["features"] as? [String], ["stats", "widgets"])
        XCTAssertEqual(json["other"] as? String, "Watch parties")
        XCTAssertEqual(json["source"] as? String, "libraryCard")
        XCTAssertEqual(json["appVersion"] as? String, "0.1.1")
        XCTAssertEqual(json["build"] as? String, "11")
        XCTAssertEqual(json["isTest"] as? Bool, true)
    }

    func test_submit_whenAccepted_savesAnswers() async throws {
        let repository = makeRepository(client: FakeHTTPClient(stub: .success(Data(), status: 204)))

        try await repository.submit(answers, source: .settings)

        XCTAssertEqual(repository.savedAnswers(), answers)
    }

    func test_submit_twice_sendsSameResponseID() async throws {
        let client = RecordingHTTPClient(stub: .success(Data(), status: 204))
        let repository = makeRepository(client: client)

        try await repository.submit(answers, source: .settings)
        try await repository.submit(ProSurveyAnswers(features: [.sync], other: nil), source: .settings)

        let requests = await client.requests
        let ids = try requests.map { request in
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
            return json["responseID"] as? String
        }
        XCTAssertEqual(ids.count, 2)
        XCTAssertEqual(ids[0], ids[1])
    }

    func test_submit_whenRejected_throwsServerErrorAndSavesNothing() async {
        let repository = makeRepository(client: FakeHTTPClient(stub: .success(Data(), status: 400)))

        do {
            try await repository.submit(answers, source: .settings)
            XCTFail("Expected a throw")
        } catch {
            XCTAssertEqual(error as? AppError, .server(status: 400))
        }
        XCTAssertNil(repository.savedAnswers())
    }

    func test_submit_whenOffline_throwsOffline() async {
        let repository = makeRepository(client: FakeHTTPClient(stub: .failure(URLError(.notConnectedToInternet))))

        do {
            try await repository.submit(answers, source: .settings)
            XCTFail("Expected a throw")
        } catch {
            XCTAssertEqual(error as? AppError, .offline)
        }
    }

    func test_submit_whenServerFailsThenRecovers_retriesAndSaves() async throws {
        let client = SequencingHTTPClient(stubs: [.success(Data(), status: 503), .success(Data(), status: 204)])
        let repository = makeRepository(client: client)

        try await repository.submit(answers, source: .settings)

        let count = await client.requestCount
        XCTAssertEqual(count, 2)
        XCTAssertEqual(repository.savedAnswers(), answers)
    }

    // MARK: - Order

    func test_displayOrder_isStableForOneInstallAndHasEveryFeature() {
        let store = ProSurveyStore(suiteName: makeTestSuite())
        let repository = makeRepository(client: FakeHTTPClient(stub: .success(Data(), status: 204)), store: store)

        let first = repository.displayOrder()
        let second = repository.displayOrder()

        XCTAssertEqual(first, second)
        XCTAssertEqual(Set(first), Set(ProFeature.allCases))
        XCTAssertEqual(first.count, ProFeature.allCases.count)
    }

    func test_displayOrder_forAnySeed_putsAppIconsLast() {
        for seed in UInt64(0)..<16 {
            XCTAssertEqual(ProFeature.displayOrder(seed: seed &* 0x9E37_79B9).last, .appIcons)
        }
    }

    func test_displayOrder_differsBetweenSeeds() {
        let orders = Set((0..<8).map { ProFeature.displayOrder(seed: UInt64($0) &* 0x1234_5678_9ABC)})

        XCTAssertGreaterThan(orders.count, 1)
    }

    // MARK: - Store

    func test_store_recordOpen_countsDistinctDays() {
        let store = ProSurveyStore(suiteName: makeTestSuite())

        store.recordOpen(day: "2026-11-09")
        store.recordOpen(day: "2026-11-09")
        let count = store.recordOpen(day: "2026-11-10")

        XCTAssertEqual(count, 2)
        XCTAssertEqual(store.daysOpened, 2)
    }

    func test_store_keysAreScopedBySurvey() {
        let suite = makeTestSuite()
        let first = ProSurveyStore(suiteName: suite, surveyID: "pro-features-1")
        first.saveAnswers(answers)

        let next = ProSurveyStore(suiteName: suite, surveyID: "pro-features-2")

        XCTAssertNil(next.savedAnswers())
        XCTAssertNotEqual(first.responseID(), next.responseID())
    }
}
