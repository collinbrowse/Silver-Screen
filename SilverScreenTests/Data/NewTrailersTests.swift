//
//  NewTrailersTests.swift
//  SilverScreenTests
//
//  The New Trailers window rule, `published_at` decoding, and the per-title scan.
//

import XCTest
@testable import SilverScreen

final class NewTrailersTests: XCTestCase {

    private let utc = TimeZone(secondsFromGMT: 0)!
    private let locale = Locale(identifier: "en_US")

    // MARK: - Window

    func test_window_coversTodayAndTheSixDaysBeforeIt() {
        let today = instant("2024-06-15T12:00:00Z")

        XCTAssertTrue(NewTrailerWindow.contains(instant("2024-06-15T11:00:00Z"), today: today, timeZone: utc))
        XCTAssertTrue(NewTrailerWindow.contains(instant("2024-06-09T00:00:00Z"), today: today, timeZone: utc))
        XCTAssertFalse(NewTrailerWindow.contains(instant("2024-06-08T23:59:59Z"), today: today, timeZone: utc))
    }

    func test_window_startsAtTheUsersMidnightNotUTC() {
        let losAngeles = TimeZone(identifier: "America/Los_Angeles")!
        let today = instant("2024-06-15T12:00:00Z")
        // June 9 06:59 UTC is still June 8 in Los Angeles.
        let lateJune8Pacific = instant("2024-06-09T06:59:00Z")

        XCTAssertTrue(NewTrailerWindow.contains(lateJune8Pacific, today: today, timeZone: utc))
        XCTAssertFalse(NewTrailerWindow.contains(lateJune8Pacific, today: today, timeZone: losAngeles))
        XCTAssertTrue(NewTrailerWindow.contains(instant("2024-06-09T07:00:00Z"), today: today, timeZone: losAngeles))
    }

    // MARK: - Decoding

    func test_officialTrailers_carryPublishedAt() throws {
        let data = Self.videos([("abc", "2024-06-12T16:00:11.000Z"), ("def", "not a date")])
        let trailers = TMDBTrailerDecoding.trailers(
            from: Data("{\"videos\":\(String(decoding: data, as: UTF8.self))}".utf8),
            logger: SilentLogger(),
            context: "Test"
        )

        XCTAssertEqual(trailers.map(\.youtubeID), ["abc", "def"])
        XCTAssertEqual(trailers[0].publishedAt, instant("2024-06-12T16:00:11Z"))
        XCTAssertNil(trailers[1].publishedAt)
    }

    // MARK: - Scan

    func test_movieNewTrailers_keepsRecentTrailersNewestFirstAndDedupes() async throws {
        let client = RoutingHTTPClient(routes: [
            "movie/upcoming": .success(Self.moviePage(ids: [1, 2])),
            "movie/now_playing": .success(Self.moviePage(ids: [2, 3])),
            "movie/1/videos": .success(Self.videos([("one", "2024-06-10T00:00:00.000Z")])),
            "movie/2/videos": .success(Self.videos([("two", "2024-05-01T00:00:00.000Z")])),
            "movie/3/videos": .success(Self.videos([("three", "2024-06-14T00:00:00.000Z")])),
            ])
        let repository = MovieRepository.test(client: client)

        let page = try await repository.newTrailers(locale: locale, today: instant("2024-06-15T12:00:00Z"), timeZone: utc)

        XCTAssertEqual(page.movies.map(\.id), [3, 1])
        XCTAssertFalse(page.hasMore)
        let videoRequests = await client.requests.compactMap(\.url?.path).filter { $0.hasSuffix("/videos") }
        XCTAssertEqual(videoRequests.count, 3, "Movie 2 is on both lists but is checked once")
    }

    func test_movieNewTrailers_skipsATitleWhoseVideosFail() async throws {
        let client = RoutingHTTPClient(routes: [
            "movie/upcoming": .success(Self.moviePage(ids: [1, 2])),
            "movie/now_playing": .success(Self.moviePage(ids: [])),
            "movie/1/videos": .success(Data(), status: 404),
            "movie/2/videos": .success(Self.videos([("two", "2024-06-14T00:00:00.000Z")])),
            ])
        let repository = MovieRepository.test(client: client)

        let page = try await repository.newTrailers(locale: locale, today: instant("2024-06-15T12:00:00Z"), timeZone: utc)

        XCTAssertEqual(page.movies.map(\.id), [2])
    }

    func test_movieNewTrailers_throwsWhenEveryTitleFails() async {
        let client = RoutingHTTPClient(routes: [
            "movie/upcoming": .success(Self.moviePage(ids: [1, 2])),
            "movie/now_playing": .success(Self.moviePage(ids: [])),
            "videos": .success(Data(), status: 404),
            ])
        let repository = MovieRepository.test(client: client)

        do {
            _ = try await repository.newTrailers(locale: locale, today: instant("2024-06-15T12:00:00Z"), timeZone: utc)
            XCTFail("Expected an error when no title's videos load")
        } catch {
            XCTAssertTrue(error is AppError)
        }
    }

    func test_scan_checksAtMostMaxCandidatesTitles() async throws {
        let ids = Array(1...(RecentTrailerScan.maxCandidates + 10))
        let client = RoutingHTTPClient(routes: [
            "movie/upcoming": .success(Self.moviePage(ids: ids)),
            "movie/now_playing": .success(Self.moviePage(ids: [])),
            "videos": .success(Self.videos([])),
            ])
        let repository = MovieRepository.test(client: client)

        let page = try await repository.newTrailers(locale: locale, today: instant("2024-06-15T12:00:00Z"), timeZone: utc)

        XCTAssertTrue(page.movies.isEmpty)
        let videoRequests = await client.requests.compactMap(\.url?.path).filter { $0.hasSuffix("/videos") }
        XCTAssertEqual(videoRequests.count, RecentTrailerScan.maxCandidates)
    }

    func test_tvNewTrailers_readsSeriesVideos() async throws {
        let client = RoutingHTTPClient(routes: [
            "discover/tv": .success(Self.tvPage(ids: [7])),
            "tv/on_the_air": .success(Self.tvPage(ids: [8])),
            "tv/7/videos": .success(Self.videos([("seven", "2024-06-13T00:00:00.000Z")])),
            "tv/8/videos": .success(Self.videos([("eight", "2024-01-01T00:00:00.000Z")])),
            ])
        let repository = TVRepository.test(client: client)

        let page = try await repository.newTrailers(locale: locale, today: instant("2024-06-15T12:00:00Z"), timeZone: utc)

        XCTAssertEqual(page.series.map(\.id), [7])
    }

    // MARK: - Fixtures

    private func instant(_ iso: String) -> Date {
        ISO8601DateFormatter().date(from: iso)!
    }

    static func moviePage(ids: [Int]) -> Data {
        let results = ids.map {
            """
            {"id": \($0), "title": "Movie \($0)", "genre_ids": [18], "release_date": "2024-06-01", "vote_average": 7, "vote_count": 10}
            """
        }
        return Data("{\"page\":1,\"results\":[\(results.joined(separator: ","))],\"total_pages\":1,\"total_results\":\(ids.count)}".utf8)
    }

    static func tvPage(ids: [Int]) -> Data {
        let results = ids.map {
            """
            {"id": \($0), "name": "Show \($0)", "genre_ids": [18], "first_air_date": "2024-06-01", "vote_average": 7}
            """
        }
        return Data("{\"page\":1,\"results\":[\(results.joined(separator: ","))],\"total_pages\":1,\"total_results\":\(ids.count)}".utf8)
    }

    /// A `/videos` payload of official YouTube trailers.
    static func videos(_ trailers: [(key: String, publishedAt: String)]) -> Data {
        let results = trailers.map {
            """
            {"name": "Trailer", "key": "\($0.key)", "site": "YouTube", "type": "Trailer", "official": true, "published_at": "\($0.publishedAt)"}
            """
        }
        return Data("{\"results\":[\(results.joined(separator: ","))]}".utf8)
    }
}
