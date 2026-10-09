//
//  TVWatchProgress.swift
//  TheSilverScreen
//
//  Episode-level TV watch ledger. An episode is completed or not; season and
//  series completion are derived from the completed set vs the TMDB catalog.
//  Next up prefers the episode after the highest completed one; when that is
//  past the finale but gaps remain, it is the first unwatched episode.
//

import Foundation

/// One episode inside a series. Identity is season + episode number (not TMDB episode id).
struct TVEpisodeRef: Codable, Sendable, Equatable, Hashable, Comparable {
    let seasonNumber: Int
    let episodeNumber: Int

    static func < (lhs: TVEpisodeRef, rhs: TVEpisodeRef) -> Bool {
        if lhs.seasonNumber != rhs.seasonNumber {
            return lhs.seasonNumber < rhs.seasonNumber
        }
        return lhs.episodeNumber < rhs.episodeNumber
    }
}

/// One season’s episode count as it looked on TMDB when we froze a catalog snapshot.
struct TVCatalogSeasonCount: Codable, Sendable, Equatable, Hashable {
    let seasonNumber: Int
    let episodeCount: Int
}

/// Watch progress for one series.
struct TVSeriesWatchState: Codable, Sendable, Equatable {
    let seriesID: Int
    /// Completed regular episodes. Specials (season 0) are never stored.
    var completed: [TVEpisodeRef]
    /// Next episode to watch after the highest completed one. Nil when caught up / finished.
    var nextUp: TVEpisodeRef?
    /// Title of `nextUp`, when known.
    var nextUpTitle: String?
    /// TMDB season→episodeCount shape frozen when this series last moved to Watched.
    /// Nil while In Progress (or never finished). Cold launch compares a fresh TMDB
    /// fetch to this so a new season / more episodes can reopen In Progress.
    var catalogSnapshot: [TVCatalogSeasonCount]?

    init(
        seriesID: Int,
        completed: [TVEpisodeRef] = [],
        nextUp: TVEpisodeRef? = nil,
        nextUpTitle: String? = nil,
        catalogSnapshot: [TVCatalogSeasonCount]? = nil
    ) {
        self.seriesID = seriesID
        self.completed = Self.normalized(completed)
        self.nextUp = nextUp
        self.nextUpTitle = nextUpTitle
        self.catalogSnapshot = catalogSnapshot
    }

    /// Decode through `normalized` so specials / dupes on disk cannot re-enter the ledger.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        seriesID = try container.decode(Int.self, forKey: .seriesID)
        completed = Self.normalized(
            try container.decodeIfPresent([TVEpisodeRef].self, forKey: .completed) ?? []
        )
        nextUp = try container.decodeIfPresent(TVEpisodeRef.self, forKey: .nextUp)
        nextUpTitle = try container.decodeIfPresent(String.self, forKey: .nextUpTitle)
        catalogSnapshot = try container.decodeIfPresent(
            [TVCatalogSeasonCount].self,
            forKey: .catalogSnapshot
        )
    }

    private enum CodingKeys: String, CodingKey {
        case seriesID, completed, nextUp, nextUpTitle, catalogSnapshot
    }

    /// Highest completed episode by season, then episode number. Gaps behind it are ignored.
    var lastCompleted: TVEpisodeRef? {
        completed.max()
    }

    var completedSet: Set<TVEpisodeRef> {
        Set(completed)
    }

    func contains(seasonNumber: Int, episodeNumber: Int) -> Bool {
        completedSet.contains(TVEpisodeRef(seasonNumber: seasonNumber, episodeNumber: episodeNumber))
    }

    /// In Progress subtitle: `Next up: S2 · E3 · Episode name`.
    var progressSubtitle: String? {
        guard let next = nextUp else { return nil }
        let title = nextUpTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let prefix = "Next up: S\(next.seasonNumber) · E\(next.episodeNumber)"
        return title.isEmpty ? prefix : "\(prefix) · \(title)"
    }

    /// Updates `nextUp` / `nextUpTitle` from completed episodes and catalog seasons.
    /// Prefers the episode after the highest completed one; when that would be past
    /// the finale but gaps remain, falls back to the first unwatched episode.
    mutating func refreshNextUp(
        against seasons: [TVSeasonSummary],
        episodeTitles: [TVEpisodeRef: String] = [:]
    ) {
        if let sequential = Self.nextEpisode(after: lastCompleted, seasons: seasons) {
            nextUp = sequential
        } else if !isSeriesComplete(against: seasons),
                  let gap = Self.firstUnwatchedEpisode(in: seasons, completed: completedSet) {
            nextUp = gap
        } else {
            nextUp = nil
        }
        if let nextUp {
            let trimmed = episodeTitles[nextUp]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            nextUpTitle = trimmed.isEmpty ? nil : trimmed
        } else {
            nextUpTitle = nil
        }
    }

    /// Episode after `last` in catalog order. Nil when `last` is the catalog finale
    /// (or the catalog is empty). Does not look behind `last` for gaps.
    static func nextEpisode(
        after last: TVEpisodeRef?,
        seasons: [TVSeasonSummary]
    ) -> TVEpisodeRef? {
        let regular = regularSeasons(seasons)
            .filter { $0.episodeCount > 0 }
            .sorted { $0.seasonNumber < $1.seasonNumber }
        guard !regular.isEmpty else { return nil }

        guard let last else {
            let first = regular[0]
            return TVEpisodeRef(seasonNumber: first.seasonNumber, episodeNumber: 1)
        }

        if let current = regular.first(where: { $0.seasonNumber == last.seasonNumber }),
           last.episodeNumber < current.episodeCount {
            return TVEpisodeRef(
                seasonNumber: last.seasonNumber,
                episodeNumber: last.episodeNumber + 1
            )
        }

        guard let nextSeason = regular.first(where: { $0.seasonNumber > last.seasonNumber }) else {
            return nil
        }
        return TVEpisodeRef(seasonNumber: nextSeason.seasonNumber, episodeNumber: 1)
    }

    /// Earliest regular-season episode not in `completed`. Nil when every episode is done.
    static func firstUnwatchedEpisode(
        in seasons: [TVSeasonSummary],
        completed: Set<TVEpisodeRef>
    ) -> TVEpisodeRef? {
        let regular = regularSeasons(seasons)
            .filter { $0.episodeCount > 0 }
            .sorted { $0.seasonNumber < $1.seasonNumber }
        for season in regular {
            for number in 1...season.episodeCount {
                let ref = TVEpisodeRef(seasonNumber: season.seasonNumber, episodeNumber: number)
                if !completed.contains(ref) {
                    return ref
                }
            }
        }
        return nil
    }

    /// Watched-row subtitle (“2 seasons” / “Complete”) from the frozen catalog, not live TMDB.
    var watchedSeasonCaption: String? {
        guard let catalogSnapshot else { return nil }
        let seasons = catalogSnapshot.filter { $0.seasonNumber > 0 && $0.episodeCount > 0 }
        let count = seasons.count
        if count == 0 { return "Complete" }
        if count == 1 { return "1 season" }
        return "\(count) seasons"
    }

    /// Marks one episode completed. Returns whether it was newly added.
    @discardableResult
    mutating func mark(
        seasonNumber: Int,
        episodeNumber: Int,
        title _: String? = nil
    ) -> Bool {
        guard seasonNumber > 0, episodeNumber > 0 else { return false }
        let ref = TVEpisodeRef(seasonNumber: seasonNumber, episodeNumber: episodeNumber)
        let inserted = !completedSet.contains(ref)
        if inserted {
            completed.append(ref)
            completed = Self.normalized(completed)
        }
        return inserted
    }

    mutating func unmark(seasonNumber: Int, episodeNumber: Int) {
        completed.removeAll {
            $0.seasonNumber == seasonNumber && $0.episodeNumber == episodeNumber
        }
        if completed.isEmpty {
            nextUp = nil
            nextUpTitle = nil
            catalogSnapshot = nil
        }
    }

    /// Clears every completed episode in a regular season. Returns how many were removed.
    @discardableResult
    mutating func unmarkSeason(seasonNumber: Int, episodeCount: Int) -> Int {
        guard seasonNumber > 0, episodeCount > 0 else { return 0 }
        let before = completed.count
        let range = 1...episodeCount
        completed.removeAll {
            $0.seasonNumber == seasonNumber && range.contains($0.episodeNumber)
        }
        if completed.isEmpty {
            nextUp = nil
            nextUpTitle = nil
            catalogSnapshot = nil
        }
        return before - completed.count
    }

    /// Marks every episode in a season. Returns how many were newly added.
    @discardableResult
    mutating func markSeason(
        seasonNumber: Int,
        episodeCount: Int,
        episodeTitles: [Int: String] = [:]
    ) -> Int {
        guard seasonNumber > 0, episodeCount > 0 else { return 0 }
        var newly = 0
        for number in 1...episodeCount {
            if mark(
                seasonNumber: seasonNumber,
                episodeNumber: number,
                title: episodeTitles[number]
            ) {
                newly += 1
            }
        }
        return newly
    }

    /// Marks every regular season. Returns how many episodes were newly added.
    @discardableResult
    mutating func markSeries(
        seasons: [TVSeasonSummary],
        episodeTitles: [TVEpisodeRef: String] = [:]
    ) -> Int {
        var newly = 0
        for season in Self.regularSeasons(seasons) where season.episodeCount > 0 {
            var titles: [Int: String] = [:]
            for number in 1...season.episodeCount {
                let ref = TVEpisodeRef(seasonNumber: season.seasonNumber, episodeNumber: number)
                if let title = episodeTitles[ref] {
                    titles[number] = title
                }
            }
            newly += markSeason(
                seasonNumber: season.seasonNumber,
                episodeCount: season.episodeCount,
                episodeTitles: titles
            )
        }
        return newly
    }

    func isSeasonComplete(seasonNumber: Int, episodeCount: Int) -> Bool {
        guard seasonNumber > 0, episodeCount > 0 else { return false }
        let set = completedSet
        return (1...episodeCount).allSatisfy { number in
            set.contains(TVEpisodeRef(seasonNumber: seasonNumber, episodeNumber: number))
        }
    }

    func isSeriesComplete(against seasons: [TVSeasonSummary]) -> Bool {
        let regular = Self.regularSeasons(seasons).filter { $0.episodeCount > 0 }
        guard !regular.isEmpty else { return false }
        return regular.allSatisfy { season in
            isSeasonComplete(seasonNumber: season.seasonNumber, episodeCount: season.episodeCount)
        }
    }

    /// Episodes still unmarked when completing a season (for confirm copy).
    func unmarkedCount(seasonNumber: Int, episodeCount: Int) -> Int {
        guard seasonNumber > 0, episodeCount > 0 else { return 0 }
        let set = completedSet
        return (1...episodeCount).filter { number in
            !set.contains(TVEpisodeRef(seasonNumber: seasonNumber, episodeNumber: number))
        }.count
    }

    func unmarkedCount(against seasons: [TVSeasonSummary]) -> Int {
        Self.regularSeasons(seasons)
            .filter { $0.episodeCount > 0 }
            .reduce(0) { partial, season in
                partial + unmarkedCount(
                    seasonNumber: season.seasonNumber,
                    episodeCount: season.episodeCount
                )
            }
    }

    /// Remember today’s TMDB shape so we can detect growth later (see `hasNewCatalogContent`).
    mutating func freezeCatalogSnapshot(from seasons: [TVSeasonSummary]) {
        catalogSnapshot = Self.catalogCounts(from: seasons)
    }

    /// Drop the freeze when the series leaves Watched (back to In Progress, or cleared).
    mutating func clearCatalogSnapshot() {
        catalogSnapshot = nil
    }

    /// True when live TMDB has more episodes in a regular season than the frozen snapshot.
    func hasNewCatalogContent(against seasons: [TVSeasonSummary]) -> Bool {
        guard let catalogSnapshot else { return false }
        let prior = Dictionary(
            uniqueKeysWithValues: catalogSnapshot.map { ($0.seasonNumber, $0.episodeCount) }
        )
        for season in Self.regularSeasons(seasons) where season.episodeCount > 0 {
            let previous = prior[season.seasonNumber] ?? 0
            if season.episodeCount > previous {
                return true
            }
        }
        return false
    }

    static func catalogCounts(from seasons: [TVSeasonSummary]) -> [TVCatalogSeasonCount] {
        regularSeasons(seasons)
            .filter { $0.episodeCount > 0 }
            .map { TVCatalogSeasonCount(seasonNumber: $0.seasonNumber, episodeCount: $0.episodeCount) }
            .sorted { $0.seasonNumber < $1.seasonNumber }
    }

    static func regularSeasons(_ seasons: [TVSeasonSummary]) -> [TVSeasonSummary] {
        seasons.filter { $0.seasonNumber > 0 }
    }

    private static func normalized(_ completed: [TVEpisodeRef]) -> [TVEpisodeRef] {
        Array(Set(completed.filter { $0.seasonNumber > 0 && $0.episodeNumber > 0 })).sorted()
    }
}

/// Prior episode ledger to restore when undoing a watch mutation’s list toast.
struct TVWatchUndo: Sendable, Equatable {
    let seriesID: Int
    /// Nil means there was no progress before the action — undo clears the series ledger.
    let priorState: TVSeriesWatchState?
}

/// Result of a watch mutation, including the list membership change to toast (if any).
struct TVWatchOutcome: Sendable, Equatable {
    let state: TVSeriesWatchState
    let membershipChange: MembershipChange?
    /// Episodes newly marked in this action (for confirm UI accounting).
    let episodesNewlyMarked: Int
    /// When non-nil, toast Undo must restore this ledger before reversing list membership.
    let watchUndo: TVWatchUndo?

    init(
        state: TVSeriesWatchState,
        membershipChange: MembershipChange?,
        episodesNewlyMarked: Int,
        watchUndo: TVWatchUndo? = nil
    ) {
        self.state = state
        self.membershipChange = membershipChange
        self.episodesNewlyMarked = episodesNewlyMarked
        self.watchUndo = watchUndo
    }
}
