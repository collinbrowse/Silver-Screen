//
//  FeedbackViewModel.swift
//  SilverScreen
//
//  A message and an optional reply address, sent as Sentry user feedback.
//

import Foundation

/// What the person typed, trimmed. `email` is nil when they left it blank.
struct FeedbackSubmission: Sendable, Equatable {
    let message: String
    let email: String?
}

@Observable
@MainActor
final class FeedbackViewModel {
    enum State: Sendable, Equatable {
        case composing
        case sent
        /// Nothing could take the message (no Sentry DSN in this build).
        case unavailable
    }

    var message = ""
    var email = ""
    private(set) var state: State = .composing

    private let send: @MainActor (FeedbackSubmission) -> Bool

    /// - Parameter send: Delivers the feedback and returns false when nothing can take it.
    init(send: @escaping @MainActor (FeedbackSubmission) -> Bool) {
        self.send = send
    }

    var trimmedEmail: String {
        email.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Blank is fine. Anything typed needs one `@` with text on both sides and a dot in the domain.
    var emailIsValid: Bool {
        let value = trimmedEmail
        guard !value.isEmpty else {
            return true
        }
        let parts = value.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[0].isEmpty, !value.contains(" ") else {
            return false
        }
        let domain = parts[1]
        return domain.contains(".") && !domain.hasPrefix(".") && !domain.hasSuffix(".")
    }

    var canSubmit: Bool {
        state == .composing
            && !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && emailIsValid
    }

    func submit() {
        guard canSubmit else {
            return
        }
        let submission = FeedbackSubmission(
            message: message.trimmingCharacters(in: .whitespacesAndNewlines),
            email: trimmedEmail.isEmpty ? nil : trimmedEmail
        )
        state = send(submission) ? .sent : .unavailable
    }
}
