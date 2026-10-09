//
//  TVWatchRepository.swift
//  TheSilverScreen
//
//  Episode watch ledger for TV. Coordinates In Progress / Watched membership
//  when progress crosses series-complete boundaries.
//

import Foundation

actor TVWatchRepository {
    private let store: any TVWatchStore
    private let lists: ListsRepository
    private let logger: any AppLogging
    private var cached: [Int: TVSeriesWatchState]?
    private var loadTask: Task<[Int: TVSeriesWatchState], Error>?
    private var writeBarrier: Task<Void, Never>?

    init(store: any TVWatchStore, lists: ListsRepository, logger: any AppLogging) {
        self.store = store
        self.lists = lists
        self.logger = logger
    }

    func state(seriesID: Int) async throws -> TVSeriesWatchState? {
        try await loadCache()[seriesID]
    }

    func states(for seriesIDs: [Int]) async throws -> [Int: TVSeriesWatchState] {
        let cache = try await loadCache()
        var result: [Int: TVSeriesWatchState] = [:]
        for id in seriesIDs {
            if let state = cache[id] {
                result[id] = state
            }
        }
        return result
    }

    /// Finished series that still remember the TMDB shape they finished against —
    /// the only ones cold-launch reconcile needs to re-check.
    func statesWithCatalogSnapshot() async throws -> [TVSeriesWatchState] {
        try await loadCache().values.filter { $0.catalogSnapshot != nil }
    }

    func isEpisodeCompleted(seriesID: Int, seasonNumber: Int, episodeNumber: Int) async throws -> Bool {
        try await state(seriesID: seriesID)?
            .contains(seasonNumber: seasonNumber, episodeNumber: episodeNumber) == true
    }

    func unmarkedEpisodeCount(
        seriesID: Int,
        seasonNumber: Int,
        episodeCount: Int
    ) async throws -> Int {
        let existing = try await state(seriesID: seriesID)
            ?? TVSeriesWatchState(seriesID: seriesID)
        return existing.unmarkedCount(seasonNumber: seasonNumber, episodeCount: episodeCount)
    }

    func unmarkedEpisodeCount(seriesID: Int, seasons: [TVSeasonSummary]) async throws -> Int {
        let existing = try await state(seriesID: seriesID)
            ?? TVSeriesWatchState(seriesID: seriesID)
        return existing.unmarkedCount(against: seasons)
    }

    @discardableResult
    func markEpisode(
        seriesID: Int,
        seasonNumber: Int,
        episodeNumber: Int,
        title: String?,
        draft: ListItemDraft,
        seasons: [TVSeasonSummary],
        knownTitles: [TVEpisodeRef: String] = [:]
    ) async throws -> TVWatchOutcome {
        try await serializeWrite { [self] in
            let prior = try await loadCache()[seriesID]
            var state = prior ?? TVSeriesWatchState(seriesID: seriesID)
            let newly = state.mark(
                seasonNumber: seasonNumber,
                episodeNumber: episodeNumber,
                title: title
            ) ? 1 : 0
            var titles = knownTitles
            if let title {
                titles[TVEpisodeRef(seasonNumber: seasonNumber, episodeNumber: episodeNumber)] = title
            }
            state.refreshNextUp(against: seasons, episodeTitles: titles)
            Self.alignCatalogSnapshot(state: &state, seasons: seasons)
            try await commitLedger(state)
            let change = try await syncListsCompensating(
                state: &state,
                draft: draft,
                seasons: seasons,
                preferSilentComplete: newly > 0,
                prior: prior
            )
            return Self.makeOutcome(
                state: state,
                change: change,
                newly: newly,
                prior: prior
            )
        }
    }

    @discardableResult
    func unmarkEpisode(
        seriesID: Int,
        seasonNumber: Int,
        episodeNumber: Int,
        draft: ListItemDraft,
        seasons: [TVSeasonSummary]
    ) async throws -> TVWatchOutcome {
        try await serializeWrite { [self] in
            let prior = try await loadCache()[seriesID]
            var state = prior ?? TVSeriesWatchState(seriesID: seriesID)
            state.unmark(seasonNumber: seasonNumber, episodeNumber: episodeNumber)
            state.refreshNextUp(against: seasons)
            Self.alignCatalogSnapshot(state: &state, seasons: seasons)
            try await commitLedger(state)
            let change = try await syncListsCompensating(
                state: &state,
                draft: draft,
                seasons: seasons,
                preferSilentComplete: false,
                prior: prior
            )
            return Self.makeOutcome(
                state: state,
                change: change,
                newly: 0,
                prior: prior
            )
        }
    }

    @discardableResult
    func markSeason(
        seriesID: Int,
        seasonNumber: Int,
        episodeCount: Int,
        episodeTitles: [Int: String] = [:],
        draft: ListItemDraft,
        seasons: [TVSeasonSummary]
    ) async throws -> TVWatchOutcome {
        try await serializeWrite { [self] in
            let prior = try await loadCache()[seriesID]
            var state = prior ?? TVSeriesWatchState(seriesID: seriesID)
            let newly = state.markSeason(
                seasonNumber: seasonNumber,
                episodeCount: episodeCount,
                episodeTitles: episodeTitles
            )
            var titles: [TVEpisodeRef: String] = [:]
            for (number, name) in episodeTitles {
                titles[TVEpisodeRef(seasonNumber: seasonNumber, episodeNumber: number)] = name
            }
            state.refreshNextUp(against: seasons, episodeTitles: titles)
            Self.alignCatalogSnapshot(state: &state, seasons: seasons)
            try await commitLedger(state)
            let change = try await syncListsCompensating(
                state: &state,
                draft: draft,
                seasons: seasons,
                preferSilentComplete: true,
                prior: prior
            )
            return Self.makeOutcome(
                state: state,
                change: change,
                newly: newly,
                prior: prior
            )
        }
    }

    @discardableResult
    func unmarkSeason(
        seriesID: Int,
        seasonNumber: Int,
        episodeCount: Int,
        draft: ListItemDraft,
        seasons: [TVSeasonSummary]
    ) async throws -> TVWatchOutcome {
        try await serializeWrite { [self] in
            let prior = try await loadCache()[seriesID]
            var state = prior ?? TVSeriesWatchState(seriesID: seriesID)
            _ = state.unmarkSeason(seasonNumber: seasonNumber, episodeCount: episodeCount)
            state.refreshNextUp(against: seasons)
            Self.alignCatalogSnapshot(state: &state, seasons: seasons)
            try await commitLedger(state)
            let change = try await syncListsCompensating(
                state: &state,
                draft: draft,
                seasons: seasons,
                preferSilentComplete: false,
                prior: prior
            )
            return Self.makeOutcome(
                state: state,
                change: change,
                newly: 0,
                prior: prior
            )
        }
    }

    @discardableResult
    func markSeries(
        seriesID: Int,
        seasons: [TVSeasonSummary],
        episodeTitles: [TVEpisodeRef: String] = [:],
        draft: ListItemDraft
    ) async throws -> TVWatchOutcome {
        try await serializeWrite { [self] in
            let prior = try await loadCache()[seriesID]
            var state = prior ?? TVSeriesWatchState(seriesID: seriesID)
            let newly = state.markSeries(seasons: seasons, episodeTitles: episodeTitles)
            state.refreshNextUp(against: seasons, episodeTitles: episodeTitles)
            Self.alignCatalogSnapshot(state: &state, seasons: seasons)
            try await commitLedger(state)
            let change = try await syncListsCompensating(
                state: &state,
                draft: draft,
                seasons: seasons,
                preferSilentComplete: true,
                prior: prior
            )
            return Self.makeOutcome(
                state: state,
                change: change,
                newly: newly,
                prior: prior
            )
        }
    }

    /// Recomputes Next up from the catalog and persists when it changes (heals stale ledgers).
    @discardableResult
    func syncNextUp(
        seriesID: Int,
        seasons: [TVSeasonSummary],
        episodeTitles: [TVEpisodeRef: String] = [:]
    ) async throws -> TVSeriesWatchState? {
        try await serializeWrite { [self] in
            guard var state = try await loadCache()[seriesID] else { return nil }
            let priorNext = state.nextUp
            let priorTitle = state.nextUpTitle
            state.refreshNextUp(against: seasons, episodeTitles: episodeTitles)
            if state.nextUp != priorNext || state.nextUpTitle != priorTitle {
                try await persist(state)
            }
            return state
        }
    }

    /// Clears every completed episode and removes the series from Watched / In Progress.
    @discardableResult
    func clearSeries(seriesID: Int, draft: ListItemDraft) async throws -> TVWatchOutcome {
        try await serializeWrite { [self] in
            let prior = try await loadCache()[seriesID]
            try await removeState(seriesID: seriesID)
            var lastChange: MembershipChange?
            for kind in [SystemListKind.watched, .inProgress] {
                let snapshot = try await lists.snapshot()
                guard let list = snapshot.list(kind),
                      snapshot.entries.contains(where: {
                          $0.listID == list.id && $0.itemKey == draft.itemKey
                      }) else {
                    continue
                }
                lastChange = try await lists.remove(itemKey: draft.itemKey, listID: list.id)
            }
            let empty = TVSeriesWatchState(seriesID: seriesID)
            return Self.makeOutcome(
                state: empty,
                change: lastChange,
                newly: 0,
                prior: prior
            )
        }
    }

    /// Restores the episode ledger captured before a toasted watch mutation (Story 6 Undo).
    func restore(_ undo: TVWatchUndo) async throws {
        try await serializeWrite { [self] in
            if let prior = undo.priorState, !prior.completed.isEmpty {
                try await persist(prior)
            } else {
                try await removeState(seriesID: undo.seriesID)
            }
        }
    }

    /// If `seasons` grew past the frozen catalog snapshot, clear the freeze, refresh
    /// Next up, and soft-move the series from Watched back to In Progress.
    @discardableResult
    func reconcileCatalog(
        seriesID: Int,
        seasons: [TVSeasonSummary],
        draft: ListItemDraft
    ) async throws -> TVWatchOutcome? {
        try await serializeWrite { [self] in
            guard var state = try await loadCache()[seriesID] else { return nil }
            guard state.hasNewCatalogContent(against: seasons) else { return nil }
            let prior = state
            state.clearCatalogSnapshot()
            state.refreshNextUp(against: seasons)
            try await persist(state)
            let change: MembershipChange
            do {
                change = try await lists.addToInProgress(
                    draft,
                    messageOverride: "\(draft.title) moved to In Progress"
                )
            } catch {
                try await restoreLedger(prior)
                throw error
            }
            return Self.makeOutcome(
                state: state,
                change: change.action == .unchanged ? nil : change,
                newly: 0,
                prior: prior
            )
        }
    }

    // MARK: - List sync

    /// Freeze or clear the catalog snapshot before persist so Watched rows keep captions
    /// and cold-launch reconcile still sees a frozen TMDB shape.
    private nonisolated static func alignCatalogSnapshot(
        state: inout TVSeriesWatchState,
        seasons: [TVSeasonSummary]
    ) {
        if state.completed.isEmpty {
            state.clearCatalogSnapshot()
        } else if state.isSeriesComplete(against: seasons) {
            state.freezeCatalogSnapshot(from: seasons)
        } else {
            state.clearCatalogSnapshot()
        }
    }

    /// Keeps Library membership aligned with episode completion.
    /// Catalog snapshot must already match completion via `alignCatalogSnapshot`.
    private func syncLists(
        state: inout TVSeriesWatchState,
        draft: ListItemDraft,
        seasons: [TVSeasonSummary],
        preferSilentComplete: Bool
    ) async throws -> MembershipChange? {
        // No completed episodes → leave system lists; snapshot only applies to Watched.
        if state.completed.isEmpty {
            return try await removeFromSystemLists(itemKey: draft.itemKey)
        }

        // Caught up vs current TMDB → Watched (snapshot already frozen before persist).
        if state.isSeriesComplete(against: seasons) {
            let message = preferSilentComplete ? "\(draft.title) moved to Watched" : nil
            let change = try await lists.addToWatched(draft, messageOverride: message)
            // Never toast a no-op membership write.
            return change.action == .unchanged ? nil : change
        }

        // Still watching → In Progress.
        let change = try await lists.addToInProgress(draft)
        return change.action == .unchanged ? nil : change
    }

    /// Persist ledger first, then sync lists; roll the ledger back if list sync fails.
    private func syncListsCompensating(
        state: inout TVSeriesWatchState,
        draft: ListItemDraft,
        seasons: [TVSeasonSummary],
        preferSilentComplete: Bool,
        prior: TVSeriesWatchState?
    ) async throws -> MembershipChange? {
        do {
            return try await syncLists(
                state: &state,
                draft: draft,
                seasons: seasons,
                preferSilentComplete: preferSilentComplete
            )
        } catch {
            try await restoreLedger(prior, seriesID: state.seriesID)
            throw error
        }
    }

    private func removeFromSystemLists(itemKey: String) async throws -> MembershipChange? {
        var lastChange: MembershipChange?
        for kind in [SystemListKind.watched, .inProgress] {
            let snapshot = try await lists.snapshot()
            guard let list = snapshot.list(kind),
                  snapshot.entries.contains(where: {
                      $0.listID == list.id && $0.itemKey == itemKey
                  }) else {
                continue
            }
            lastChange = try await lists.remove(itemKey: itemKey, listID: list.id)
        }
        return lastChange
    }

    private nonisolated static func makeOutcome(
        state: TVSeriesWatchState,
        change: MembershipChange?,
        newly: Int,
        prior: TVSeriesWatchState?
    ) -> TVWatchOutcome {
        let undo: TVWatchUndo? = change != nil
            ? TVWatchUndo(seriesID: state.seriesID, priorState: prior)
            : nil
        return TVWatchOutcome(
            state: state,
            membershipChange: change,
            episodesNewlyMarked: newly,
            watchUndo: undo
        )
    }

    // MARK: - Persistence

    private func commitLedger(_ state: TVSeriesWatchState) async throws {
        if state.completed.isEmpty {
            try await removeState(seriesID: state.seriesID)
        } else {
            try await persist(state)
        }
    }

    private func restoreLedger(_ prior: TVSeriesWatchState?, seriesID: Int? = nil) async throws {
        if let prior, !prior.completed.isEmpty {
            try await persist(prior)
        } else if let seriesID {
            try await removeState(seriesID: seriesID)
        } else if let prior {
            try await removeState(seriesID: prior.seriesID)
        }
    }

    private func loadCache() async throws -> [Int: TVSeriesWatchState] {
        if let cached { return cached }
        if let loadTask {
            return try await loadTask.value
        }
        let task = Task { try await self.performLoad() }
        loadTask = task
        do {
            let value = try await task.value
            loadTask = nil
            return value
        } catch {
            loadTask = nil
            throw error
        }
    }

    private func performLoad() async throws -> [Int: TVSeriesWatchState] {
        do {
            let states = try await store.load()
            let (map, hadDuplicates) = Self.dedupe(states)
            cached = map
            if hadDuplicates {
                // Rewrite a merged ledger so the next launch cannot crash on uniqueKeys.
                try await save(map)
            }
            return map
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            logger.error("TV watch progress load failed", category: .persistence)
            throw AppError.persistence
        }
    }

    /// Merges duplicate `seriesID` records (union of completed episodes; prefer a snapshot).
    private static func dedupe(
        _ states: [TVSeriesWatchState]
    ) -> (map: [Int: TVSeriesWatchState], hadDuplicates: Bool) {
        var map: [Int: TVSeriesWatchState] = [:]
        var hadDuplicates = false
        for state in states {
            if let existing = map[state.seriesID] {
                hadDuplicates = true
                map[state.seriesID] = merge(existing, state)
            } else {
                map[state.seriesID] = state
            }
        }
        return (map, hadDuplicates)
    }

    private static func merge(
        _ lhs: TVSeriesWatchState,
        _ rhs: TVSeriesWatchState
    ) -> TVSeriesWatchState {
        var merged = lhs
        for ref in rhs.completed {
            merged.mark(seasonNumber: ref.seasonNumber, episodeNumber: ref.episodeNumber)
        }
        if merged.catalogSnapshot == nil {
            merged.catalogSnapshot = rhs.catalogSnapshot
        } else if let right = rhs.catalogSnapshot, let left = merged.catalogSnapshot {
            var bySeason = Dictionary(
                uniqueKeysWithValues: left.map { ($0.seasonNumber, $0.episodeCount) }
            )
            for season in right {
                bySeason[season.seasonNumber] = max(
                    bySeason[season.seasonNumber] ?? 0,
                    season.episodeCount
                )
            }
            merged.catalogSnapshot = bySeason
                .map { TVCatalogSeasonCount(seasonNumber: $0.key, episodeCount: $0.value) }
                .sorted { $0.seasonNumber < $1.seasonNumber }
        }
        if merged.nextUp == nil {
            merged.nextUp = rhs.nextUp
            merged.nextUpTitle = rhs.nextUpTitle
        }
        return merged
    }

    private func persist(_ state: TVSeriesWatchState) async throws {
        var map = try await loadCache()
        map[state.seriesID] = state
        try await save(map)
    }

    private func removeState(seriesID: Int) async throws {
        var map = try await loadCache()
        map.removeValue(forKey: seriesID)
        try await save(map)
    }

    private func save(_ map: [Int: TVSeriesWatchState]) async throws {
        do {
            let ordered = map.values.sorted { $0.seriesID < $1.seriesID }
            try await store.save(ordered)
            cached = map
        } catch {
            logger.error("TV watch progress save failed", category: .persistence)
            throw AppError.persistence
        }
    }

    private func serializeWrite<T: Sendable>(
        _ work: @Sendable @escaping () async throws -> T
    ) async throws -> T {
        let previous = writeBarrier
        let task = Task<T, Error> {
            _ = await previous?.value
            return try await work()
        }
        writeBarrier = Task { _ = try? await task.value }
        return try await task.value
    }
}
