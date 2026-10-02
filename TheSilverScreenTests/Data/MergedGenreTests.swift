//
//  MergedGenreTests.swift
//  TheSilverScreenTests
//

import XCTest
@testable import TheSilverScreen

final class MergedGenreTests: XCTestCase {

    private let locale = Locale(identifier: "en_US")
    private let today = TestMovies.date("2024-06-15")

    func test_searchShelf_listsElevenGenresAlphabetically() {
        let titles = MergedGenre.searchShelf.map(\.title)
        XCTAssertEqual(titles, [
            "Action & Adventure",
            "Animation",
            "Comedy",
            "Crime",
            "Documentary",
            "Drama",
            "Family",
            "Mystery",
            "Sci-Fi & Fantasy",
            "War & Politics",
            "Western",
        ])
    }

    func test_family_includesKidsOnTV() {
        XCTAssertEqual(MergedGenre.family.tvGenreIDs, [10751, 10762])
    }

    func test_catalog_hasNoHorrorCase() {
        XCTAssertFalse(MergedGenre.allCases.contains(where: { $0.title == "Horror" }))
    }

    func test_discoverQuery_withGenreIDs_joinsWithPipe() {
        let items = DiscoverQuery.items(
            kind: .movie,
            sort: .popular,
            window: .all,
            page: 1,
            locale: locale,
            today: today,
            genreIDs: [28, 12]
        )
        XCTAssertTrue(items.contains(URLQueryItem(name: "with_genres", value: "28|12")))
    }

    func test_discoverQuery_withoutGenreIDs_omitsWithGenres() {
        let items = DiscoverQuery.items(
            kind: .tv,
            sort: .popular,
            window: .all,
            page: 1,
            locale: locale,
            today: today
        )
        XCTAssertFalse(items.contains { $0.name == "with_genres" })
    }
}
