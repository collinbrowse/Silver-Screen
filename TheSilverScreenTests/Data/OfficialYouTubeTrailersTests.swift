//
//  OfficialYouTubeTrailersTests.swift
//  TheSilverScreenTests
//

import XCTest
@testable import TheSilverScreen

final class OfficialYouTubeTrailersTests: XCTestCase {

    func test_make_namesBlankTrailersByPositionAndKeepsGivenNames() {
        let videos = [
            video(name: "   ", key: "first", site: "YouTube", type: "Trailer", official: true),
            video(name: "Official Trailer", key: "second", site: "youtube", type: "trailer", official: true),
            video(name: nil, key: "third", site: "YouTube", type: "Trailer", official: true),
        ]

        let trailers = OfficialYouTubeTrailers.make(from: videos)

        XCTAssertEqual(trailers.map(\.youtubeID), ["first", "second", "third"])
        XCTAssertEqual(trailers.map(\.title), ["Trailer", "Official Trailer", "Trailer 3"])
        let watch = URLComponents(url: trailers[0].watchURL, resolvingAgainstBaseURL: false)
        XCTAssertEqual(watch?.host, "www.youtube.com")
        XCTAssertEqual(watch?.path, "/watch")
        XCTAssertEqual(watch?.queryItems?.first { $0.name == "v" }?.value, "first")
    }

    func test_make_dropsNonTrailersDuplicatesAndUnsafeKeys() {
        let videos = [
            video(name: "Teaser", key: "tease", site: "YouTube", type: "Teaser", official: true),
            video(name: "Fan cut", key: "fan", site: "YouTube", type: "Trailer", official: false),
            video(name: "Vimeo", key: "vim", site: "Vimeo", type: "Trailer", official: true),
            video(name: "Main", key: "main", site: "YouTube", type: "Trailer", official: true),
            video(name: "Again", key: "main", site: "YouTube", type: "Trailer", official: true),
            video(name: "Broken", key: "ab\"c", site: "YouTube", type: "Trailer", official: true),
            video(name: "Missing", key: "  ", site: "YouTube", type: "Trailer", official: true),
            video(name: nil, key: "fourth", site: "YouTube", type: "Trailer", official: nil),
        ]

        let trailers = OfficialYouTubeTrailers.make(from: videos)

        XCTAssertEqual(trailers.map(\.youtubeID), ["main"])
        XCTAssertEqual(trailers.map(\.title), ["Main"])
    }

    private func video(
        name: String?,
        key: String?,
        site: String?,
        type: String?,
        official: Bool?
    ) -> TMDBVideoDTO {
        TMDBVideoDTO(name: name, key: key, site: site, type: type, official: official)
    }
}
