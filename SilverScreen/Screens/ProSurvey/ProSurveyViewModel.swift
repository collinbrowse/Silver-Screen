//
//  ProSurveyViewModel.swift
//  SilverScreen
//
//  The "Pro is coming soon" form: pick any number of features, optionally write
//  something else, send. Reopening shows the last answers, and sending again
//  replaces them.
//

import Foundation

@Observable
@MainActor
final class ProSurveyViewModel {
    enum State: Sendable, Equatable {
        case composing
        case sending
        case sent
        /// The send failed; the picks stay so the person can try again.
        case failed(AppError)
    }

    /// Every option, in this install's order.
    let options: [ProFeature]
    private(set) var selected: Set<ProFeature>
    var other: String {
        didSet {
            if other.count > ProSurvey.otherCharacterLimit {
                other = String(other.prefix(ProSurvey.otherCharacterLimit))
            }
        }
    }
    private(set) var state: State = .composing
    /// True when this install already sent answers before this screen opened.
    let isEditingEarlierAnswers: Bool

    @ObservationIgnored private let repository: ProSurveyRepository
    @ObservationIgnored private let source: ProSurveySource
    @ObservationIgnored private let onOpened: @MainActor () -> Void
    @ObservationIgnored private let onSubmitted: @MainActor () -> Void
    @ObservationIgnored private var hasReportedOpen = false

    init(
        repository: ProSurveyRepository,
        source: ProSurveySource,
        onOpened: @escaping @MainActor () -> Void = {},
        onSubmitted: @escaping @MainActor () -> Void = {}
    ) {
        self.repository = repository
        self.source = source
        self.onOpened = onOpened
        self.onSubmitted = onSubmitted
        self.options = repository.displayOrder()
        let saved = repository.savedAnswers()
        self.selected = saved?.features ?? []
        self.other = saved?.other ?? ""
        self.isEditingEarlierAnswers = saved != nil
    }

    var trimmedOther: String? {
        let value = other.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    var canSubmit: Bool {
        switch state {
            case .sending, .sent:
                false
            case .composing, .failed:
                !selected.isEmpty || trimmedOther != nil
        }
    }

    func isSelected(_ feature: ProFeature) -> Bool {
        selected.contains(feature)
    }

    /// Flips one pick. A change after a failure returns to composing.
    func toggle(_ feature: ProFeature) {
        guard state != .sending, state != .sent else { return }
        if selected.contains(feature) {
            selected.remove(feature)
        } else {
            selected.insert(feature)
        }
        if case .failed = state {
            state = .composing
        }
    }

    /// The screen appeared. Reports the open once per screen.
    func appeared() {
        guard !hasReportedOpen else { return }
        hasReportedOpen = true
        onOpened()
    }

    /// Sends the answers. Ignored while a send is in flight or when nothing is picked.
    func submit() async {
        guard canSubmit else { return }
        state = .sending
        let answers = ProSurveyAnswers(features: selected, other: trimmedOther)
        do {
            try await repository.submit(answers, source: source)
            state = .sent
            onSubmitted()
        } catch is CancellationError {
            state = .composing
        } catch let error as AppError {
            state = .failed(error)
        } catch {
            state = .failed(.unknown)
        }
    }
}
