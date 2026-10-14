//
//  DemoLibrarySeed.swift
//  SilverScreen
//
//  The library a marketing capture starts with. Decoded from the `library` object
//  in `marketing/titles.json` and written through the real repositories, so the
//  seeded rows follow the same product rules as a user's own adds.
//

import Foundation

/// Watched, Watchlist, and custom lists, each in display order (first item on top).
struct DemoLibrarySeed: Decodable, Sendable, Equatable {
    /// One title. Metadata mirrors what a list row saves at add time; `score` and
    /// `note` become the user's rating and review for that title.
    struct Item: Decodable, Sendable, Equatable {
        let id: Int
        let kind: ListItemKind
        let title: String
        let posterPath: String?
        /// `yyyy-MM-dd`, as TMDB returns it.
        let releaseDate: String?
        let genres: [String]?
        let voteAverage: Double?
        let popularity: Double?
        let score: Double?
        let note: String?

        var draft: ListItemDraft {
            ListItemDraft(
                id: id,
                kind: kind,
                title: title,
                imagePath: posterPath,
                releaseDate: releaseDate.flatMap(Self.day),
                genreNames: genres ?? [],
                voteAverage: voteAverage ?? 0,
                popularity: popularity ?? 0
            )
        }

        /// Movies and series carry a rating; a person cannot.
        var annotationKey: AnnotationKey? {
            switch kind {
                case .movie: .movie(id)
                case .tv: .series(id)
                case .person: nil
            }
        }

        private static func day(_ raw: String) -> Date? {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withFullDate]
            return formatter.date(from: raw)
        }
    }

    /// A user-made list. Movies & TV and People lists are told apart by their items.
    struct CustomList: Decodable, Sendable, Equatable {
        let name: String
        let items: [Item]
    }

    let watched: [Item]
    let watchlist: [Item]
    let lists: [CustomList]

    private enum CodingKeys: String, CodingKey {
        case watched, watchlist, lists
    }

    init(watched: [Item] = [], watchlist: [Item] = [], lists: [CustomList] = []) {
        self.watched = watched
        self.watchlist = watchlist
        self.lists = lists
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        watched = try container.decodeIfPresent([Item].self, forKey: .watched) ?? []
        watchlist = try container.decodeIfPresent([Item].self, forKey: .watchlist) ?? []
        lists = try container.decodeIfPresent([CustomList].self, forKey: .lists) ?? []
    }

    /// Reads the `library` object from a marketing titles file.
    static func load(from url: URL) throws -> DemoLibrarySeed {
        struct File: Decodable { let library: DemoLibrarySeed }
        return try JSONDecoder().decode(File.self, from: Data(contentsOf: url)).library
    }

    /// Writes the seed into an empty library. Add dates count back an hour per row
    /// from `now`, so Date Added order matches the order in the file.
    func apply(
        lists listsRepository: ListsRepository,
        annotations: AnnotationsRepository,
        now: Date = Date()
    ) async throws {
        let snapshot = try await listsRepository.snapshot()
        guard let watchlistID = snapshot.list(.watchlist)?.id else {
            throw ListEditError.missingList
        }

        for (offset, item) in watched.enumerated() {
            _ = try await listsRepository.addToWatched(item.draft, at: Self.date(offset, before: now))
        }
        for (offset, item) in watchlist.enumerated() {
            _ = try await listsRepository.add(
                draft: item.draft,
                listID: watchlistID,
                at: Self.date(offset, before: now)
            )
        }
        for list in lists {
            guard let segment = list.items.first?.kind.segment else { continue }
            let creation = try await listsRepository.createList(name: list.name, segment: segment, at: now)
            // Custom lists put each new title on top, so add from the bottom up.
            for (offset, item) in list.items.enumerated().reversed() {
                _ = try await listsRepository.add(
                    draft: item.draft,
                    listID: creation.list.id,
                    at: Self.date(offset, before: now)
                )
            }
        }

        let rated = watched + watchlist + lists.flatMap(\.items)
        for item in rated {
            guard let key = item.annotationKey, let score = item.score else { continue }
            try await annotations.save(score: score, note: item.note ?? "", for: key, at: now)
        }
    }

    private static func date(_ offset: Int, before now: Date) -> Date {
        now.addingTimeInterval(-Double(offset) * 3600)
    }
}
