//
//  ListChangeNotice.swift
//  TheSilverScreen
//
//  Short confirmation after a title is added to or removed from a list.
//  Undo reverses that one change, including a Watchlist row displaced by Watched.
//

import Foundation

@Observable
@MainActor
final class ListChangeNotice {
    private(set) var message: String?
    private var change: MembershipChange?
    private var lists: ListsRepository?
    private var generation = 0

    func show(_ change: MembershipChange, using lists: ListsRepository) {
        guard let message = change.confirmation else { return }
        self.change = change
        self.lists = lists
        self.message = message
        generation += 1
        let token = generation
        Task {
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled, generation == token else { return }
            clear()
        }
    }

    func undo() async {
        guard let change, let lists else { return }
        clear()
        try? await lists.undo(change)
    }

    private func clear() {
        message = nil
        change = nil
        lists = nil
    }
}
