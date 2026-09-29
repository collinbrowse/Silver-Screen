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

    let listID: UUID
    private let lists: ListsRepository
    private let annotations: AnnotationsRepository

    init(listID: UUID, lists: ListsRepository, annotations: AnnotationsRepository) {
        self.listID = listID
        self.lists = lists
        self.annotations = annotations
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
                return
            }
            let entries = LibraryOrdering.displayed(snapshot.entries, list: list)
            state = .loaded(LibraryListDetail(list: list, entries: entries))
            await reloadScores(entries)
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
