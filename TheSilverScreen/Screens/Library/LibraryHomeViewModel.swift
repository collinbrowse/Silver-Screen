//
//  LibraryHomeViewModel.swift
//  TheSilverScreen
//

import Foundation

/// Library tab root: one segment, then the lists in it. Search matches a list name or a member title.
@Observable
@MainActor
final class LibraryHomeViewModel {
    private(set) var state: LoadState<LibrarySnapshot> = .idle
    var segment: LibrarySegment = .moviesAndTV
    var searchText: String = ""
    var nameError: String?

    private let lists: ListsRepository

    init(lists: ListsRepository) {
        self.lists = lists
    }

    var displayedLists: [LibraryList] {
        guard case .loaded(let snapshot, _) = state else { return [] }
        return LibraryQuery.lists(in: segment, snapshot: snapshot, matching: searchText)
    }

    /// Dragging is off while Find list is hiding a custom row.
    var canReorderLists: Bool {
        guard case .loaded(let snapshot, _) = state else { return false }
        let allCustom = snapshot.lists(in: segment).filter { !$0.isSystem }
        let shownCustom = displayedLists.filter { !$0.isSystem }
        return !allCustom.isEmpty && shownCustom.count == allCustom.count
    }

    func membershipCount(for listID: UUID) -> Int {
        guard case .loaded(let snapshot, _) = state else { return 0 }
        return snapshot.entries.filter { $0.listID == listID }.count
    }

    func load() async {
        if case .loaded(let current, _) = state {
            state = .loaded(current, activity: .refreshing)
        } else if case .empty = state {
            // Keep the empty state while the next read is in flight.
        } else {
            state = .loading
        }
        do {
            let snapshot = try await lists.snapshot()
            state = .loaded(snapshot)
        } catch is CancellationError {
            return
        } catch let error as AppError {
            fail(with: error)
        } catch {
            fail(with: .unknown)
        }
    }

    /// Creates an empty list in the current segment. Name rejections leave the dialog open.
    func createList(named raw: String) async -> Bool {
        do {
            _ = try await lists.createList(name: raw, segment: segment)
            nameError = nil
            await load()
            return true
        } catch let error as ListEditError where error.isNameRejection {
            nameError = error.message
            return false
        } catch is CancellationError {
            return false
        } catch {
            fail(with: .persistence)
            return false
        }
    }

    func rename(_ list: LibraryList, to raw: String) async -> Bool {
        do {
            try await lists.renameList(id: list.id, name: raw)
            nameError = nil
            await load()
            return true
        } catch let error as ListEditError where error.isNameRejection {
            nameError = error.message
            return false
        } catch is CancellationError {
            return false
        } catch {
            fail(with: .persistence)
            return false
        }
    }

    func delete(_ list: LibraryList) async {
        do {
            try await lists.deleteList(id: list.id)
            await load()
        } catch is CancellationError {
            return
        } catch {
            fail(with: .persistence)
        }
    }

    func moveLists(from source: IndexSet, to destination: Int) async {
        guard canReorderLists else { return }
        do {
            try await lists.moveLists(in: segment, fromOffsets: source, toOffset: destination)
            await load()
        } catch is CancellationError {
            return
        } catch {
            fail(with: .persistence)
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
