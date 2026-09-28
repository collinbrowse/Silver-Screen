//
//  FakeHTTPClientTests.swift
//  TheSilverScreenTests
//
//  Canary for the test seam. If this fails, every repository/view-model test
//  built on FakeHTTPClient is untrustworthy.
//

import XCTest
@testable import TheSilverScreen

final class FakeHTTPClientTests: XCTestCase {

    func test_data_whenStubSucceeds_returnsFixtureAndStatus() async throws {
        let client = FakeHTTPClient(stub: .success(TMDBFixtures.topMoviesPage1, status: 200))
        let request = URLRequest(url: URL(string: "https://api.themoviedb.org/3/discover/movie")!)

        let (data, response) = try await client.data(for: request)

        XCTAssertEqual(response.statusCode, 200)
        XCTAssertEqual(data, TMDBFixtures.topMoviesPage1)
        XCTAssertFalse(TMDBFixtures.topMoviesPage1.isEmpty)
    }

    func test_data_whenStubFails_throwsURLError() async {
        let client = FakeHTTPClient(result: .failure(URLError(.notConnectedToInternet)))
        let request = URLRequest(url: URL(string: "https://api.themoviedb.org/3/discover/movie")!)

        do {
            _ = try await client.data(for: request)
            XCTFail("Expected FakeHTTPClient to throw")
        } catch let error as URLError {
            XCTAssertEqual(error.code, .notConnectedToInternet)
        } catch {
            XCTFail("Expected URLError, got \(error)")
        }
    }

    func test_fixture_topMoviesPage1_decodesAsMovieList() throws {
        let list = try JSONDecoder().decode(MovieListDTO.self, from: TMDBFixtures.topMoviesPage1)

        XCTAssertEqual(list.page, 1)
        XCTAssertEqual(list.totalPages, 2)
        XCTAssertEqual(list.results.count, 2)
        XCTAssertEqual(list.results[0].id, 278)
        XCTAssertEqual(list.results[0].title, "The Shawshank Redemption")
        XCTAssertEqual(list.results[1].id, 238)
    }

    func test_fixture_emptyReleaseDate_stillDecodes() throws {
        let list = try JSONDecoder().decode(
            MovieListDTO.self,
            from: TMDBFixtures.topMoviesWithEmptyReleaseDate
        )

        XCTAssertEqual(list.results.count, 1)
        XCTAssertEqual(list.results[0].releaseDate, "")
    }

    func test_sessionConfiguration_failsFastWhenOffline() {
        let configuration = URLSessionHTTPClient.makeConfiguration()

        // Fail fast: with waitsForConnectivity on, an airplane-mode cold load parks until the
        // resource timeout and then reports the wrong ("timed out") error. Off, it fails
        // immediately with .notConnectedToInternet so the UI shows "You're Offline" right away.
        XCTAssertFalse(configuration.waitsForConnectivity)
        XCTAssertEqual(configuration.timeoutIntervalForRequest, 15)
        XCTAssertEqual(configuration.timeoutIntervalForResource, 25)
        XCTAssertLessThan(configuration.timeoutIntervalForResource, 60)
    }

    func test_imageConfiguration_hasDedicatedDiskCacheSeparateFromJSON() {
        let imageConfig = URLSessionHTTPClient.makeImageConfiguration()

        XCTAssertGreaterThan(imageConfig.urlCache?.diskCapacity ?? 0, 0)
        XCTAssertGreaterThan(imageConfig.urlCache?.memoryCapacity ?? 0, 0)
        // A distinct cache instance from the shared JSON session's, so images don't compete with it.
        XCTAssertFalse(imageConfig.urlCache === URLSessionHTTPClient.makeConfiguration().urlCache)
        // Still inherits the fail-fast transport settings.
        XCTAssertFalse(imageConfig.waitsForConnectivity)
        XCTAssertEqual(imageConfig.timeoutIntervalForResource, 25)
    }

    func test_routingClient_prefersLongestPathMatch() async throws {
        let client = RoutingHTTPClient(routes: [
            "/movie/278": .success(TMDBFixtures.movieDetailShawshank),
            "/movie/278/reviews": .success(TMDBFixtures.movieReviewsPage1),
        ])
        let detailRequest = URLRequest(url: URL(string: "https://api.themoviedb.org/3/movie/278")!)
        let reviewsRequest = URLRequest(url: URL(string: "https://api.themoviedb.org/3/movie/278/reviews")!)

        let (detailData, _) = try await client.data(for: detailRequest)
        let (reviewsData, _) = try await client.data(for: reviewsRequest)

        XCTAssertEqual(detailData, TMDBFixtures.movieDetailShawshank)
        XCTAssertEqual(reviewsData, TMDBFixtures.movieReviewsPage1)
    }
}
