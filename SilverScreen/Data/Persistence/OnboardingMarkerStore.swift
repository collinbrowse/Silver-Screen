//
//  OnboardingMarkerStore.swift
//  SilverScreen
//
//  The one value onboarding persists: when the flow was last finished or skipped.
//  The review prompt reads the same key to ignore ratings made during onboarding,
//  so the key name and the `Date` type are a contract.
//

import Foundation

/// Reads and writes the `onboardingCompletedAt` date in UserDefaults.
struct OnboardingMarkerStore {
    /// Shared with the review prompt. Do not rename.
    static let key = "onboardingCompletedAt"

    private let defaults: UserDefaults

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    /// Nil until onboarding has been finished or skipped once.
    func completedAt() -> Date? {
        defaults.object(forKey: Self.key) as? Date
    }

    /// Records the latest finish or skip. Running the flow again from the Library
    /// moves the date forward, so ratings from that run count as onboarding too.
    func markCompleted(at date: Date = Date()) {
        defaults.set(date, forKey: Self.key)
    }
}
