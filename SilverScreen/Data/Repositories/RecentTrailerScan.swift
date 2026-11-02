//
//  RecentTrailerScan.swift
//  SilverScreen
//
//  The New Trailers Browse window. TMDB has no list of recently published videos,
//  so each candidate title's `/videos` is read and checked against `NewTrailerWindow`.
//  Release builds share a 240-requests-a-minute budget at the TMDB proxy, so the
//  candidate count is capped and only a few requests run at once.
//

import Foundation

/// Reads `/movie/{id}/videos` or `/tv/{id}/videos` for a capped set of titles and keeps
/// those with an official YouTube trailer inside the New Trailers window.
struct RecentTrailerScan: Sendable {
    enum Kind: Sendable {
        case movie
        case tv
    }

    /// Titles checked per media type. Each one costs a request against the proxy budget.
    static let maxCandidates = 30
    /// Requests in flight at once.
    static let maxConcurrent = 6

    let client: any HTTPClient
    let requests: TMDBRequestBuilder
    let logger: any AppLogging
    let sleeper: any Sleeper

    /// Candidates that have a new trailer, newest trailer first. Ties keep candidate order.
    /// Duplicates are dropped and only the first `maxCandidates` are checked.
    /// One title's failed request skips that title; if every request fails, that error is thrown.
    func newest<Item: Sendable>(
        _ candidates: [Item],
        kind: Kind,
        id: (Item) -> Int,
        locale: Locale,
        today: Date,
        timeZone: TimeZone
    ) async throws -> [Item] {
        var seen: Set<Int> = []
        let unique = candidates.filter { seen.insert(id($0)).inserted }.prefix(Self.maxCandidates)
        let dates = try await latestTrailerDates(
            ids: unique.map(id),
            kind: kind,
            locale: locale,
            today: today,
            timeZone: timeZone
        )
        return unique.enumerated()
            .compactMap { index, item in dates[id(item)].map { (index, item, $0) } }
            .sorted { lhs, rhs in lhs.2 != rhs.2 ? lhs.2 > rhs.2 : lhs.0 < rhs.0 }
            .map(\.1)
    }

    /// Newest in-window trailer date per id. Ids without one are absent.
    private func latestTrailerDates(
        ids: [Int],
        kind: Kind,
        locale: Locale,
        today: Date,
        timeZone: TimeZone
    ) async throws -> [Int: Date] {
        guard !ids.isEmpty else { return [:] }
        return try await withThrowingTaskGroup(of: (Int, Result<Date?, AppError>).self) { group in
            var pending = ids.makeIterator()
            for _ in 0..<min(Self.maxConcurrent, ids.count) {
                guard let next = pending.next() else { break }
                group.addTask { try await fetch(id: next, kind: kind, locale: locale, today: today, timeZone: timeZone) }
            }

            var dates: [Int: Date] = [:]
            var firstError: AppError?
            var failures = 0
            while let (id, result) = try await group.next() {
                switch result {
                    case .success(let date?):
                        dates[id] = date
                    case .success(nil):
                        break
                    case .failure(let error):
                        failures += 1
                        firstError = firstError ?? error
                }
                if let next = pending.next() {
                    group.addTask { try await fetch(id: next, kind: kind, locale: locale, today: today, timeZone: timeZone) }
                }
            }

            if failures == ids.count, let firstError {
                throw firstError
            }
            if failures > 0 {
                logger.error("New trailers skipped \(failures) title(s) whose videos failed", category: .networking)
            }
            return dates
        }
    }

    /// One title's newest in-window trailer. Only cancellation is thrown; other failures are returned.
    private func fetch(
        id: Int,
        kind: Kind,
        locale: Locale,
        today: Date,
        timeZone: TimeZone
    ) async throws -> (Int, Result<Date?, AppError>) {
        do {
            let path = switch kind {
                case .movie: "movie/\(id)/videos"
                case .tv: "tv/\(id)/videos"
            }
            let request = try requests.get(
                path: path,
                queryItems: [URLQueryItem(name: "language", value: TMDBLocale.languageTag(for: locale))]
            )
            let data = try await HTTPTransport.data(
                for: request,
                client: client,
                logger: logger,
                context: "New trailers",
                sleeper: sleeper
            )
            let videos: [TMDBVideoDTO]
            do {
                videos = try JSONDecoder().decode(VideosDTO.self, from: data).results ?? []
            } catch {
                logger.error("New trailers skipped malformed videos", category: .networking)
                videos = []
            }
            let newest = OfficialYouTubeTrailers.make(from: videos)
                .compactMap(\.publishedAt)
                .filter { NewTrailerWindow.contains($0, today: today, timeZone: timeZone) }
                .max()
            return (id, .success(newest))
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return (id, .failure((error as? AppError) ?? .unknown))
        }
    }

    private struct VideosDTO: Decodable {
        let results: [TMDBVideoDTO]?
    }
}
