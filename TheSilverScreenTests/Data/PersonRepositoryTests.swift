//
//  PersonRepositoryTests.swift
//  TheSilverScreenTests
//

import XCTest
@testable import TheSilverScreen

final class PersonRepositoryTests: XCTestCase {

    func test_personDetail_mapsBioImagesCreditsAndImdb() async throws {
        let client = FakeHTTPClient(stub: .success(TMDBFixtures.personDetailMorganFreeman))
        let people = PersonRepository.test(client: client)

        let detail = try await people.personDetail(id: 1922)

        XCTAssertEqual(detail.id, 1922)
        XCTAssertEqual(detail.name, "Morgan Freeman")
        XCTAssertTrue(detail.biography.contains("distinctive voice"))
        XCTAssertEqual(detail.imdbID, "nm0000151")
        XCTAssertNil(detail.deathday)
        XCTAssertEqual(detail.placeOfBirth, "Memphis, Tennessee, USA")
        XCTAssertEqual(detail.images.count, 2)
        XCTAssertEqual(detail.images.first?.filePath, "/profile1.jpg")

        XCTAssertEqual(detail.castCredits.count, 2)
        XCTAssertEqual(detail.castCredits[0].title, "The Shawshank Redemption")
        XCTAssertEqual(detail.castCredits[0].mediaType, .movie)
        XCTAssertEqual(detail.castCredits[1].mediaType, .tv)
        XCTAssertEqual(detail.castCredits[1].title, "Breaking Bad")

        XCTAssertEqual(detail.crewCredits.count, 1)
        XCTAssertEqual(detail.crewCredits[0].title, "Fight Club")
        XCTAssertTrue(detail.crewCredits[0].roleLabel.contains("Executive Producer"))
        XCTAssertTrue(detail.crewCredits[0].roleLabel.contains("Producer"))
    }

    func test_personDetail_sparse_hidesOptionalFields() async throws {
        let client = FakeHTTPClient(stub: .success(TMDBFixtures.personDetailSparse))
        let people = PersonRepository.test(client: client)

        let detail = try await people.personDetail(id: 1)

        XCTAssertEqual(detail.name, "Unknown Actor")
        XCTAssertTrue(detail.biography.isEmpty)
        XCTAssertNil(detail.birthday)
        XCTAssertNil(detail.deathday)
        XCTAssertNil(detail.placeOfBirth)
        XCTAssertNil(detail.imdbID)
        XCTAssertTrue(detail.images.isEmpty)
        XCTAssertTrue(detail.castCredits.isEmpty)
        XCTAssertTrue(detail.crewCredits.isEmpty)
    }

    func test_personDetail_whenOffline_throwsOffline() async {
        let client = FakeHTTPClient(stub: .failure(URLError(.notConnectedToInternet)))
        let people = PersonRepository.test(client: client)

        do {
            _ = try await people.personDetail(id: 1)
            XCTFail("Expected offline error")
        } catch let error as AppError {
            XCTAssertEqual(error, .offline)
        } catch {
            XCTFail("Unexpected error \(error)")
        }
    }

    func test_mapCrewCredits_dedupesJobsByMedia() {
        let items = [
            PersonCombinedCreditDTO(
                id: 1,
                mediaType: "movie",
                title: "Film",
                name: nil,
                posterPath: nil,
                releaseDate: "2000-01-01",
                firstAirDate: nil,
                genreIDs: [18],
                character: nil,
                job: "Director",
                popularity: 10,
                voteAverage: nil,
                order: nil,
                voteCount: nil,
                episodeCount: nil
            ),
            PersonCombinedCreditDTO(
                id: 1,
                mediaType: "movie",
                title: "Film",
                name: nil,
                posterPath: nil,
                releaseDate: "2000-01-01",
                firstAirDate: nil,
                genreIDs: [18],
                character: nil,
                job: "Writer",
                popularity: 12,
                voteAverage: nil,
                order: nil,
                voteCount: nil,
                episodeCount: nil
            ),
        ]

        let credits = PersonRepository.mapCrewCredits(items, logger: SilentLogger())

        XCTAssertEqual(credits.count, 1)
        XCTAssertEqual(credits[0].popularity, 12)
        XCTAssertEqual(credits[0].roleLabel, "Director, Writer")
    }

    func test_mapCastCredits_ranksFamousRoleAbovePopularGuestSpot() throws {
        let credits = try castCredits(
            """
            [
              {
                "id": 59941,
                "media_type": "tv",
                "name": "The Tonight Show Starring Jimmy Fallon",
                "character": "Self - Guest",
                "popularity": 495.4,
                "vote_count": 390,
                "episode_count": 1
              },
              {
                "id": 16869,
                "media_type": "movie",
                "title": "Inglourious Basterds",
                "character": "COL. Hans Landa",
                "popularity": 30.1,
                "vote_count": 24838,
                "order": 2
              }
            ]
            """,
            personName: "Christoph Waltz"
        )

        XCTAssertEqual(credits.map(\.title), [
            "Inglourious Basterds",
            "The Tonight Show Starring Jimmy Fallon",
        ])
    }

    func test_mapCastCredits_ranksSeriesRoleAboveOneEpisodeOnAHotterShow() throws {
        let credits = try castCredits(
            """
            [
              {
                "id": 1,
                "media_type": "tv",
                "name": "Hot Guest Spot",
                "character": "Doctor",
                "popularity": 900,
                "vote_count": 20000,
                "episode_count": 1
              },
              {
                "id": 2,
                "media_type": "tv",
                "name": "The Series",
                "character": "Lead",
                "popularity": 20,
                "vote_count": 8000,
                "episode_count": 40
              }
            ]
            """
        )

        XCTAssertEqual(credits.map(\.title), ["The Series", "Hot Guest Spot"])
    }

    func test_mapCastCredits_ranksLeadAboveDeepBilledCameo() throws {
        let credits = try castCredits(
            """
            [
              {
                "id": 1,
                "media_type": "movie",
                "title": "Blockbuster",
                "character": "Extra",
                "popularity": 200,
                "vote_count": 30000,
                "order": 24
              },
              {
                "id": 2,
                "media_type": "movie",
                "title": "Famous Lead",
                "character": "Lead",
                "popularity": 15,
                "vote_count": 8000,
                "order": 0
              }
            ]
            """
        )

        XCTAssertEqual(credits.map(\.title), ["Famous Lead", "Blockbuster"])
    }

    func test_mapCastCredits_whenVoteCountMissing_ordersByPopularity() throws {
        let credits = try castCredits(
            """
            [
              {"id": 1, "media_type": "movie", "title": "Quiet", "character": "A", "popularity": 5},
              {"id": 2, "media_type": "movie", "title": "Loud", "character": "B", "popularity": 50}
            ]
            """
        )

        XCTAssertEqual(credits.map(\.title), ["Loud", "Quiet"])
    }

    func test_mapCastCredits_ranksLongRunningHostCreditAboveOneOffSelfCameo() throws {
        let credits = try castCredits(
            """
            [
              {
                "id": 1,
                "media_type": "tv",
                "name": "The Boys",
                "character": "Jimmy Fallon (uncredited)",
                "popularity": 136,
                "vote_count": 13472,
                "episode_count": 1
              },
              {
                "id": 2,
                "media_type": "tv",
                "name": "The Tonight Show Starring Jimmy Fallon",
                "character": "Self - Host",
                "popularity": 100,
                "vote_count": 390,
                "episode_count": 2421
              }
            ]
            """,
            personName: "Jimmy Fallon"
        )

        XCTAssertEqual(credits.map(\.title), [
            "The Tonight Show Starring Jimmy Fallon",
            "The Boys",
        ])
    }

    func test_mapCrewCredits_ranksDirectedFilmAboveOneEpisodeOnAPopularShow() throws {
        let data = Data(
            """
            [
              {
                "id": 1,
                "media_type": "tv",
                "name": "Popular Series",
                "job": "Director",
                "popularity": 900,
                "vote_count": 20000,
                "episode_count": 1
              },
              {
                "id": 2,
                "media_type": "movie",
                "title": "Directed Film",
                "job": "Director",
                "popularity": 12,
                "vote_count": 9000
              }
            ]
            """.utf8
        )
        let items = try JSONDecoder().decode([PersonCombinedCreditDTO].self, from: data)

        let credits = PersonRepository.mapCrewCredits(items, logger: SilentLogger())

        XCTAssertEqual(credits.map(\.title), ["Directed Film", "Popular Series"])
    }

    private func castCredits(_ json: String, personName: String = "") throws -> [PersonCredit] {
        let items = try JSONDecoder().decode([PersonCombinedCreditDTO].self, from: Data(json.utf8))
        return PersonRepository.mapCastCredits(items, logger: SilentLogger(), personName: personName)
    }

    func test_tvGenreCatalog_mapsKnownIDs() {
        XCTAssertEqual(TVGenreCatalog.names(for: [18, 80, 99999]), ["Drama", "Crime"])
    }
}
