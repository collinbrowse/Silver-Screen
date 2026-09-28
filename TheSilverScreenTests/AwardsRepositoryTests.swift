//
//  AwardsRepositoryTests.swift
//  TheSilverScreenTests
//

import XCTest
@testable import TheSilverScreen

final class AwardsRepositoryTests: XCTestCase {

    func test_decode_readsACreditFixture() throws {
        let catalog = try AwardsCatalog.decode(from: Data(Self.fixtureJSON.utf8))
        XCTAssertEqual(catalog.credits.map(\.title), ["The Godfather", "Oppenheimer"])
        XCTAssertEqual(catalog.credits[0].work?.movieID, 238)
        XCTAssertEqual(catalog.credits[1].category, "Best Picture")
        XCTAssertNil(catalog.credits[1].work)
    }

    func test_creditPage_filtersBestPictureWinnersNewestFirst() async {
        let repository = AwardsRepository(catalog: Self.sampleCatalog)
        let page = await repository.creditPage(
            request: AwardTitleRequest(family: .academy, category: "Best Picture"),
            winners: true,
            page: 1
        )
        XCTAssertEqual(page.credits.map(\.title), ["Oppenheimer", "The Godfather"])
        XCTAssertTrue(page.credits.allSatisfy(\.won))
        XCTAssertFalse(page.hasMore)
    }

    func test_categories_hidesAListTooShortToBeAHistory() async {
        let enough = (0..<AwardsRepository.minimumListedCredits).map { index in
            Self.credit(
                "picture-\(index)",
                title: "Film \(index)",
                category: "Best Picture",
                year: 2000 + index,
                won: true,
                movieID: index + 1
            )
        }
        let thin = (0..<(AwardsRepository.minimumListedCredits - 1)).map { index in
            Self.credit(
                "drama-\(index)",
                title: "Show \(index)",
                category: "Outstanding Drama Series",
                year: 2000 + index,
                won: true,
                movieID: 100 + index
            )
        }
        let repository = AwardsRepository(catalog: AwardsCatalog(
            generatedAt: Date(timeIntervalSince1970: 1),
            credits: enough + thin
        ))

        let names = await repository.categories(in: .academy).map(\.name)

        XCTAssertEqual(names, ["Best Picture"])
    }

    func test_pillLabels_prefersEveryWinOverNominations() async {
        let repository = AwardsRepository(catalog: Self.sampleCatalog)
        let labels = await repository.pillLabels(movieID: 238)
        XCTAssertEqual(labels, [
            AwardPill(family: .academy, title: "Best Actor"),
            AwardPill(family: .academy, title: "Best Picture"),
        ])
    }

    func test_pillLabels_keepsEachPrizeBodyWhenTheCategoryNameMatches() async {
        let repository = AwardsRepository(catalog: AwardsCatalog(
            generatedAt: Date(timeIntervalSince1970: 1),
            credits: [
                Self.credit(
                    "oscar-actor",
                    title: "Film",
                    category: "Best Actor",
                    year: 2024,
                    won: true,
                    movieID: 1,
                    family: .academy
                ),
                Self.credit(
                    "bafta-actor",
                    title: "Film",
                    category: "Best Actor",
                    year: 2024,
                    won: true,
                    movieID: 1,
                    family: .bafta
                ),
            ]
        ))

        let labels = await repository.pillLabels(movieID: 1)

        XCTAssertEqual(labels, [
            AwardPill(family: .academy, title: "Best Actor"),
            AwardPill(family: .bafta, title: "Best Actor"),
        ])
    }

    func test_pill_namesThePrizeBodyForVoiceOver() {
        XCTAssertEqual(
            AwardPill(family: .academy, title: "Best Original Music").accessibilityName,
            "Oscar for Best Original Music"
        )
        XCTAssertEqual(
            AwardPill(family: .bafta, title: "Best Film nominee").accessibilityName,
            "BAFTA nominee for Best Film"
        )
        XCTAssertEqual(
            AwardPill(family: .emmy, title: "Outstanding Drama Series").accessibilityName,
            "Emmy for Outstanding Drama Series"
        )
    }

    func test_pillLabels_capsNominationsAtThreeWhenThereAreNoWins() async {
        let repository = AwardsRepository(catalog: Self.sampleCatalog)
        let labels = await repository.pillLabels(movieID: 278)
        XCTAssertEqual(
            labels,
            [
                AwardPill(family: .academy, title: "Best Picture nominee"),
                AwardPill(family: .academy, title: "Best Actor nominee"),
                AwardPill(family: .academy, title: "Best Director nominee"),
            ]
        )
    }

    func test_pillLabels_unknownMovieIsEmpty() async {
        let repository = AwardsRepository(catalog: Self.sampleCatalog)
        let labels = await repository.pillLabels(movieID: 999)
        XCTAssertEqual(labels, [])
    }

    func test_prepare_prefersNewerCachedFile() async throws {
        let fixture = try makeFiles(
            bundle: catalog(title: "Bundle Film", generatedAt: "2020-01-01T00:00:00Z"),
            cache: catalog(title: "Cached Film", generatedAt: "2024-01-01T00:00:00Z"),
            stamp: Date()
        )
        defer { fixture.cleanup() }
        let client = RecordingHTTPClient(stub: .failure(URLError(.notConnectedToInternet)))
        let repository = AwardsRepository(
            client: client,
            bundleURL: fixture.bundleURL,
            cacheURL: fixture.cacheURL,
            logger: SilentLogger(),
            now: { Date() }
        )

        await repository.prepare()

        let page = await repository.creditPage(
            request: AwardTitleRequest(family: .academy, category: "Best Picture"),
            winners: true,
            page: 1
        )
        XCTAssertEqual(page.credits.map(\.title), ["Cached Film"])
        let count = await client.requestCount
        XCTAssertEqual(count, 0)
    }

    func test_prepare_keepsBundleWhenDownloadFails() async throws {
        let fixture = try makeFiles(
            bundle: catalog(title: "Bundle Film", generatedAt: "2020-01-01T00:00:00Z"),
            cache: nil,
            stamp: nil
        )
        defer { fixture.cleanup() }
        let repository = AwardsRepository(
            client: FakeHTTPClient(result: .failure(URLError(.notConnectedToInternet))),
            bundleURL: fixture.bundleURL,
            cacheURL: fixture.cacheURL,
            logger: SilentLogger(),
            now: { Date() }
        )

        await repository.prepare()

        let page = await repository.creditPage(
            request: AwardTitleRequest(family: .academy, category: "Best Picture"),
            winners: true,
            page: 1
        )
        XCTAssertEqual(page.credits.map(\.title), ["Bundle Film"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.cacheURL.path))
    }

    private static let fixtureJSON = """
    {
      "credits": [
        {
          "category": "Best Picture",
          "categoryID": "Q102427",
          "family": "academy",
          "key": "godfather",
          "title": "The Godfather",
          "won": true,
          "work": {"kind": "movie", "movieID": 238},
          "year": 1973
        },
        {
          "category": "Best Picture",
          "categoryID": "Q102427",
          "family": "academy",
          "imdbID": "tt15398776",
          "key": "oppenheimer-unresolved",
          "title": "Oppenheimer",
          "wikidataID": "Q108669",
          "won": true,
          "year": 2024
        }
      ],
      "generatedAt": "2024-03-10T10:00:00Z"
    }
    """

    private static let sampleCatalog = AwardsCatalog(
        generatedAt: Date(timeIntervalSince1970: 1_700_000_000),
        credits: [
            credit("pic-2024", title: "Oppenheimer", category: "Best Picture", year: 2024, won: true, movieID: 872585),
            credit("pic-1973", title: "The Godfather", category: "Best Picture", year: 1973, won: true, movieID: 238),
            credit("actor-1973", title: "The Godfather", category: "Best Actor", year: 1973, won: true, movieID: 238),
            credit("nom-picture", title: "The Shawshank Redemption", category: "Best Picture", year: 1995, won: false, movieID: 278),
            credit("nom-actor", title: "The Shawshank Redemption", category: "Best Actor", year: 1994, won: false, movieID: 278),
            credit("nom-director", title: "The Shawshank Redemption", category: "Best Director", year: 1993, won: false, movieID: 278),
            credit("nom-screen", title: "The Shawshank Redemption", category: "Best Adapted Screenplay", year: 1992, won: false, movieID: 278),
            credit("other-family", title: "Parasite", category: "Best Film", year: 2020, won: true, movieID: 496243, family: .bafta),
            credit("unresolved", title: "Missing", category: "Best Picture", year: 2021, won: true, movieID: nil),
        ]
    )

    private static func credit(
        _ key: String,
        title: String,
        category: String,
        year: Int,
        won: Bool,
        movieID: Int?,
        family: AwardFamily = .academy
    ) -> AwardCredit {
        AwardCredit(
            key: key,
            family: family,
            category: category,
            categoryID: category,
            won: won,
            year: year,
            title: title,
            imdbID: nil,
            wikidataID: nil,
            work: movieID.map { AwardWork(kind: .movie, movieID: $0) }
        )
    }

    private func catalog(title: String, generatedAt: String) -> AwardsCatalog {
        AwardsCatalog(
            generatedAt: AwardJSON.parseDate(generatedAt)!,
            credits: [
                AwardCredit(
                    key: title,
                    family: .academy,
                    category: "Best Picture",
                    categoryID: "Q102427",
                    won: true,
                    year: 2020,
                    title: title,
                    imdbID: nil,
                    wikidataID: nil,
                    work: AwardWork(kind: .movie, movieID: 1)
                ),
            ]
        )
    }

    private func makeFiles(
        bundle: AwardsCatalog,
        cache: AwardsCatalog?,
        stamp: Date?
    ) throws -> (bundleURL: URL, cacheURL: URL, cleanup: () -> Void) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let bundleURL = directory.appendingPathComponent("AwardsCatalog.json")
        let cacheURL = directory.appendingPathComponent("Cache.json")
        try bundle.encoded().write(to: bundleURL)
        if let cache {
            try cache.encoded().write(to: cacheURL)
        }
        if let stamp {
            let stampURL = directory.appendingPathComponent("AwardsCatalog.stamp.json")
            let payload = try AwardJSON.encoder().encode(["lastAttempt": AwardJSON.formatDate(stamp)])
            try payload.write(to: stampURL)
        }
        return (bundleURL, cacheURL, { try? FileManager.default.removeItem(at: directory) })
    }
}

