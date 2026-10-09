//
//  LibraryDetailViewModel.swift
//  TheSilverScreen
//
//  One list. Watched and Watchlist sort from the snapshot saved at add time.
//  Every other list keeps the order the user arranged.
//

import Foundation

@Observable
@MainActor
final class LibraryDetailViewModel {
    private(set) var state: LoadState<LibraryListDetail> = .idle
    var searchText: String = ""
    /// All / Movies / TV. People lists ignore this.
    var mediaFilter: TitleMediaFilter = .all
    private(set) var userScores: [String: SavedUserScore] = [:]
    /// TV progress line under a row title (In Progress episode line or Watched season count).
    private(set) var progressCaptions: [String: String] = [:]
    /// Last completed episode per In Progress TV row — used to open that season scrolled to it.
    private(set) var progressAnchors: [String: TVEpisodeRef] = [:]

    let listID: UUID
    private let lists: ListsRepository
    private let annotations: AnnotationsRepository
    private let tvWatch: TVWatchRepository?

    init(
        listID: UUID,
        lists: ListsRepository,
        annotations: AnnotationsRepository,
        tvWatch: TVWatchRepository? = nil
    ) {
        self.listID = listID
        self.lists = lists
        self.annotations = annotations
        self.tvWatch = tvWatch
    }

    var displayedEntries: [ListEntry] {
        guard case .loaded(let detail, _) = state else { return [] }
        let filter = detail.list.segment == .people ? TitleMediaFilter.all : mediaFilter
        return LibraryQuery.entries(detail.entries, matching: searchText, filter: filter)
    }

    /// Dragging is off for system lists and while a filter is hiding rows.
    var allowsReorder: Bool {
        guard case .loaded(let detail, _) = state, detail.list.system == nil else { return false }
        return !detail.entries.isEmpty && displayedEntries.count == detail.entries.count
    }

    func load() async {
        if case .loaded(let current, _) = state {
            state = .loaded(current, activity: .refreshing)
        } else if case .empty = state {
        } else {
            state = .loading
        }
        do {
            let snapshot = try await lists.snapshot()
            guard let list = snapshot.lists.first(where: { $0.id == listID }) else {
                state = .empty
                userScores = [:]
                progressCaptions = [:]
                progressAnchors = [:]
                return
            }
            let entries = LibraryOrdering.displayed(snapshot.entries, list: list)
            state = .loaded(LibraryListDetail(list: list, entries: entries))
            await reloadScores(entries)
            await reloadProgressCaptions(list: list, entries: entries)
        } catch is CancellationError {
            return
        } catch let error as AppError {
            fail(with: error)
        } catch {
            fail(with: .unknown)
        }
    }

    func setSort(_ sort: LibrarySort) async {
        do {
            try await lists.setSort(sort, listID: listID)
            await load()
        } catch is CancellationError {
            return
        } catch {
            fail(with: .persistence)
        }
    }

    func remove(_ entry: ListEntry) async -> MembershipChange? {
        do {
            let change = try await lists.remove(itemKey: entry.itemKey, listID: listID)
            await load()
            return change
        } catch is CancellationError {
            return nil
        } catch {
            fail(with: .persistence)
            return nil
        }
    }

    func moveEntries(from source: IndexSet, to destination: Int) async {
        guard allowsReorder else { return }
        do {
            try await lists.moveEntries(listID: listID, fromOffsets: source, toOffset: destination)
            await load()
        } catch is CancellationError {
            return
        } catch {
            fail(with: .persistence)
        }
    }

    /// Destination for a list row. In Progress TV opens the season of the last watched episode
    /// (Next up sits on the row below once scrolled).
    func route(for entry: ListEntry) -> Route {
        switch entry.kind {
            case .movie:
                return .movieDetail(id: entry.itemID)
            case .person:
                return .person(id: entry.itemID)
            case .tv:
                if case .loaded(let detail, _) = state,
                   detail.list.system == .inProgress,
                   let last = progressAnchors[entry.itemKey] {
                    return .tvSeason(
                        seriesID: entry.itemID,
                        seriesName: entry.title,
                        seasonNumber: last.seasonNumber,
                        seriesSnapshot: SeriesListSnapshot(entry: entry),
                        scrollToEpisodeNumber: last.episodeNumber
                    )
                }
                return .tvSeries(id: entry.itemID)
        }
    }

    private func reloadScores(_ entries: [ListEntry]) async {
        let scores = await annotations.formattedScores()
        var mapped: [String: SavedUserScore] = [:]
        for entry in entries {
            let key: AnnotationKey? = switch entry.kind {
                case .movie: .movie(entry.itemID)
                case .tv: .series(entry.itemID)
                case .person: nil
            }
            if let key, let score = scores[key] {
                mapped[entry.itemKey] = score
            }
        }
        userScores = mapped
    }

    private func reloadProgressCaptions(list: LibraryList, entries: [ListEntry]) async {
        guard let tvWatch else {
            progressCaptions = [:]
            progressAnchors = [:]
            return
        }
        let tvEntries = entries.filter { $0.kind == .tv }
        guard !tvEntries.isEmpty else {
            progressCaptions = [:]
            progressAnchors = [:]
            return
        }
        do {
            let states = try await tvWatch.states(for: tvEntries.map(\.itemID))
            var captions: [String: String] = [:]
            var anchors: [String: TVEpisodeRef] = [:]
            for entry in tvEntries {
                guard let state = states[entry.itemID] else { continue }
                switch list.system {
                    case .inProgress:
                        if let subtitle = state.progressSubtitle {
                            captions[entry.itemKey] = subtitle
                        }
                        if let last = state.lastCompleted {
                            anchors[entry.itemKey] = last
                        }
                    case .watched:
                        if let caption = state.watchedSeasonCaption {
                            captions[entry.itemKey] = caption
                        } else {
                            captions[entry.itemKey] = "Complete"
                        }
                    case .watchlist, nil:
                        break
                }
            }
            progressCaptions = captions
            progressAnchors = anchors
        } catch {
            progressCaptions = [:]
            progressAnchors = [:]
        }
    }

    private func fail(with error: AppError) {
        if case .loaded(let current, _) = state {
            state = .loaded(current, activity: .failed(error))
        } else {
            state = .failed(error)
        }
    }
}

/// A list and its entries already in display order.
struct LibraryListDetail: Sendable, Equatable {
    var list: LibraryList
    var entries: [ListEntry]
}
