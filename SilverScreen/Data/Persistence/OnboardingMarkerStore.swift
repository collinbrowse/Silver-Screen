//
//  OnboardingMarkerStore.swift
//  SilverScreen
//
//  The one value onboarding persists: when the flow was last finished or skipped.
//  The key and the read live in `OnboardingCompletion`, shared with the review
//  prompt, which uses the date to ignore ratings made during onboarding.
//

import Foundation

/// Reads and writes the `onboardingCompletedAt` date in UserDefaults.
struct OnboardingMarkerStore {
    private let defaults: UserDefaults

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    /// Nil until onboarding has been finished or skipped once.
    func completedAt() -> Date? {
        OnboardingCompletion.date(in: defaults)
    }

    /// Records the latest finish or skip. Running the flow again from the Library
    /// moves the date forward, so ratings from that run count as onboarding too.
    func markCompleted(at date: Date = Date()) {
        defaults.set(date, forKey: OnboardingCompletion.defaultsKey)
    }
}
