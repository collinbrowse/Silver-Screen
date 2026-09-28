//
//  MediaTrailer.swift
//  TheSilverScreen
//
//  A trailer the app can play. The TMDB `videos` block is decoded in the networking layer.
//

import Foundation

/// A trailer the app can play inside YouTube's player.
struct MediaTrailer: Sendable, Equatable, Hashable, Identifiable {
    /// YouTube video id. Also the identity of the player sheet.
    let youtubeID: String
    /// Pill title. A blank TMDB name becomes "Trailer", then "Trailer 2", and so on.
    let title: String

    var id: String { youtubeID }

    /// Referer origin for the watch page. YouTube rejects a player request that has none.
    static let embedOrigin = URL(string: "https://www.youtube.com")!

    /// Watch page. YouTube's embed endpoint rejects in-app web views with error 152-4;
    /// the watch page is the same player and does not.
    var watchURL: URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "www.youtube.com"
        components.path = "/watch"
        components.queryItems = [
            URLQueryItem(name: "v", value: youtubeID),
            URLQueryItem(name: "playsinline", value: "1"),
        ]
        return components.url ?? Self.embedOrigin
    }
}
