//
//  TVRepositoryTests.swift
//  TheSilverScreenTests
//

import XCTest
@testable import TheSilverScreen

final class TVRepositoryTests: XCTestCase {

    func test_series_mapsHeaderSeasonsCastAndCrew() async throws {
        let client = RecordingHTTPClient(stub: .success(TMDBFixtures.tvSeriesBreakingBad))
        let repository = TVRepository.test(client: client)

        let series = try await repository.series(id: 1396)

        let path = await client.lastPath
        XCTAssertEqual(path, "/3/tv/1396")
        XCTAssertEqual(series.name, "Breaking Bad")
        XCTAssertEqual(series.creators, ["Vince Gilligan"])
        XCTAssertEqual(series.genres.map(\.name), ["Drama"])
        XCTAssertEqual(series.seasons.map(\.seasonNumber), [1, 2])
        XCTAssertEqual(series.cast.map(\.name), ["Bryan Cranston", "Aaron Paul"])
        XCTAssertEqual(series.cast[0].role, "Walter White")
        XCTAssertEqual(series.directorsAndWriters.map(\.name), ["Vince Gilligan", "Michelle MacLaren"])
        XCTAssertEqual(series.recommendations.map(\.name), ["Better Call Saul"])
        XCTAssertEqual(series.images.map(\.filePath), ["/wide.jpg"])
        XCTAssertNotNil(series.firstAirDate)
        XCTAssertNotNil(series.lastAirDate)
    }

    func test_mapAggregateCast_sortsByEpisodeCountAndLimitsToThirty() {
        let cast = (1...31).map { index in
            TVAggregateCastDTO(
                id: index,
                name: "Actor \(index)",
                profilePath: nil,
                knownForDepartment: "Acting",
                totalEpisodeCount: index,
                roles: [TVAggregateRoleDTO(character: "Role \(index)", episodeCount: index)]
            )
        }
        let credits = TVRepository.mapAggregateCast(cast, logger: SilentLogger())
        XCTAssertEqual(credits.count, 30)
        XCTAssertEqual(credits.first?.id, 31)
        XCTAssertEqual(credits.last?.id, 2)
    }

    func test_season_mapsEpisodesAndDirector() async throws {
        let repository = TVRepository.test(
            client: FakeHTTPClient(stub: .success(TMDBFixtures.tvSeasonPilot))
        )
        let season = try await repository.season(seriesID: 1396, seasonNumber: 1)
        XCTAssertEqual(season.name, "The Beginning")
        XCTAssertEqual(season.episodes.count, 1)
        XCTAssertEqual(season.episodes[0].title, "Pilot")
        XCTAssertEqual(season.episodes[0].directorName, "Vince Gilligan")
        XCTAssertEqual(season.images.map(\.filePath), ["/still.jpg"])
        XCTAssertEqual(season.cast.map(\.role), ["Walter White"])
    }

    func test_episode_separatesCastGuestsAndCrew() async throws {
        let repository = TVRepository.test(
            client: FakeHTTPClient(stub: .success(TMDBFixtures.tvEpisodePilot))
        )
        let episode = try await repository.episode(seriesID: 1396, seasonNumber: 1, episodeNumber: 1)
        XCTAssertEqual(episode.title, "Pilot")
        XCTAssertEqual(episode.cast.map(\.name), ["Bryan Cranston"])
        XCTAssertEqual(episode.guestStars.map(\.name), ["John Koyama"])
        XCTAssertEqual(episode.directorsAndWriters.map(\.name), ["Vince Gilligan", "Story Person", "Screen Person"])
        XCTAssertFalse(episode.directorsAndWriters.contains { $0.name == "Script Coordinator" })
        XCTAssertTrue(episode.directorsAndWriters[0].role.contains("Director"))
        XCTAssertTrue(episode.directorsAndWriters[0].role.contains("Writer"))
        XCTAssertEqual(episode.images.map(\.filePath), ["/still.jpg"])
    }

    func test_series_usesTheDeviceLanguageAndDropsItselfFromRecommendations() async throws {
        let client = RecordingHTTPClient(stub: .success(TMDBFixtures.tvSeriesBreakingBad))
        let repository = TVRepository.test(client: client)

        let series = try await repository.series(id: 1396, locale: Locale(identifier: "fr_FR"))

        let url = await client.lastURL
        XCTAssertTrue(url?.absoluteString.contains("language=fr-FR") == true)
        XCTAssertEqual(series.recommendations.map(\.id), [60059])
        XCTAssertEqual(series.cast.map(\.name), ["Bryan Cranston", "Aaron Paul"])
    }

    func test_mapAggregateCast_breaksEqualCountsByNameAndDropsZero() {
        let cast = [
            TVAggregateCastDTO(
                id: 2,
                name: "Zed",
                profilePath: nil,
                knownForDepartment: "Acting",
                totalEpisodeCount: 5,
                roles: [TVAggregateRoleDTO(character: "A", episodeCount: 5)]
            ),
            TVAggregateCastDTO(
                id: 1,
                name: "Amy",
                profilePath: nil,
                knownForDepartment: "Acting",
                totalEpisodeCount: 5,
                roles: [TVAggregateRoleDTO(character: "B", episodeCount: 5)]
            ),
            TVAggregateCastDTO(
                id: 3,
                name: "Never Aired",
                profilePath: nil,
                knownForDepartment: "Acting",
                totalEpisodeCount: 0,
                roles: [TVAggregateRoleDTO(character: "C", episodeCount: 0)]
            ),
        ]
        let credits = TVRepository.mapAggregateCast(cast, logger: SilentLogger())
        XCTAssertEqual(credits.map(\.name), ["Amy", "Zed"])
    }

    func test_season_joinsEveryDirector() async throws {
        let payload = Data("""
        {
          "id": 2,
          "name": "Season 2",
          "season_number": 2,
          "episodes": [
            {
              "id": 11,
              "name": "Grilled",
              "episode_number": 2,
              "crew": [
                {"id": 4, "credit_id": "dir-1", "name": "Vince Gilligan", "job": "Director", "department": "Directing"},
                {"id": 5, "credit_id": "dir-2", "name": "Michelle MacLaren", "job": "Director", "department": "Directing"}
              ]
            }
          ]
        }
        """.utf8)
        let season = try await TVRepository.test(client: FakeHTTPClient(stub: .success(payload)))
            .season(seriesID: 1396, seasonNumber: 2)
        XCTAssertEqual(season.episodes[0].directorName, "Vince Gilligan, Michelle MacLaren")
        XCTAssertEqual(season.episodes[0].directorLine, "Director: Vince Gilligan, Michelle MacLaren")
    }

    func test_season_reportsUnknownDirectorWhenNoneAreCredited() async throws {
        let payload = Data("""
        {
          "id": 1,
          "name": "Specials",
          "season_number": 0,
          "episodes": [
            {"id": 12, "name": "Extra", "episode_number": 1, "crew": []}
          ]
        }
        """.utf8)
        let season = try await TVRepository.test(client: FakeHTTPClient(stub: .success(payload)))
            .season(seriesID: 1396, seasonNumber: 0)
        XCTAssertNil(season.episodes[0].directorName)
        XCTAssertEqual(season.episodes[0].directorLine, "Director: unknown")
    }

    func test_popular_requestsPopularTV() async throws {
        let client = RecordingHTTPClient(stub: .success(TMDBFixtures.popularTVPage))
        let repository = TVRepository.test(client: client)
        let page = try await repository.popular(page: 1)
        let path = await client.lastPath
        XCTAssertEqual(path, "/3/tv/popular")
        XCTAssertEqual(page.series.map(\.name), ["Breaking Bad"])
        XCTAssertTrue(page.hasMore)
    }

    func test_series_skipsMalformedImagesAndKeepsTheSeries() async throws {
        let payload = Data("""
        {
          "id": 1396,
          "name": "Breaking Bad",
          "images": { "backdrops": "not-an-array" },
          "aggregate_credits": { "cast": [], "crew": [] },
          "recommendations": { "results": [] }
        }
        """.utf8)
        let series = try await TVRepository.test(client: FakeHTTPClient(stub: .success(payload)))
            .series(id: 1396)
        XCTAssertEqual(series.name, "Breaking Bad")
        XCTAssertTrue(series.images.isEmpty)
        XCTAssertTrue(series.cast.isEmpty)
    }

    func test_series_appendsVideosAndMapsOfficialTrailers() async throws {
        let client = RecordingHTTPClient(stub: .success(Self.detailPayload(
            core: #""id": 9, "name": "Show""#,
            videos: Self.twoTrailers
        )))
        let repository = TVRepository.test(client: client)
        let series = try await repository.series(id: 9)
        let url = await client.lastURL
        let items = URLComponents(url: url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
        XCTAssertTrue(items.contains(URLQueryItem(name: "append_to_response", value: "images,aggregate_credits,recommendations,videos")))
        XCTAssertEqual(series.trailers.map(\.title), ["Official Trailer", "Trailer 2"])
    }

    func test_season_appendsVideosAndMapsOfficialTrailers() async throws {
        let client = RecordingHTTPClient(stub: .success(Self.detailPayload(
            core: #""id": 3, "season_number": 1"#,
            videos: Self.twoTrailers
        )))
        let repository = TVRepository.test(client: client)
        let season = try await repository.season(seriesID: 9, seasonNumber: 1)
        let url = await client.lastURL
        let items = URLComponents(url: url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
        XCTAssertTrue(items.contains(URLQueryItem(name: "append_to_response", value: "images,aggregate_credits,videos")))
        XCTAssertEqual(season.trailers.map(\.youtubeID), ["abc_123", "second"])
    }

    func test_episode_appendsVideosAndMapsOfficialTrailers() async throws {
        let client = RecordingHTTPClient(stub: .success(Self.detailPayload(
            core: #""id": 4, "episode_number": 2"#,
            videos: Self.twoTrailers
        )))
        let repository = TVRepository.test(client: client)
        let episode = try await repository.episode(seriesID: 9, seasonNumber: 1, episodeNumber: 2)
        let url = await client.lastURL
        let items = URLComponents(url: url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
        XCTAssertTrue(items.contains(URLQueryItem(name: "append_to_response", value: "images,credits,videos")))
        XCTAssertEqual(episode.trailers.map(\.title), ["Official Trailer", "Trailer 2"])
    }

    private static let twoTrailers = """
    {"name": "Official Trailer", "key": "abc_123", "site": "YouTube", "type": "Trailer", "official": true},
    {"key": "second", "site": "YouTube", "type": "Trailer", "official": true}
    """

    private static func detailPayload(core: String, videos: String) -> Data {
        Data("""
        {
          \(core),
          "videos": { "results": [\(videos)] }
        }
        """.utf8)
    }
}
