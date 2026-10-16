//
//  ReviewPrompt.swift
//  SilverScreen
//
//  When to ask for an App Store review: after the 5th saved rating, at most once
//  per app version, never right after a failed save. Ratings saved during
//  onboarding do not count. The root view watches `ReviewPrompter` and calls
//  SwiftUI's `requestReview`.
//

import Foundation

/// Where onboarding records the moment it was finished or skipped.
/// Onboarding owns writing it; this side only reads it.
enum OnboardingCompletion {
    static let defaultsKey = "onboardingCompletedAt"

    /// Nil for people who started before onboarding existed, so all their ratings count.
    static func date(in defaults: UserDefaults) -> Date? {
        defaults.object(forKey: defaultsKey) as? Date
    }
}

/// The review prompt rule, kept free of storage so it can be tested directly.
enum ReviewPromptPolicy {
    /// The rating count that makes a good moment to ask.
    static let ratingThreshold = 5

    /// - Parameters:
    ///   - ratingCount: Ratings saved after onboarding (all ratings when onboarding never ran).
    ///   - currentVersion: The running marketing version.
    ///   - lastPromptedVersion: The version that last asked, or nil when the app never asked.
    ///   - followsFailedSave: The previous save attempt failed, so this success follows an error.
    static func shouldRequest(
        ratingCount: Int,
        currentVersion: String,
        lastPromptedVersion: String?,
        followsFailedSave: Bool
    ) -> Bool {
        guard !followsFailedSave else { return false }
        guard lastPromptedVersion != currentVersion else { return false }
        return ratingCount >= ratingThreshold
    }
}

/// Tracks rating saves and raises `requestCount` when the app should ask for a review.
/// The editor sheet reports every save; the root view asks StoreKit when the count changes.
@Observable
@MainActor
final class ReviewPrompter {
    /// UserDefaults key for the marketing version that last asked.
    static let promptedVersionKey = "reviewPromptedVersion"

    /// Goes up by one each time a review should be requested.
    private(set) var requestCount = 0

    @ObservationIgnored private let appVersion: String
    @ObservationIgnored private let defaults: UserDefaults
    /// Ratings first saved after the given date, or all ratings for nil.
    @ObservationIgnored private let countRatings: @Sendable (Date?) async throws -> Int
    @ObservationIgnored private var previousSaveFailed = false

    init(
        appVersion: String,
        defaults: UserDefaults,
        countRatings: @escaping @Sendable (Date?) async throws -> Int
    ) {
        self.appVersion = appVersion
        self.defaults = defaults
        self.countRatings = countRatings
    }

    /// Records the outcome of a rating save. A cancelled save changes nothing. A failure
    /// skips the next success too, and a count that cannot be read never asks.
    func ratingSaveFinished(_ result: AnnotationEditorWriteResult) async {
        switch result {
            case .cancelled:
                return
            case .failed:
                previousSaveFailed = true
                return
            case .succeeded:
                break
        }
        let followsFailedSave = previousSaveFailed
        previousSaveFailed = false
        guard !followsFailedSave, lastPromptedVersion != appVersion else { return }

        let ratingCount: Int
        do {
            ratingCount = try await countRatings(OnboardingCompletion.date(in: defaults))
        } catch {
            return
        }
        // Read the version again: another save may have asked while the count loaded.
        guard ReviewPromptPolicy.shouldRequest(
            ratingCount: ratingCount,
            currentVersion: appVersion,
            lastPromptedVersion: lastPromptedVersion,
            followsFailedSave: false
        ) else { return }
        defaults.set(appVersion, forKey: Self.promptedVersionKey)
        requestCount += 1
    }

    private var lastPromptedVersion: String? {
        defaults.string(forKey: Self.promptedVersionKey)
    }
}
