//
//  ReviewPrompterTests.swift
//  SilverScreenTests
//
//  Save outcomes, the once-per-version record, and the onboarding cutoff, using a
//  throwaway UserDefaults suite and a counted fake in place of the library store.
//

import XCTest
@testable import SilverScreen

@MainActor
final class ReviewPrompterTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() async throws {
        suiteName = "ReviewPrompterTests.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
    }

    func test_ratingSaveFinished_withFifthRating_requestsReviewAndRecordsVersion() async {
        let prompter = makePrompter(ratings: RatingCounter(count: 5))

        await prompter.ratingSaveFinished(.succeeded)

        XCTAssertEqual(prompter.requestCount, 1)
        XCTAssertEqual(defaults.string(forKey: ReviewPrompter.promptedVersionKey), "2.0")
    }

    func test_ratingSaveFinished_withFourthRating_doesNotRequest() async {
        let prompter = makePrompter(ratings: RatingCounter(count: 4))

        await prompter.ratingSaveFinished(.succeeded)

        XCTAssertEqual(prompter.requestCount, 0)
    }

    func test_ratingSaveFinished_pastFifthRating_doesNotRequest() async {
        let prompter = makePrompter(ratings: RatingCounter(count: 6))

        await prompter.ratingSaveFinished(.succeeded)

        XCTAssertEqual(prompter.requestCount, 0)
    }

    func test_ratingSaveFinished_secondTimeInSameVersion_doesNotRequestAgain() async {
        let prompter = makePrompter(ratings: RatingCounter(count: 5))
        await prompter.ratingSaveFinished(.succeeded)

        await prompter.ratingSaveFinished(.succeeded)

        XCTAssertEqual(prompter.requestCount, 1)
    }

    func test_ratingSaveFinished_inNewVersionAfterEarlierPrompt_requests() async {
        defaults.set("1.0", forKey: ReviewPrompter.promptedVersionKey)
        let prompter = makePrompter(ratings: RatingCounter(count: 5))

        await prompter.ratingSaveFinished(.succeeded)

        XCTAssertEqual(prompter.requestCount, 1)
    }

    func test_ratingSaveFinished_whenSaveFailed_doesNotRequest() async {
        let ratings = RatingCounter(count: 5)
        let prompter = makePrompter(ratings: ratings)

        await prompter.ratingSaveFinished(.failed)

        XCTAssertEqual(prompter.requestCount, 0)
        let lookups = await ratings.cutoffs.count
        XCTAssertEqual(lookups, 0)
    }

    func test_ratingSaveFinished_successRightAfterFailure_doesNotRequest() async {
        let prompter = makePrompter(ratings: RatingCounter(count: 5))
        await prompter.ratingSaveFinished(.failed)

        await prompter.ratingSaveFinished(.succeeded)

        XCTAssertEqual(prompter.requestCount, 0)
        XCTAssertNil(defaults.string(forKey: ReviewPrompter.promptedVersionKey))
    }

    func test_ratingSaveFinished_whenCountCannotBeRead_doesNotRequest() async {
        let prompter = makePrompter(ratings: RatingCounter(count: 5, fails: true))

        await prompter.ratingSaveFinished(.succeeded)

        XCTAssertEqual(prompter.requestCount, 0)
    }

    func test_ratingSaveFinished_afterOnboarding_countsOnlyLaterRatings() async {
        let finished = Date(timeIntervalSince1970: 1_800_000_000)
        defaults.set(finished, forKey: OnboardingCompletion.defaultsKey)
        let ratings = RatingCounter(count: 5)
        let prompter = makePrompter(ratings: ratings)

        await prompter.ratingSaveFinished(.succeeded)

        let cutoffs = await ratings.cutoffs
        XCTAssertEqual(cutoffs, [finished])
    }

    func test_ratingSaveFinished_withoutOnboardingDate_countsAllRatings() async {
        let ratings = RatingCounter(count: 5)
        let prompter = makePrompter(ratings: ratings)

        await prompter.ratingSaveFinished(.succeeded)

        let cutoffs = await ratings.cutoffs
        XCTAssertEqual(cutoffs, [nil])
    }

    private func makePrompter(ratings: RatingCounter) -> ReviewPrompter {
        ReviewPrompter(appVersion: "2.0", defaults: defaults) { cutoff in
            try await ratings.count(createdAfter: cutoff)
        }
    }
}

/// Stands in for `SQLiteLibraryStore.countRatings` and records each cutoff it was asked for.
private actor RatingCounter {
    private let total: Int
    private let fails: Bool
    private(set) var cutoffs: [Date?] = []

    init(count: Int, fails: Bool = false) {
        self.total = count
        self.fails = fails
    }

    func count(createdAfter cutoff: Date?) throws -> Int {
        cutoffs.append(cutoff)
        if fails {
            throw AppError.persistence
        }
        return total
    }
}
