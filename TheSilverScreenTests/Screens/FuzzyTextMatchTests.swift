//
//  FuzzyTextMatchTests.swift
//  TheSilverScreenTests
//

import XCTest
@testable import TheSilverScreen

final class FuzzyTextMatchTests: XCTestCase {
    func test_matches_christopherWaltz_findsChristophWaltz() {
        XCTAssertTrue(FuzzyTextMatch.matches(query: "Christopher Waltz", candidate: "Christoph Waltz"))
    }

    func test_matches_christopherWalz_findsChristophWaltz() {
        XCTAssertTrue(FuzzyTextMatch.matches(query: "Christopher Walz", candidate: "Christoph Waltz"))
    }

    func test_matches_christopherNolan_doesNotFindChristophWaltz() {
        XCTAssertFalse(FuzzyTextMatch.matches(query: "Christopher Nolan", candidate: "Christoph Waltz"))
    }

    func test_matches_shawshank_findsTheShawshankRedemption() {
        XCTAssertTrue(FuzzyTextMatch.matches(query: "shawshank", candidate: "The Shawshank Redemption"))
    }

    func test_matches_spiPrefix_findsSpiderMan() {
        XCTAssertTrue(FuzzyTextMatch.matches(query: "Spi", candidate: "Spider-Man"))
    }

    func test_matches_spiderManWords_findsHyphenatedTitle() {
        XCTAssertTrue(FuzzyTextMatch.matches(query: "spider man", candidate: "Spider-Man"))
    }

    func test_matches_foldedDiacritics_findsAmelie() {
        XCTAssertTrue(FuzzyTextMatch.matches(query: "amelie", candidate: "Amélie"))
    }

    func test_fallbackTokens_keepsTwoLongWordsInOrder() {
        XCTAssertEqual(
            FuzzyTextMatch.fallbackTokens(in: "Christopher Waltz"),
            ["christopher", "waltz"]
        )
        XCTAssertEqual(FuzzyTextMatch.fallbackTokens(in: "Spi"), [])
        XCTAssertEqual(FuzzyTextMatch.fallbackTokens(in: "shawshank"), [])
        XCTAssertEqual(
            FuzzyTextMatch.fallbackTokens(in: "the dark knight rises"),
            ["dark", "knight"]
        )
    }
}
