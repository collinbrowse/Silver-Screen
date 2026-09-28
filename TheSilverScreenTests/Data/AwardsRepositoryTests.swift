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

    func test_movieAwards_listsEachPrizeNewestFirst() async {
        let repository = AwardsRepository(catalog: Self.sampleCatalog)
        let rows = await repository.movieAwards(movieID: 238)
        XCTAssertEqual(rows.map(\.categoryLabel), ["Best Actor", "Best Picture"])
        XCTAssertEqual(rows.map(\.detailLine), ["1973", "1973"])
    }

    func test_movieAwards_keepsEachPrizeBodyWhenTheCategoryNameMatches() async {
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

        let rows = await repository.movieAwards(movieID: 1)

        XCTAssertEqual(rows.map(\.id), ["oscar-actor", "bafta-actor"])
        XCTAssertEqual(rows.map(\.family), [.academy, .bafta])
        XCTAssertEqual(rows[1].accessibilityName, "BAFTA for Best Actor, 2024")
    }

    func test_movieAwards_dropsOnlyTheNominationForACategoryThatWasWon() async {
        let murphy = AwardRecipient(name: "Cillian Murphy", wikidataID: "Q202589", imdbID: "nm0614165")
        let repository = AwardsRepository(catalog: AwardsCatalog(
            generatedAt: Date(timeIntervalSince1970: 1),
            credits: [
                Self.credit(
                    "actor-nom",
                    title: "Oppenheimer",
                    category: "Best Actor",
                    year: 2024,
                    won: false,
                    movieID: 872585,
                    recipients: [murphy]
                ),
                Self.credit(
                    "actor-win",
                    title: "Oppenheimer",
                    category: "Best Actor",
                    year: 2024,
                    won: true,
                    movieID: 872585,
                    recipients: [murphy]
                ),
                Self.credit(
                    "director-nom",
                    title: "Oppenheimer",
                    category: "Best Director",
                    year: 2024,
                    won: false,
                    movieID: 872585,
                    recipients: [AwardRecipient(name: "Christopher Nolan", wikidataID: "Q25191", imdbID: "nm0634240")]
                ),
            ]
        ))

        let rows = await repository.movieAwards(movieID: 872585)

        XCTAssertEqual(rows.map(\.id), ["actor-win", "director-nom"])
        XCTAssertEqual(rows.map(\.detailLine), [
            "Cillian Murphy · 2024",
            "Christopher Nolan · 2024",
        ])
        XCTAssertEqual(rows.map(\.categoryLabel), ["Best Actor", "Best Director nominee"])
        XCTAssertEqual(
            rows[0].accessibilityName,
            "Oscar for Best Actor, Cillian Murphy, 2024"
        )
    }

    func test_personAwards_listsPrizesGivenToThisPersonNewestFirst() async {
        let freeman = AwardRecipient(name: "Morgan Freeman", wikidataID: "Q48337", imdbID: "nm0000151")
        let repository = AwardsRepository(catalog: AwardsCatalog(
            generatedAt: Date(timeIntervalSince1970: 1),
            credits: [
                Self.credit(
                    "support-1995",
                    title: "The Shawshank Redemption",
                    category: "Best Supporting Actor",
                    year: 1995,
                    won: true,
                    movieID: 278,
                    recipients: [freeman]
                ),
                Self.credit(
                    "actor-1973",
                    title: "The Godfather",
                    category: "Best Actor",
                    year: 1973,
                    won: true,
                    movieID: 238,
                    recipients: [freeman]
                ),
                Self.credit(
                    "picture",
                    title: "The Shawshank Redemption",
                    category: "Best Picture",
                    year: 1995,
                    won: true,
                    movieID: 278
                ),
                Self.credit(
                    "other",
                    title: "Se7en",
                    category: "Best Actor",
                    year: 1996,
                    won: true,
                    movieID: 807,
                    recipients: [AwardRecipient(name: "Someone Else", wikidataID: "Q1", imdbID: "nm0000001")]
                ),
            ]
        ))

        let awards = await repository.personAwards(imdbID: "nm0000151")

        XCTAssertEqual(awards.map(\.workTitle), ["The Shawshank Redemption", "The Godfather"])
        XCTAssertEqual(awards.map(\.categoryLabel), ["Best Supporting Actor", "Best Actor"])
        XCTAssertEqual(awards.first?.route, .movieDetail(id: 278))
    }

    func test_personAwards_prefersTheWinOverTheSameNomination() async {
        let freeman = AwardRecipient(name: "Morgan Freeman", wikidataID: "Q48337", imdbID: "nm0000151")
        let repository = AwardsRepository(catalog: AwardsCatalog(
            generatedAt: Date(timeIntervalSince1970: 1),
            credits: [
                Self.credit(
                    "win",
                    title: "The Shawshank Redemption",
                    category: "Best Supporting Actor",
                    year: 1995,
                    won: true,
                    movieID: 278,
                    recipients: [freeman]
                ),
                Self.credit(
                    "nom",
                    title: "The Shawshank Redemption",
                    category: "Best Supporting Actor",
                    year: 1995,
                    won: false,
                    movieID: 278,
                    recipients: [freeman]
                ),
                Self.credit(
                    "other-nom",
                    title: "Se7en",
                    category: "Best Supporting Actor",
                    year: 1996,
                    won: false,
                    movieID: 807,
                    recipients: [freeman]
                ),
            ]
        ))

        let awards = await repository.personAwards(imdbID: "NM0000151")

        XCTAssertEqual(awards.map(\.key), ["other-nom", "win"])
        XCTAssertEqual(awards.map(\.categoryLabel), ["Best Supporting Actor nominee", "Best Supporting Actor"])
    }

    func test_personAwards_returnsNothingWithoutAnIMDbId() async {
        let repository = AwardsRepository(catalog: AwardsCatalog(
            generatedAt: Date(timeIntervalSince1970: 1),
            credits: [
                Self.credit(
                    "win",
                    title: "Film",
                    category: "Best Actor",
                    year: 2020,
                    won: true,
                    movieID: 1,
                    recipients: [AwardRecipient(name: "Morgan Freeman", wikidataID: "Q48337", imdbID: "nm0000151")]
                ),
            ]
        ))

        let missing = await repository.personAwards(imdbID: nil)
        let blank = await repository.personAwards(imdbID: "  ")

        XCTAssertEqual(missing, [])
        XCTAssertEqual(blank, [])
    }

    func test_decode_readsRecipientsAndOmitsAnEmptyList() throws {
        let json = """
        {
          "generatedAt": "2024-03-10T10:00:00Z",
          "credits": [{
            "key": "support",
            "family": "academy",
            "category": "Best Supporting Actor",
            "categoryID": "Q106291",
            "won": true,
            "year": 1995,
            "title": "The Shawshank Redemption",
            "work": {"kind": "movie", "movieID": 278},
            "recipients": [{"name": "Morgan Freeman", "wikidataID": "Q48337", "imdbID": "nm0000151"}]
          }]
        }
        """
        let catalog = try AwardsCatalog.decode(from: Data(json.utf8))
        XCTAssertEqual(catalog.credits.first?.recipients.first?.imdbID, "nm0000151")

        let encoded = String(
            decoding: try AwardsCatalog(
                generatedAt: Date(timeIntervalSince1970: 0),
                credits: [
                    Self.credit("plain", title: "Film", category: "Best Picture", year: 2020, won: true, movieID: 1),
                ]
            ).encoded(),
            as: UTF8.self
        )
        XCTAssertFalse(encoded.contains("recipients"))
    }

    func test_movieAwards_listsEveryNominationWhenThereAreNoWins() async {
        let repository = AwardsRepository(catalog: Self.sampleCatalog)
        let rows = await repository.movieAwards(movieID: 278)
        XCTAssertEqual(rows.map(\.categoryLabel), [
            "Best Picture nominee",
            "Best Actor nominee",
            "Best Director nominee",
            "Best Adapted Screenplay nominee",
        ])
        XCTAssertEqual(rows.map(\.detailLine), ["1995", "1994", "1993", "1992"])
        XCTAssertEqual(rows[0].accessibilityName, "Oscar nominee for Best Picture, 1995")
    }

    func test_movieAwards_unknownMovieIsEmpty() async {
        let repository = AwardsRepository(catalog: Self.sampleCatalog)
        let rows = await repository.movieAwards(movieID: 999)
        XCTAssertEqual(rows, [])
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
        family: AwardFamily = .academy,
        recipients: [AwardRecipient] = []
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
            work: movieID.map { AwardWork(kind: .movie, movieID: $0) },
            recipients: recipients
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

