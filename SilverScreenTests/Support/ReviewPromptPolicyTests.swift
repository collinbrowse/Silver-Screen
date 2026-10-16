//
//  ReviewPromptPolicyTests.swift
//  SilverScreenTests
//

import XCTest
@testable import SilverScreen

final class ReviewPromptPolicyTests: XCTestCase {
    func test_shouldRequest_withFourRatings_isFalse() {
        XCTAssertFalse(request(ratingCount: 4))
    }

    func test_shouldRequest_withFifthRating_isTrue() {
        XCTAssertTrue(request(ratingCount: 5))
    }

    func test_shouldRequest_pastThresholdInNewVersion_isTrue() {
        XCTAssertTrue(request(ratingCount: 12, lastPromptedVersion: "1.0"))
    }

    func test_shouldRequest_whenThisVersionAlreadyAsked_isFalse() {
        XCTAssertFalse(request(ratingCount: 6, lastPromptedVersion: "1.1"))
    }

    func test_shouldRequest_afterFailedSave_isFalse() {
        XCTAssertFalse(request(ratingCount: 5, followsFailedSave: true))
    }

    private func request(
        ratingCount: Int,
        lastPromptedVersion: String? = nil,
        followsFailedSave: Bool = false
    ) -> Bool {
        ReviewPromptPolicy.shouldRequest(
            ratingCount: ratingCount,
            currentVersion: "1.1",
            lastPromptedVersion: lastPromptedVersion,
            followsFailedSave: followsFailedSave
        )
    }
}
