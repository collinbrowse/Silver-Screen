//
//  ShareCardContentTests.swift
//  SilverScreenTests
//
//  The words and posters a share card carries for a watch and for a list.
//

import XCTest
@testable import SilverScreen

final class ShareCardContentTests: XCTestCase {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()
    private let locale = Locale(identifier: "en_US")

    func test_watch_ratedWithReview_carriesScoreDateAndPoster() {
        let card = ShareCardContent.watch(entry(score: 8.5, review: "  Loved it.  "), calendar: calendar, locale: locale)

        XCTAssertEqual(card.kind, .watch)
        XCTAssertEqual(card.title, "Arrival")
        XCTAssertEqual(card.subtitle, "2016")
        XCTAssertEqual(card.scoreText, "8.5")
        XCTAssertEqual(card.reviewExcerpt, "Loved it.")
        XCTAssertEqual(card.dateLine, "Watched March 3, 2026")
        XCTAssertEqual(card.posterPaths, ["/arrival.jpg"])
    }

    func test_watch_rewatch_saysRewatched() {
        let card = ShareCardContent.watch(entry(isRewatch: true), calendar: calendar, locale: locale)

        XCTAssertEqual(card.dateLine, "Rewatched March 3, 2026")
    }

    func test_watch_unknownDateAndNoRating_omitsBoth() {
        let card = ShareCardContent.watch(entry(isDateKnown: false), calendar: calendar, locale: locale)

        XCTAssertNil(card.dateLine)
        XCTAssertNil(card.scoreText)
        XCTAssertNil(card.reviewExcerpt)
    }

    func test_excerpt_longReview_cutsAtWordWithEllipsis() {
        let review = String(repeating: "word ", count: 100)

        let excerpt = ShareCardContent.excerpt(review)

        XCTAssertNotNil(excerpt)
        XCTAssertLessThanOrEqual(excerpt!.count, ShareCardContent.reviewLimit + 1)
        XCTAssertTrue(excerpt!.hasSuffix("word…"))
    }

    func test_excerpt_blankReview_isNil() {
        XCTAssertNil(ShareCardContent.excerpt(" \n "))
    }

    func test_list_takesFirstSixPostersAndCountsEveryTitle() {
        let list = LibraryList.system(.watchlist)
        let entries = (1...8).map { listEntry($0, list: list, poster: $0 == 2 ? nil : "/p\($0).jpg") }

        let card = ShareCardContent.list(list, entries: entries)

        XCTAssertEqual(card.kind, .list)
        XCTAssertEqual(card.title, list.displayName)
        XCTAssertEqual(card.subtitle, "8 titles")
        XCTAssertEqual(card.posterPaths, ["/p1.jpg", "/p3.jpg", "/p4.jpg", "/p5.jpg", "/p6.jpg", "/p7.jpg"])
    }

    func test_list_oneTitle_usesSingular() {
        let list = LibraryList.system(.watched)

        let card = ShareCardContent.list(list, entries: [listEntry(1, list: list, poster: nil)])

        XCTAssertEqual(card.subtitle, "1 title")
        XCTAssertEqual(card.posterPaths, [])
    }

    private func entry(
        score: Double? = nil,
        review: String? = nil,
        isRewatch: Bool = false,
        isDateKnown: Bool = true
    ) -> DiaryEntry {
        DiaryEntry(
            id: UUID(),
            subject: .movie(329865),
            title: "Arrival",
            releaseYear: 2016,
            posterPath: "/arrival.jpg",
            watchedOn: DiaryDay(year: 2026, month: 3, day: 3),
            score: score,
            review: review,
            isRewatch: isRewatch,
            loggedAt: Date(timeIntervalSince1970: 0),
            isDateKnown: isDateKnown
        )
    }

    private func listEntry(_ id: Int, list: LibraryList, poster: String?) -> ListEntry {
        let draft = ListItemDraft(
            id: id,
            kind: .movie,
            title: "Movie \(id)",
            imagePath: poster,
            releaseDate: nil,
            genreNames: [],
            voteAverage: 7,
            popularity: 10
        )
        return ListEntry(listID: list.id, draft: draft, addedAt: Date(timeIntervalSince1970: 0), position: id)
    }
}
