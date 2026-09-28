//
//  MovieRepositoryTests.swift
//  TheSilverScreenTests
//

import XCTest
@testable import TheSilverScreen

final class MovieRepositoryTests: XCTestCase {

    func test_topMovies_mapsFixtureToDomainMovies() async throws {
        let client = FakeHTTPClient(stub: .success(TMDBFixtures.topMoviesPage1, status: 200))
        let repository = MovieRepository.test(client: client)

        let page = try await repository.topMovies(page: 1)

        XCTAssertEqual(page.movies.count, 2)
        XCTAssertEqual(page.movies[0].id, 278)
        XCTAssertEqual(page.movies[0].title, "The Shawshank Redemption")
        XCTAssertEqual(page.movies[0].posterPath, "/poster.jpg")
        XCTAssertEqual(page.movies[0].releaseDate, TestMovies.date("1994-09-23"))
        XCTAssertEqual(page.movies[0].voteAverage, 8.7, accuracy: 0.01)
        XCTAssertEqual(page.movies[0].genreIDs, [18, 80])
        XCTAssertTrue(page.hasMore)
        XCTAssertEqual(page.page, 1)
    }

    func test_topMovies_emptyReleaseDate_mapsToNilAndKeepsMovie() async throws {
        let client = FakeHTTPClient(stub: .success(TMDBFixtures.topMoviesWithEmptyReleaseDate))
        let repository = MovieRepository.test(client: client)

        let page = try await repository.topMovies(page: 1)

        XCTAssertEqual(page.movies.count, 1)
        XCTAssertNil(page.movies[0].releaseDate)
        XCTAssertEqual(page.movies[0].title, "Untitled")
        XCTAssertFalse(page.hasMore)
    }

    func test_topMovies_whenOffline_throwsOffline() async {
        let client = FakeHTTPClient(result: .failure(URLError(.notConnectedToInternet)))
        let repository = MovieRepository.test(client: client)

        do {
            _ = try await repository.topMovies(page: 1)
            XCTFail("Expected offline error")
        } catch let error as AppError {
            XCTAssertEqual(error, .offline)
        } catch {
            XCTFail("Expected AppError, got \(error)")
        }
    }

    func test_topMovies_whenUnauthorized_throwsUnauthorized() async {
        let client = FakeHTTPClient(stub: .success(Data(), status: 401))
        let repository = MovieRepository.test(client: client)

        do {
            _ = try await repository.topMovies(page: 1)
            XCTFail("Expected unauthorized")
        } catch let error as AppError {
            XCTAssertEqual(error, .unauthorized)
        } catch {
            XCTFail("Expected AppError, got \(error)")
        }
    }

    func test_topMovies_whenUnauthorized_doesNotRetry() async {
        let client = SequencingHTTPClient(stubs: [
            .success(Data(), status: 401),
            .success(TMDBFixtures.topMoviesPage1),
        ])
        let repository = MovieRepository.test(client: client)

        do {
            _ = try await repository.topMovies(page: 1)
            XCTFail("Expected unauthorized")
        } catch let error as AppError {
            XCTAssertEqual(error, .unauthorized)
        } catch {
            XCTFail("Expected AppError, got \(error)")
        }

        let count = await client.requestCount
        XCTAssertEqual(count, 1)
    }

    func test_topMovies_whenServerError_throwsServerStatus() async {
        let client = FakeHTTPClient(stub: .success(Data(), status: 500))
        let repository = MovieRepository.test(client: client)

        do {
            _ = try await repository.topMovies(page: 1)
            XCTFail("Expected server error")
        } catch let error as AppError {
            XCTAssertEqual(error, .server(status: 500))
        } catch {
            XCTFail("Expected AppError, got \(error)")
        }
    }

    func test_topMovies_whenServerErrorThenSuccess_retriesAndReturns() async throws {
        let client = SequencingHTTPClient(stubs: [
            .success(Data(), status: 500),
            .success(Data(), status: 503),
            .success(TMDBFixtures.topMoviesPage1),
        ])
        let repository = MovieRepository.test(client: client)

        let page = try await repository.topMovies(page: 1)

        XCTAssertEqual(page.movies.count, 2)
        let count = await client.requestCount
        XCTAssertEqual(count, 3)
    }

    func test_topMovies_whenOffline_failsFastWithoutRetrying() async {
        // Offline must not be auto-retried: retrying a request with no connectivity only delays the
        // offline message. Even though a success stub follows, the repository must stop at the first
        // offline failure and surface .offline. Regression for the "spinner forever" report.
        let client = SequencingHTTPClient(stubs: [
            .failure(URLError(.notConnectedToInternet)),
            .success(TMDBFixtures.topMoviesPage1),
        ])
        let repository = MovieRepository.test(client: client)

        do {
            _ = try await repository.topMovies(page: 1)
            XCTFail("Expected offline error")
        } catch let error as AppError {
            XCTAssertEqual(error, .offline)
        } catch {
            XCTFail("Expected AppError, got \(error)")
        }

        let count = await client.requestCount
        XCTAssertEqual(count, 1)
    }

    func test_topMovies_whenGarbageJSON_throwsDecoding() async {
        let client = FakeHTTPClient(stub: .success(Data("not-json".utf8)))
        let repository = MovieRepository.test(client: client)

        do {
            _ = try await repository.topMovies(page: 1)
            XCTFail("Expected decoding error")
        } catch let error as AppError {
            XCTAssertEqual(error, .decoding)
        } catch {
            XCTFail("Expected AppError, got \(error)")
        }
    }

    func test_topMovies_skipsMalformedElement_keepsValidOnes() async throws {
        let json = Data(
            """
            {
              "page": 1,
              "results": [
                {
                  "id": 1,
                  "title": "Good",
                  "poster_path": null,
                  "release_date": "2000-01-01",
                  "vote_average": 7.5
                },
                {
                  "id": "bad",
                  "title": 12
                }
              ],
              "total_pages": 1,
              "total_results": 2
            }
            """.utf8
        )
        let client = FakeHTTPClient(stub: .success(json))
        let repository = MovieRepository.test(client: client)

        let page = try await repository.topMovies(page: 1)

        XCTAssertEqual(page.movies.count, 1)
        XCTAssertEqual(page.movies[0].title, "Good")
    }

    func test_movieDetail_requestsApiKeyAndMapsFields() async throws {
        let client = RecordingHTTPClient(stub: .success(TMDBFixtures.movieDetailShawshank))
        let repository = MovieRepository.test(client: client, apiKey: "test-key")

        let detail = try await repository.movieDetail(id: 278)

        XCTAssertEqual(detail.id, 278)
        XCTAssertEqual(detail.title, "The Shawshank Redemption")
        XCTAssertEqual(detail.overview, "Framed in the 1940s for a double murder.")
        XCTAssertEqual(detail.posterPath, "/poster.jpg")
        XCTAssertEqual(detail.releaseDate, TestMovies.date("1994-09-23"))
        XCTAssertEqual(detail.voteAverage, 8.7, accuracy: 0.01)
        XCTAssertEqual(detail.budget, 25_000_000)
        XCTAssertEqual(detail.revenue, 28_341_469)
        XCTAssertEqual(detail.genres.map(\.name), ["Drama", "Crime"])

        let path = await client.lastPath
        XCTAssertEqual(path, "/3/movie/278")
        let url = await client.lastURL
        let items = URLComponents(url: url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
        XCTAssertTrue(items.contains(URLQueryItem(name: "api_key", value: "test-key")))
        XCTAssertTrue(items.contains(URLQueryItem(name: "language", value: "en-US")))
        XCTAssertTrue(items.contains(URLQueryItem(name: "append_to_response", value: "credits,images,similar,videos")))
        XCTAssertTrue(detail.trailers.isEmpty)
        XCTAssertTrue(items.contains(URLQueryItem(name: "include_image_language", value: "en,null")))
        let authorization = await client.lastAuthorizationHeader
        XCTAssertNil(authorization)

        XCTAssertEqual(detail.images.map(\.filePath), ["/backdrop-a.jpg", "/backdrop-b.jpg"])
        XCTAssertEqual(detail.cast.map(\.name), ["Tim Robbins", "Morgan Freeman"])
        XCTAssertEqual(detail.crew.filter { $0.job == "Director" }.map(\.name), ["Frank Darabont"])
        XCTAssertEqual(detail.similar.map(\.id), [311])
        XCTAssertNil(detail.collection)
    }

    func test_creditedDirectorsAndWriters_dedupesDirectorAndScreenplay() {
        let crew = [
            CrewMember(id: "1", personID: 4027, name: "Frank Darabont", job: "Director", department: "Directing", profilePath: nil),
            CrewMember(id: "2", personID: 4027, name: "Frank Darabont", job: "Screenplay", department: "Writing", profilePath: nil),
            CrewMember(id: "3", personID: 9, name: "Cam", job: "Director of Photography", department: "Camera", profilePath: nil),
        ]
        let people = MovieRepository.creditedDirectorsAndWriters(from: crew)
        XCTAssertEqual(people.count, 1)
        XCTAssertEqual(people[0].roles, ["Director", "Screenplay"])
    }

    func test_creditedDirectorsAndWriters_keepsWriterJobsAndDropsAssistants() {
        let crew = [
            CrewMember(id: "1", personID: 1, name: "Ada", job: "Story", department: "Writing", profilePath: nil),
            CrewMember(id: "2", personID: 2, name: "Bea", job: "Script Coordinator", department: "Writing", profilePath: nil),
            CrewMember(id: "3", personID: 3, name: "Cam", job: "Director", department: "Directing", profilePath: nil),
        ]
        let people = MovieRepository.creditedDirectorsAndWriters(from: crew)
        XCTAssertEqual(people.map(\.name), ["Cam", "Ada"])
        XCTAssertEqual(people[1].roles, ["Story"])
    }

    func test_collection_mapsParts() async throws {
        let client = FakeHTTPClient(stub: .success(TMDBFixtures.collectionGodfather))
        let repository = MovieRepository.test(client: client)
        let collection = try await repository.collection(id: 230)
        XCTAssertEqual(collection.name, "The Godfather Collection")
        XCTAssertEqual(collection.overview, "The Corleone family saga.")
        XCTAssertEqual(collection.posterPath, "/collection.jpg")
        XCTAssertEqual(collection.parts.map(\.id), [238, 240])
    }

    func test_movieReviews_mapsAuthorAndFractionalDate() async throws {
        let client = FakeHTTPClient(stub: .success(TMDBFixtures.movieReviewsPage1))
        let repository = MovieRepository.test(client: client)
        let page = try await repository.movieReviews(id: 278, page: 1)
        XCTAssertEqual(page.reviews.count, 1)
        XCTAssertEqual(page.reviews[0].username, "alice_reviews")
        XCTAssertNotNil(page.reviews[0].updatedAt)
        XCTAssertTrue(page.hasMore)
    }

    func test_imageURL_selectsBackdropAndProfileTokens() {
        let backdrop = ImageLoader.imageURL(
            path: "/b.jpg",
            kind: .backdrop,
            targetWidthPoints: 400,
            scale: 3
        )
        XCTAssertTrue(backdrop?.absoluteString.contains("/w1280/") == true)

        let profile = ImageLoader.imageURL(
            path: "p.jpg",
            kind: .profile,
            targetWidthPoints: 140,
            scale: 3
        )
        XCTAssertTrue(profile?.absoluteString.contains("/h632/") == true)
    }

    func test_movieDetail_emptyReleaseDateAndZeroMoney_mapsCleanly() async throws {
        let client = FakeHTTPClient(stub: .success(TMDBFixtures.movieDetailSparse))
        let repository = MovieRepository.test(client: client)

        let detail = try await repository.movieDetail(id: 999)

        XCTAssertNil(detail.releaseDate)
        XCTAssertNil(detail.posterPath)
        XCTAssertEqual(detail.budget, 0)
        XCTAssertEqual(detail.revenue, 0)
        XCTAssertTrue(detail.genres.isEmpty)
        XCTAssertEqual(detail.overview, "")
    }

    func test_movieDetail_whenOffline_throwsOffline() async {
        let client = FakeHTTPClient(result: .failure(URLError(.notConnectedToInternet)))
        let repository = MovieRepository.test(client: client)

        do {
            _ = try await repository.movieDetail(id: 278)
            XCTFail("Expected offline error")
        } catch let error as AppError {
            XCTAssertEqual(error, .offline)
        } catch {
            XCTFail("Expected AppError, got \(error)")
        }
    }

    func test_movieDetail_whenUnauthorized_throwsUnauthorized() async {
        let client = FakeHTTPClient(stub: .success(Data(), status: 401))
        let repository = MovieRepository.test(client: client)

        do {
            _ = try await repository.movieDetail(id: 278)
            XCTFail("Expected unauthorized")
        } catch let error as AppError {
            XCTAssertEqual(error, .unauthorized)
        } catch {
            XCTFail("Expected AppError, got \(error)")
        }
    }

    func test_movieDetail_whenGarbageJSON_throwsDecoding() async {
        let client = FakeHTTPClient(stub: .success(Data("not-json".utf8)))
        let repository = MovieRepository.test(client: client)

        do {
            _ = try await repository.movieDetail(id: 278)
            XCTFail("Expected decoding error")
        } catch let error as AppError {
            XCTAssertEqual(error, .decoding)
        } catch {
            XCTFail("Expected AppError, got \(error)")
        }
    }

    func test_nowPlaying_requestsNowPlayingPath() async throws {
        let client = RecordingHTTPClient(stub: .success(TMDBFixtures.topMoviesPage1))
        let repository = MovieRepository.test(client: client)
        let page = try await repository.nowPlaying(page: 1)
        let path = await client.lastPath
        XCTAssertEqual(path, "/3/movie/now_playing")
        XCTAssertEqual(page.movies.map(\.id), [278, 238])
        XCTAssertTrue(page.hasMore)
    }

    func test_upcoming_requestsUpcomingPath() async throws {
        let client = RecordingHTTPClient(stub: .success(TMDBFixtures.topMoviesPage1))
        let repository = MovieRepository.test(client: client)
        _ = try await repository.upcoming(page: 2)
        let path = await client.lastPath
        XCTAssertEqual(path, "/3/movie/upcoming")
    }

    func test_searchMovies_sendsQueryWithoutLoggingIt() async throws {
        let client = RecordingHTTPClient(stub: .success(TMDBFixtures.topMoviesPage1))
        let repository = MovieRepository.test(client: client)
        _ = try await repository.searchMovies(query: "shawshank", page: 1)
        let url = await client.lastURL
        let items = URLComponents(url: url!, resolvingAgainstBaseURL: false)?.queryItems
        XCTAssertEqual(url?.path, "/3/search/movie")
        XCTAssertEqual(items?.first { $0.name == "query" }?.value, "shawshank")
    }

    func test_movieDetail_mapsOfficialYouTubeTrailers() async throws {
        let payload = Data("""
        {
          "id": 1,
          "title": "Dune",
          "vote_average": 8,
          "videos": {
            "results": [
              {"name": "Teaser", "key": "tease", "site": "YouTube", "type": "Teaser", "official": true},
              {"name": "Official Trailer", "key": "abc_123", "site": "YouTube", "type": "Trailer", "official": true},
              {"key": "second", "site": "YouTube", "type": "Trailer", "official": true}
            ]
          }
        }
        """.utf8)
        let detail = try await MovieRepository.test(client: FakeHTTPClient(stub: .success(payload)))
            .movieDetail(id: 1)
        XCTAssertEqual(detail.trailers.map(\.title), ["Official Trailer", "Trailer 2"])
        XCTAssertEqual(detail.trailers.map(\.youtubeID), ["abc_123", "second"])
    }

    func test_movieDetail_keepsTheMovieWhenVideosAreMalformed() async throws {
        let payload = Data("""
        {
          "id": 1,
          "title": "Dune",
          "vote_average": 8,
          "videos": []
        }
        """.utf8)
        let detail = try await MovieRepository.test(client: FakeHTTPClient(stub: .success(payload)))
            .movieDetail(id: 1)
        XCTAssertEqual(detail.title, "Dune")
        XCTAssertTrue(detail.trailers.isEmpty)
    }
}
