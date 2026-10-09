//
//  WatchedToggleButton.swift
//  TheSilverScreen
//
//  Eye control that marks a title watched or not. Watched is never chosen from
//  the + list menu — this toggle (and TV episode progress / rating sync) owns it.
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
    var onFailure: () -> Void = {}
    /// Called after a successful watch toggle (membership and/or episode ledger).
    var onToggleComplete: () -> Void = {}

    @Environment(ListChangeNotice.self) private var notice
    @State private var confirmEpisodeCount: Int?
    @State private var pendingSeasons: [TVSeasonSummary]?

    private var isWatched: Bool {
        index.isOnWatched(draft.itemKey)
    }

    private var isConfirmPresented: Binding<Bool> {
        Binding(
            get: { confirmEpisodeCount != nil },
            set: { presented in
                if !presented {
                    confirmEpisodeCount = nil
                    pendingSeasons = nil
                }
            }
        )
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
        .alert(TVWatchConfirm.seriesTitle, isPresented: isConfirmPresented) {
            Button("Cancel", role: .cancel) {}
            Button(TVWatchConfirm.confirmButtonTitle) {
                Task { await confirmMarkSeries() }
            }
        } message: {
            if let count = confirmEpisodeCount {
                Text(TVWatchConfirm.message(episodeCount: count))
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
                    let change = try await lists.toggleWatched(draft)
                    notice.show(change, using: lists)
                    onToggleComplete()
                case .tv:
                    guard let tvWatch else {
                        onFailure()
                        return
                    }
                    if isWatched {
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
                        onToggleComplete()
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

    private func confirmMarkSeries() async {
        guard let seasons = pendingSeasons else { return }
        pendingSeasons = nil
        confirmEpisodeCount = nil
        await performMarkSeries(seasons: seasons)
    }

    private func performMarkSeries(seasons: [TVSeasonSummary]) async {
        guard let tvWatch else {
            onFailure()
            return
        }
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
            onToggleComplete()
        } catch is CancellationError {
            return
        } catch {
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
