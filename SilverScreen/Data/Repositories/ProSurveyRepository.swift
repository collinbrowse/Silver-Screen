//
//  ProSurveyRepository.swift
//  SilverScreen
//
//  Sends survey answers to the Worker and remembers them on the device. The
//  send is an upsert keyed by the install's response ID, so retrying or changing
//  answers never counts one person twice. See worker/README.md → Feature survey.
//

import Foundation

struct ProSurveyRepository: Sendable {
    private let client: any HTTPClient
    /// Nil in builds without the Worker; the survey is then hidden.
    private let endpoint: URL?
    private let store: ProSurveyStore
    private let appInfo: AppInfo
    private let isTestMode: Bool
    private let logger: any AppLogging
    private let sleeper: any Sleeper

    init(
        client: any HTTPClient,
        endpoint: URL?,
        store: ProSurveyStore,
        appInfo: AppInfo,
        isTestMode: Bool,
        logger: any AppLogging,
        sleeper: any Sleeper = TaskSleeper()
    ) {
        self.client = client
        self.endpoint = endpoint
        self.store = store
        self.appInfo = appInfo
        self.isTestMode = isTestMode
        self.logger = logger
        self.sleeper = sleeper
    }

    var isAvailable: Bool { endpoint != nil }

    /// The answers last sent from this install, to prefill the form.
    func savedAnswers() -> ProSurveyAnswers? {
        store.savedAnswers()
    }

    /// The option order for this install, stable across launches.
    func displayOrder() -> [ProFeature] {
        let uuid = UUID(uuidString: store.responseID())?.uuid
        let seed = uuid.map { bytes in
            withUnsafeBytes(of: bytes) { raw in raw.prefix(8).reduce(UInt64(0)) { $0 << 8 | UInt64($1) } }
        } ?? 0
        return ProFeature.displayOrder(seed: seed)
    }

    /// Sends the answers and saves them locally once the Worker accepts them.
    /// Throws `AppError`; the saved answers are unchanged on failure.
    func submit(_ answers: ProSurveyAnswers, source: ProSurveySource) async throws {
        guard let endpoint else { throw AppError.invalidBaseURL }
        let body = ProSurveySubmissionDTO(
            surveyID: store.surveyID,
            responseID: store.responseID().lowercased(),
            features: answers.features.map(\.rawValue).sorted(),
            other: answers.other,
            source: source.rawValue,
            appVersion: appInfo.marketingVersion,
            build: appInfo.build,
            isTest: isTestMode
        )
        let request: URLRequest
        do {
            request = try ProSurveyRequest.make(body, endpoint: endpoint)
        } catch {
            logger.error("Survey body encode failed", category: .networking)
            throw AppError.unknown
        }
        // Safe to retry: the Worker upserts on the response ID.
        _ = try await HTTPTransport.data(
            for: request,
            client: client,
            logger: logger,
            context: "Survey",
            sleeper: sleeper
        )
        store.saveAnswers(answers)
    }
}
