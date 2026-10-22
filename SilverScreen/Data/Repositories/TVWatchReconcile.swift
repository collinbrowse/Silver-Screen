//
//  TVWatchReconcile.swift
//  SilverScreen
//
//  Cold-launch pass over Watched TV that still carries a catalog snapshot.
//  For each candidate still on Watched, fetch live TMDB seasons and ask
//  TVWatchRepository to reopen In Progress when the catalog grew (new season
//  or more episodes). Never blocks launch UI; failures are logged only.
//

import Foundation

enum TVWatchReconcile {
    /// Caps parallel TMDB fetches so a large Watched library cannot stampede the API.
    private static let maxConcurrentFetches = 4

    /// Background reconcile for series that finished watching (have a frozen catalog)
    /// and are still on Watched. Failures are logged; launch is never blocked.
    static func refreshWatchedCatalogs(
        tvWatch: TVWatchRepository,
        shows: TVRepository,
        lists: ListsRepository,
        listChanges: ListChangeNotice?,
        logger: any AppLogging
    ) async {
        let watchedSeriesIDs: Set<Int>
        do {
            let snapshot = try await lists.snapshot()
            guard let watched = snapshot.list(.watched) else { return }
            watchedSeriesIDs = Set(
                snapshot.entries.compactMap { entry in
                    guard entry.listID == watched.id, entry.kind == .tv else { return nil }
                    return entry.itemID
                }
            )
        } catch is CancellationError {
            return
        } catch {
            logger.error("TV watch reconcile could not read lists", category: .persistence)
            return
        }
        guard !watchedSeriesIDs.isEmpty else { return }

        let candidates: [TVSeriesWatchState]
        do {
            candidates = try await tvWatch.statesWithCatalogSnapshot()
                .filter { watchedSeriesIDs.contains($0.seriesID) }
        } catch is CancellationError {
            return
        } catch {
            logger.error("TV watch reconcile could not read progress", category: .persistence)
            return
        }
        guard !candidates.isEmpty else { return }

        var index = 0
        await withTaskGroup(of: Void.self) { group in
            func enqueueNext() {
                guard index < candidates.count else { return }
                let state = candidates[index]
                index += 1
                group.addTask {
                    await reconcileOne(
                        state: state,
                        tvWatch: tvWatch,
                        shows: shows,
                        lists: lists,
                        listChanges: listChanges,
                        logger: logger
                    )
                }
            }

            let initial = min(maxConcurrentFetches, candidates.count)
            for _ in 0..<initial {
                enqueueNext()
            }
            for await _ in group {
                if Task.isCancelled {
                    group.cancelAll()
                    return
                }
                enqueueNext()
            }
        }
    }

    private static func reconcileOne(
        state: TVSeriesWatchState,
        tvWatch: TVWatchRepository,
        shows: TVRepository,
        lists: ListsRepository,
        listChanges: ListChangeNotice?,
        logger: any AppLogging
    ) async {
        if Task.isCancelled { return }
        do {
            let detail = try await shows.seriesCatalog(id: state.seriesID)
            let outcome = try await tvWatch.reconcileCatalog(
                seriesID: state.seriesID,
                seasons: detail.seasons,
                draft: detail.listItem()
            )
            if let change = outcome?.membershipChange, let listChanges {
                await MainActor.run {
                    listChanges.show(change, using: lists)
                }
            }
        } catch is CancellationError {
            return
        } catch {
            logger.error(
                "TV watch reconcile failed for series \(state.seriesID)",
                category: .networking
            )
        }
    }
}
