//
//  DiaryEntryTests.swift
//  SilverScreenTests
//
//  Diary domain rules: calendar days, tag cleanup, normalization, and the Letterboxd
//  rating conversion an importer will rely on.
//

import XCTest
@testable import SilverScreen

final class DiaryEntryTests: XCTestCase {
    func test_diaryDayISO_validDay_roundTrips() {
        let day = DiaryDay(iso: "2026-02-28")

        XCTAssertEqual(day, DiaryDay(year: 2026, month: 2, day: 28))
        XCTAssertEqual(day?.iso, "2026-02-28")
    }

    func test_diaryDayISO_impossibleOrMalformed_isNil() {
        XCTAssertNil(DiaryDay(iso: "2026-02-30"))
        XCTAssertNil(DiaryDay(iso: "2026-2-3"))
        XCTAssertNil(DiaryDay(iso: "16/10/2026"))
        XCTAssertNil(DiaryDay(iso: ""))
    }

    func test_diaryDayFromDate_usesCalendarTimezone() throws {
        var losAngeles = Calendar(identifier: .gregorian)
        losAngeles.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        // 05:30 UTC on 17 Oct is still the evening of 16 Oct in Los Angeles.
        let lateEvening = try XCTUnwrap(LibrarySQLDate.decode("2026-10-17T05:30:00.000Z"))

        XCTAssertEqual(DiaryDay(lateEvening, calendar: losAngeles), DiaryDay(year: 2026, month: 10, day: 16))
    }

    func test_diaryDay_comparesChronologically() {
        XCTAssertLessThan(DiaryDay(year: 2025, month: 12, day: 31), DiaryDay(year: 2026, month: 1, day: 1))
        XCTAssertLessThan(DiaryDay(year: 2026, month: 1, day: 9), DiaryDay(year: 2026, month: 1, day: 10))
    }

    func test_diaryTagsParse_trimsDropsEmptiesAndCaseInsensitiveRepeats() {
        XCTAssertEqual(DiaryTags.parse("  horror, Halloween ,,horror, HALLOWEEN"), ["horror", "Halloween"])
    }

    func test_diaryTagsJoined_matchesLetterboxdCommaForm() {
        XCTAssertEqual(DiaryTags.joined(["horror", "with friends"]), "horror, with friends")
    }

    func test_normalized_dropsInvalidScoreAndBlankReview() {
        let entry = DiaryFixtures.entry(score: 0, review: " \n ")

        let normalized = entry.normalized()

        XCTAssertNil(normalized.score)
        XCTAssertNil(normalized.review)
    }

    func test_normalized_keepsValidHalfPointScore() {
        XCTAssertEqual(DiaryFixtures.entry(score: 7.5).normalized().score, 7.5)
    }

    func test_letterboxdStarsToScore_doublesStars() {
        XCTAssertEqual(LetterboxdRating.score(fromStars: 0.5), 1)
        XCTAssertEqual(LetterboxdRating.score(fromStars: 4.5), 9)
        XCTAssertEqual(LetterboxdRating.score(fromStars: 5), 10)
    }

    func test_letterboxdStarsToScore_outOfRange_isNil() {
        XCTAssertNil(LetterboxdRating.score(fromStars: 0))
        XCTAssertNil(LetterboxdRating.score(fromStars: 5.5))
        XCTAssertNil(LetterboxdRating.score(fromStars: 3.3))
    }

    func test_scoreToLetterboxdStars_roundsToNearestHalfStar() {
        XCTAssertEqual(LetterboxdRating.stars(fromScore: 8), 4)
        XCTAssertEqual(LetterboxdRating.stars(fromScore: 7.5), 4)
        XCTAssertEqual(LetterboxdRating.stars(fromScore: 1), 0.5)
        XCTAssertEqual(LetterboxdRating.stars(fromScore: 0.5), 0.5)
        XCTAssertEqual(LetterboxdRating.stars(fromScore: 10), 5)
        XCTAssertNil(LetterboxdRating.stars(fromScore: 0))
    }

    func test_subjectItemKey_matchesListItemKey() {
        XCTAssertEqual(DiarySubject.movie(550).itemKey, "movie-550")
        XCTAssertEqual(DiarySubject.series(42).itemKey, "tv-42")
    }
}
