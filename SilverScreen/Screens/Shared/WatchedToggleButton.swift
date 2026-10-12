//
//  WatchedToggleButton.swift
//  SilverScreen
//
//  Eye control that marks a title watched or not. Watched is never chosen from
//  the + list menu — this toggle (and TV episode progress / rating sync) owns it.
//  `onFailure` is last so a trailing closure cannot bind to the success path.
//

import SwiftUI

struct WatchedToggleButton: View {
    let draft: ListItemDraft
    let lists: ListsRepository
    @Bindable var index: ListsIndex
    /// Required to mark or clear a TV series through the episode ledger.
    var tvWatch: TVWatchRepository? = nil
    /// Used to load season counts when marking a TV series from a row.
    var shows: TVRepository? = nil
    /// When already known (series detail), avoids a network fetch.
    var seasons: [TVSeasonSummary]? = nil
    /// Compact chrome for list rows vs plain toolbar icon.
    var chrome: Bool = true
    /// When set, drives the filled eye (series detail ledger completeness) instead of
    /// Watched-list membership alone.
    var isWatchedOverride: Bool? = nil
    /// Called after a successful watch toggle (membership and/or episode ledger).
    var onToggleComplete: () -> Void = {}
    /// Trailing-closure friendly — keep this parameter last.
    var onFailure: () -> Void = {}

    @Environment(ListChangeNotice.self) private var notice
    @State private var confirmEpisodeCount: Int?
    @State private var pendingSeasons: [TVSeasonSummary]?
    @State private var clearConfirmCount: Int?
    /// Kept separate from payload state so alert dismissal cannot wipe seasons
    /// before the confirm button captures them.
    @State private var isMarkConfirmPresented = false
    @State private var isClearConfirmPresented = false
    @State private var optimisticWatched: Bool?

    private var isWatched: Bool {
        optimisticWatched ?? isWatchedOverride ?? index.isOnWatched(draft.itemKey)
    }

    var body: some View {
        Button {
            Task { await toggle() }
        } label: {
            label
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(isWatched ? "Mark \(draft.title) not watched" : "Mark \(draft.title) watched")
        .accessibilityValue(isWatched ? "Watched" : "Not watched")
        .alert(TVWatchConfirm.seriesTitle, isPresented: $isMarkConfirmPresented) {
            Button("Cancel", role: .cancel) {
                confirmEpisodeCount = nil
                pendingSeasons = nil
            }
            Button(TVWatchConfirm.confirmButtonTitle) {
                confirmMarkSeries()
            }
        } message: {
            if let count = confirmEpisodeCount {
                Text(TVWatchConfirm.message(episodeCount: count))
            }
        }
        .alert(TVWatchConfirm.clearSeriesTitle, isPresented: $isClearConfirmPresented) {
            Button("Cancel", role: .cancel) {
                clearConfirmCount = nil
            }
            Button(TVWatchConfirm.clearButtonTitle, role: .destructive) {
                confirmClearSeries()
            }
        } message: {
            if let count = clearConfirmCount {
                Text(TVWatchConfirm.clearMessage(episodeCount: count))
            }
        }
    }

    @ViewBuilder
    private var label: some View {
        if chrome {
            ZStack {
                Circle()
                    .fill(Color.black.opacity(0.45))
                    .frame(width: 36, height: 36)
                Image(systemName: isWatched ? "eye.fill" : "eye")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(isWatched ? DesignTheme.accent : Color.white)
            }
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
        } else {
            Image(systemName: isWatched ? "eye.fill" : "eye")
                .foregroundStyle(isWatched ? DesignTheme.accent : DesignTheme.textPrimary)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
    }

    private func toggle() async {
        do {
            switch draft.kind {
                case .movie:
                    optimisticWatched = !isWatched
                    do {
                        let change = try await lists.toggleWatched(draft)
                        notice.show(change, using: lists)
                        optimisticWatched = nil
                        onToggleComplete()
                    } catch {
                        optimisticWatched = nil
                        throw error
                    }
                case .tv:
                    guard let tvWatch else {
                        onFailure()
                        return
                    }
                    if isWatched {
                        let count = try await tvWatch.completedEpisodeCount(seriesID: draft.id)
                        if count > 1 {
                            clearConfirmCount = count
                            isClearConfirmPresented = true
                        } else {
                            await performClearSeries()
                        }
                    } else {
                        let seasons = try await resolveSeasons()
                        let unmarked = try await tvWatch.unmarkedEpisodeCount(
                            seriesID: draft.id,
                            seasons: seasons
                        )
                        if unmarked == 0 {
                            await performMarkSeries(seasons: seasons)
                        } else {
                            pendingSeasons = seasons
                            confirmEpisodeCount = unmarked
                            isMarkConfirmPresented = true
                        }
                    }
                case .person:
                    onFailure()
            }
        } catch is CancellationError {
            return
        } catch {
            onFailure()
        }
    }

    /// Captures seasons synchronously so alert dismissal cannot nil them first.
    private func confirmMarkSeries() {
        guard let seasons = pendingSeasons else { return }
        pendingSeasons = nil
        confirmEpisodeCount = nil
        isMarkConfirmPresented = false
        Task { await performMarkSeries(seasons: seasons) }
    }

    private func confirmClearSeries() {
        clearConfirmCount = nil
        isClearConfirmPresented = false
        Task { await performClearSeries() }
    }

    private func performClearSeries() async {
        guard let tvWatch else {
            onFailure()
            return
        }
        optimisticWatched = false
        do {
            let outcome = try await tvWatch.clearSeries(
                seriesID: draft.id,
                draft: draft
            )
            if let change = outcome.membershipChange, change.confirmation != nil {
                notice.show(
                    change,
                    using: lists,
                    tvWatch: tvWatch,
                    watchUndo: outcome.watchUndo
                )
            }
            optimisticWatched = nil
            onToggleComplete()
        } catch is CancellationError {
            optimisticWatched = nil
            return
        } catch {
            optimisticWatched = nil
            onFailure()
        }
    }

    private func performMarkSeries(seasons: [TVSeasonSummary]) async {
        guard let tvWatch else {
            onFailure()
            return
        }
        optimisticWatched = true
        do {
            let outcome = try await tvWatch.markSeries(
                seriesID: draft.id,
                seasons: seasons,
                draft: draft
            )
            if let change = outcome.membershipChange, change.confirmation != nil {
                notice.show(
                    change,
                    using: lists,
                    ratingKey: .series(draft.id),
                    tvWatch: tvWatch,
                    watchUndo: outcome.watchUndo
                )
            }
            optimisticWatched = nil
            onToggleComplete()
        } catch is CancellationError {
            optimisticWatched = nil
            return
        } catch {
            optimisticWatched = nil
            onFailure()
        }
    }

    private func resolveSeasons() async throws -> [TVSeasonSummary] {
        if let seasons { return seasons }
        guard let shows else { throw AppError.unknown }
        let detail = try await shows.series(id: draft.id)
        return detail.seasons
    }
}
