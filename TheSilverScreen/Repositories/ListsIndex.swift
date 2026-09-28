//
//  ListsIndex.swift
//  TheSilverScreen
//

import Foundation

/// Lists and membership the row icon and add menu read without another fetch.
///
/// `ListsRepository` publishes here after every load and save. The icon checks
/// whether a title is on any list. Menu rows check a single list.
@Observable
@MainActor
final class ListsIndex {
    private(set) var lists: [LibraryList] = []
    /// Item keys present on at least one list.
    private(set) var listedItemKeys: Set<String> = []
    /// List id to the item keys saved on that list.
    private(set) var membersByList: [UUID: Set<String>] = [:]

    func lists(in segment: LibrarySegment) -> [LibraryList] {
        LibrarySnapshot(lists: lists, entries: []).lists(in: segment)
    }

    func contains(_ itemKey: String) -> Bool {
        listedItemKeys.contains(itemKey)
    }

    func contains(_ itemKey: String, listID: UUID) -> Bool {
        membersByList[listID, default: []].contains(itemKey)
    }

    func replace(with snapshot: LibrarySnapshot) {
        lists = snapshot.lists
        var members: [UUID: Set<String>] = [:]
        var keys = Set<String>()
        for entry in snapshot.entries {
            members[entry.listID, default: []].insert(entry.itemKey)
            keys.insert(entry.itemKey)
        }
        membersByList = members
        listedItemKeys = keys
    }
}
