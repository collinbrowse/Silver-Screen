//
//  TVWatchReconcile.swift
//  TheSilverScreen
//
//  Cold-launch pass over Watched TV that still carries a catalog snapshot.
//  For each candidate, fetch live TMDB seasons and ask TVWatchRepository to
//  reopen In Progress when the catalog grew (new season or more episodes).
//  Never blocks launch UI; failures are logged only.
//

import Foundation

enum TVWatchReconcile {

    /// Background reconcile for series that finished watching (have a frozen catalog).
    /// Failures are logged; launch is never blocked.
    static func refreshWatchedCatalogs(
        tvWatch: TVWatchRepository,
        shows: TVRepository,
        lists: ListsRepository,
        listChanges: ListChangeNotice?,
        logger: any AppLogging
    ) async {
        // Only states with a freeze are Watched-and-complete candidates.
        let candidates: [TVSeriesWatchState]
        do {
            candidates = try await tvWatch.statesWithCatalogSnapshot()
        } catch is CancellationError {
            return
        } catch {
            logger.error("TV watch reconcile could not read progress", category: .persistence)
            return
        }
        guard !candidates.isEmpty else { return }

        for state in candidates {
            if Task.isCancelled { return }
            do {
                let detail = try await shows.series(id: state.seriesID)
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
}
