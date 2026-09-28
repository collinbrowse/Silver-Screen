//
//  TMDBTrailerDecoding.swift
//  TheSilverScreen
//
//  Turns a TMDB `videos` block into playable trailers. A bad block does not fail the detail screen.
//

import Foundation

/// One row from TMDB's `videos.results`.
struct TMDBVideoDTO: Decodable, Sendable, Equatable {
    let name: String?
    let key: String?
    let site: String?
    let type: String?
    let official: Bool?
}

/// Selects the official YouTube trailers a detail screen can offer.
enum OfficialYouTubeTrailers {
    /// Official YouTube trailers in payload order. Duplicate ids are dropped.
    /// A blank name is "Trailer" on the first pill and "Trailer #" after that.
    /// A TMDB name replaces that fallback.
    static func make(from videos: [TMDBVideoDTO]) -> [MediaTrailer] {
        var seen: Set<String> = []
        let selected: [(id: String, name: String)] = videos.compactMap { video in
            guard video.official == true else { return nil }
            guard video.site?.caseInsensitiveCompare("YouTube") == .orderedSame else { return nil }
            guard video.type?.caseInsensitiveCompare("Trailer") == .orderedSame else { return nil }
            guard let id = youtubeID(from: video.key), seen.insert(id).inserted else { return nil }
            let name = video.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return (id, name)
        }
        return selected.enumerated().map { index, video in
            MediaTrailer(youtubeID: video.id, title: pillTitle(name: video.name, index: index))
        }
    }

    private static func pillTitle(name: String, index: Int) -> String {
        if !name.isEmpty {
            return name
        }
        if index == 0 {
            return "Trailer"
        }
        return "Trailer \(index + 1)"
    }

    /// YouTube ids are a short token. Anything else is dropped so it cannot be placed in the watch URL.
    private static func youtubeID(from key: String?) -> String? {
        let trimmed = key?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return nil }
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")
        guard trimmed.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { return nil }
        return trimmed
    }
}

/// Reads `videos` from a TMDB detail payload. A bad videos block does not fail the screen.
enum TMDBTrailerDecoding {
    static func trailers(from data: Data, logger: any AppLogging, context: String) -> [MediaTrailer] {
        do {
            let envelope = try JSONDecoder().decode(Envelope.self, from: data)
            return OfficialYouTubeTrailers.make(from: envelope.videos?.results ?? [])
        } catch {
            logger.error("\(context) skipped malformed videos", category: .networking)
            return []
        }
    }

    private struct Envelope: Decodable {
        let videos: TMDBVideosDTO?
    }

    private struct TMDBVideosDTO: Decodable {
        let results: [TMDBVideoDTO]?
    }
}
