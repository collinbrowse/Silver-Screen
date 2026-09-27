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
                voteAverage: nil
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
                voteAverage: nil
            ),
        ]

        let credits = PersonRepository.mapCrewCredits(items, logger: SilentLogger())

        XCTAssertEqual(credits.count, 1)
        XCTAssertEqual(credits[0].popularity, 12)
        XCTAssertEqual(credits[0].roleLabel, "Director, Writer")
    }

    func test_tvGenreCatalog_mapsKnownIDs() {
        XCTAssertEqual(TVGenreCatalog.names(for: [18, 80, 99999]), ["Drama", "Crime"])
    }
}
