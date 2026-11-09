//
//  ProSurveyPrompt.swift
//  SilverScreen
//
//  Shared survey state for Settings and Library: whether the survey exists in
//  this build, whether this install has answered, and when the one-time Library
//  card shows. The card appears from the second day the app is opened, until it
//  is dismissed or the survey is answered.
//

import Foundation

@Observable
@MainActor
final class ProSurveyPrompt {
    /// Distinct days opened before the Library card appears: someone who came back.
    static let cardDayThreshold = 2

    private(set) var hasAnswered: Bool
    private(set) var isCardVisible = false

    @ObservationIgnored let repository: ProSurveyRepository
    @ObservationIgnored private let store: ProSurveyStore
    @ObservationIgnored private let analytics: any AnalyticsClient
    @ObservationIgnored private let calendar: Calendar

    init(
        repository: ProSurveyRepository,
        store: ProSurveyStore,
        analytics: any AnalyticsClient,
        calendar: Calendar = .current
    ) {
        self.repository = repository
        self.store = store
        self.analytics = analytics
        self.calendar = calendar
        self.hasAnswered = store.savedAnswers() != nil
        updateCardVisibility()
    }

    var isAvailable: Bool { repository.isAvailable }

    /// Called each time the app comes to the foreground.
    func recordAppOpened(at date: Date = Date()) {
        store.recordOpen(day: AnalyticsRetention.day(date, calendar: calendar))
        updateCardVisibility()
    }

    /// The card is on screen. Counts it once per install.
    func cardAppeared() {
        guard isCardVisible, !store.wasCardShown else { return }
        store.markCardShown()
        analytics.send(.proSurveyCardShown)
    }

    func dismissCard() {
        store.dismissCard()
        updateCardVisibility()
    }

    /// The view model for a survey screen opened from `source`. Building one sends
    /// nothing; the screen reports `opened` once it appears.
    func makeViewModel(source: ProSurveySource) -> ProSurveyViewModel {
        ProSurveyViewModel(
            repository: repository,
            source: source,
            onOpened: { [weak self] in self?.analytics.send(.proSurveyOpened) },
            onSubmitted: { [weak self] in self?.answered() }
        )
    }

    private func answered() {
        hasAnswered = true
        analytics.send(.proSurveySubmitted)
        updateCardVisibility()
    }

    private func updateCardVisibility() {
        isCardVisible = repository.isAvailable
            && !hasAnswered
            && !store.isCardDismissed
            && store.daysOpened >= Self.cardDayThreshold
    }
}
