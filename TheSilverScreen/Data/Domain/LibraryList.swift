//
//  LibraryList.swift
//  TheSilverScreen
//
//  A personal library of lists. Watched and Watchlist are fixed movie/TV lists whose
//  order comes from metadata saved at add time. Every other list keeps the order
//  the user arranged, with new items inserted at the top.
//

import Foundation

/// Movies & TV and People are separate libraries. A list belongs to one of them.
enum LibrarySegment: String, Codable, Sendable, Equatable, CaseIterable {
    case moviesAndTV
    case people

    var title: String {
        switch self {
            case .moviesAndTV: "Movies & TV"
            case .people: "People"
        }
    }
}

/// Fixed Movies & TV lists. They cannot be renamed, deleted, or reordered.
enum SystemListKind: String, Codable, Sendable, Equatable {
    case watched
    case inProgress
    case watchlist

    var name: String {
        switch self {
            case .watched: "Watched"
            case .inProgress: "In Progress"
            case .watchlist: "Watchlist"
        }
    }

    /// Hidden from every + list menu. Watched / In Progress come from the eye
    /// toggle and TV episode progress — never from manual membership picks.
    static let membershipMenuHidden: Set<SystemListKind> = [.watched, .inProgress]

    /// Same as `membershipMenuHidden` (kept for older TV call sites).
    static let tvMembershipHidden: Set<SystemListKind> = membershipMenuHidden
}

/// Sort for Watched and Watchlist. Custom and people lists ignore this and keep manual order.
enum LibrarySort: String, Codable, Sendable, Equatable, CaseIterable {
    case dateAdded
    case alphabetical
    case popular
    case topRated
    case newest
    case oldest

    var title: String {
        switch self {
            case .dateAdded: "Date Added"
            case .alphabetical: "Alphabetical"
            case .popular: "Popular"
            case .topRated: "Top Rated"
            case .newest: "Newest"
            case .oldest: "Oldest"
        }
    }

    var symbol: String {
        switch self {
            case .dateAdded: "clock"
            case .alphabetical: "textformat.abc"
            case .popular: "flame"
            case .topRated: "star"
            case .newest: "arrow.down"
            case .oldest: "arrow.up"
        }
    }
}

/// One saved list. `system` is nil for a list the user created.
struct LibraryList: Codable, Sendable, Equatable, Identifiable, Hashable {
    let id: UUID
    var name: String
    let segment: LibrarySegment
    /// Nil for a custom list. Watched, In Progress, and Watchlist are system lists.
    let system: SystemListKind?
    /// Remembered sort for a system list. Custom and people lists keep `position` order instead.
    var sort: LibrarySort
    /// Order of custom lists inside a segment. System lists stay pinned and ignore this.
    var position: Int

    var isSystem: Bool { system != nil }

    static func system(_ kind: SystemListKind, id: UUID = UUID(), position: Int = 0) -> LibraryList {
        LibraryList(
            id: id,
            name: kind.name,
            segment: .moviesAndTV,
            system: kind,
            sort: .dateAdded,
            position: position
        )
    }
}

/// Movie, series, or person. Movie ids and person ids share TMDB's number space, so kind is part of identity.
enum ListItemKind: String, Codable, Sendable, Equatable, Hashable {
    case movie
    case tv
    case person

    var segment: LibrarySegment {
        switch self {
            case .movie, .tv: .moviesAndTV
            case .person: .people
        }
    }
}

/// Metadata copied at add time so Watched and Watchlist can sort without another network request.
struct ListItemDraft: Sendable, Equatable, Hashable {
    let id: Int
    let kind: ListItemKind
    let title: String
    let imagePath: String?
    let releaseDate: Date?
    let genreNames: [String]
    let voteAverage: Double
    let popularity: Double

    /// Stable per-kind identity. Movie 500 and person 500 must not collide.
    var itemKey: String { ListEntry.itemKey(id: id, kind: kind) }
}

/// One membership. `position` 0 is the top of a custom or people list.
struct ListEntry: Codable, Sendable, Equatable, Identifiable, Hashable {
    let listID: UUID
    let itemID: Int
    let kind: ListItemKind
    let addedAt: Date
    var position: Int
    let title: String
    let imagePath: String?
    let releaseDate: Date?
    let genreNames: [String]
    let voteAverage: Double
    let popularity: Double

    var id: String { "\(listID.uuidString)-\(itemKey)" }

    var itemKey: String { Self.itemKey(id: itemID, kind: kind) }

    static func itemKey(id: Int, kind: ListItemKind) -> String {
        "\(kind.rawValue)-\(id)"
    }

    init(listID: UUID, draft: ListItemDraft, addedAt: Date, position: Int) {
        self.listID = listID
        self.itemID = draft.id
        self.kind = draft.kind
        self.addedAt = addedAt
        self.position = position
        self.title = draft.title
        self.imagePath = draft.imagePath
        self.releaseDate = draft.releaseDate
        self.genreNames = draft.genreNames
        self.voteAverage = draft.voteAverage
        self.popularity = draft.popularity
    }

    /// Merges `draft` into this row. Non-empty draft fields win so detail can refresh a
    /// stale poster; empty draft fields leave the stored value alone.
    /// Returns `nil` when nothing changes so callers can skip a write.
    func mergingSnapshot(from draft: ListItemDraft) -> ListEntry? {
        guard draft.itemKey == itemKey else { return nil }
        let trimmedDraftTitle = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let nextTitle = trimmedDraftTitle.isEmpty ? title : draft.title
        let nextImage = draft.imagePath ?? imagePath
        let nextDate = draft.releaseDate ?? releaseDate
        let nextGenres = draft.genreNames.isEmpty ? genreNames : draft.genreNames
        let nextVote = draft.voteAverage != 0 ? draft.voteAverage : voteAverage
        let nextPopularity = draft.popularity != 0 ? draft.popularity : popularity
        let updated = ListEntry(
            listID: listID,
            itemID: itemID,
            kind: kind,
            addedAt: addedAt,
            position: position,
            title: nextTitle,
            imagePath: nextImage,
            releaseDate: nextDate,
            genreNames: nextGenres,
            voteAverage: nextVote,
            popularity: nextPopularity
        )
        return updated == self ? nil : updated
    }

    private init(
        listID: UUID,
        itemID: Int,
        kind: ListItemKind,
        addedAt: Date,
        position: Int,
        title: String,
        imagePath: String?,
        releaseDate: Date?,
        genreNames: [String],
        voteAverage: Double,
        popularity: Double
    ) {
        self.listID = listID
        self.itemID = itemID
        self.kind = kind
        self.addedAt = addedAt
        self.position = position
        self.title = title
        self.imagePath = imagePath
        self.releaseDate = releaseDate
        self.genreNames = genreNames
        self.voteAverage = voteAverage
        self.popularity = popularity
    }
}

/// On-disk library. Favorites are not imported into this snapshot.
struct LibrarySnapshot: Codable, Sendable, Equatable {
    var lists: [LibraryList]
    var entries: [ListEntry]

    static let empty = LibrarySnapshot(lists: [], entries: [])

    /// System lists first (Watched, In Progress, Watchlist), then custom lists by position.
    func lists(in segment: LibrarySegment) -> [LibraryList] {
        let matching = lists.filter { $0.segment == segment }
        let system = matching
            .filter { $0.system != nil }
            .sorted { Self.systemRank($0) < Self.systemRank($1) }
        let custom = matching
            .filter { $0.system == nil }
            .sorted { lhs, rhs in
                if lhs.position != rhs.position { return lhs.position < rhs.position }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
        return system + custom
    }

    func list(_ kind: SystemListKind) -> LibraryList? {
        lists.first { $0.system == kind }
    }

    private static func systemRank(_ list: LibraryList) -> Int {
        switch list.system {
            case .watched: 0
            case .inProgress: 1
            case .watchlist: 2
            case nil: 3
        }
    }
}

/// Why a list edit was rejected before anything was written.
enum ListEditError: Error, Equatable, Sendable {
    case emptyName
    case duplicateName
    case systemListLocked
    case wrongSegment
    case missingList

    /// Name problems reopen the name dialog. Other cases are shown as a save failure.
    var isNameRejection: Bool {
        switch self {
            case .emptyName, .duplicateName: true
            case .systemListLocked, .wrongSegment, .missingList: false
        }
    }

    var message: String {
        switch self {
            case .emptyName:
                "Enter a name."
            case .duplicateName:
                "A list with that name already exists."
            case .systemListLocked:
                "System lists can't be changed."
            case .wrongSegment:
                "That title doesn't belong on this list."
            case .missingList:
                "That list no longer exists."
        }
    }
}

/// Result of adding or removing one title, including rows displaced from other lists.
struct MembershipChange: Sendable, Equatable {
    enum Action: Sendable, Equatable {
        case added
        case removed
        case unchanged
    }

    let action: Action
    let listID: UUID
    let listName: String
    let itemKey: String
    /// Rows removed from other lists because of this add (Watchlist / In Progress). Undo puts them back.
    let restores: [ListEntry]
    /// The row taken off the target list. Undo of a removal puts this back in place.
    let removed: ListEntry?
    /// Soft-move copy such as “Moved to Watched.” Wins over the default added/removed string.
    let messageOverride: String?

    /// Watchlist (or first) displaced row. Kept for older call sites and tests.
    var restore: ListEntry? { restores.first }

    /// Banner copy for an add or removal. An unchanged membership has nothing to confirm.
    var confirmation: String? {
        if let messageOverride { return messageOverride }
        switch action {
            case .added:
                return "Added to \(listName)"
            case .removed:
                return "Removed from \(listName)"
            case .unchanged:
                return nil
        }
    }

    init(
        action: Action,
        listID: UUID,
        listName: String,
        itemKey: String,
        restores: [ListEntry] = [],
        removed: ListEntry? = nil,
        messageOverride: String? = nil
    ) {
        self.action = action
        self.listID = listID
        self.listName = listName
        self.itemKey = itemKey
        self.restores = restores
        self.removed = removed
        self.messageOverride = messageOverride
    }

    /// Compatibility with the former single-`restore` call sites.
    init(
        action: Action,
        listID: UUID,
        listName: String,
        itemKey: String,
        restore: ListEntry?,
        removed: ListEntry?,
        messageOverride: String? = nil
    ) {
        self.init(
            action: action,
            listID: listID,
            listName: listName,
            itemKey: itemKey,
            restores: restore.map { [$0] } ?? [],
            removed: removed,
            messageOverride: messageOverride
        )
    }
}

/// Orders Watched and Watchlist from the snapshot saved at add time.
/// Equal keys break A to Z, then by id. A missing release date is older than every real date.
enum LibraryOrdering {
    static func displayed(_ entries: [ListEntry], list: LibraryList) -> [ListEntry] {
        let mine = entries.filter { $0.listID == list.id }
        if list.system != nil {
            return sorted(mine, by: list.sort)
        }
        return mine.sorted { lhs, rhs in
            if lhs.position != rhs.position { return lhs.position < rhs.position }
            return lhs.addedAt > rhs.addedAt
        }
    }

    static func sorted(_ entries: [ListEntry], by sort: LibrarySort) -> [ListEntry] {
        entries.sorted { comesBefore($0, $1, sort: sort) }
    }

    static func comesBefore(_ lhs: ListEntry, _ rhs: ListEntry, sort: LibrarySort) -> Bool {
        switch sort {
            case .dateAdded:
                if lhs.addedAt != rhs.addedAt { return lhs.addedAt > rhs.addedAt }
            case .popular:
                if lhs.popularity != rhs.popularity { return lhs.popularity > rhs.popularity }
            case .topRated:
                if lhs.voteAverage != rhs.voteAverage { return lhs.voteAverage > rhs.voteAverage }
            case .alphabetical:
                break
            case .newest:
                switch (lhs.releaseDate, rhs.releaseDate) {
            case let (left?, right?) where left != right:
                return left > right
            case (.some, .none):
                return true
            case (.none, .some):
                return false
            default:
                break
            }
            case .oldest:
                switch (lhs.releaseDate, rhs.releaseDate) {
            case let (left?, right?) where left != right:
                return left < right
            case (.none, .some):
                return true
            case (.some, .none):
                return false
            default:
                break
            }
        }
        let titleOrder = lhs.title.compare(
            rhs.title,
            options: [.caseInsensitive, .diacriticInsensitive]
        )
        if titleOrder != .orderedSame {
            return titleOrder == .orderedAscending
        }
        if lhs.itemID != rhs.itemID {
            return lhs.itemID < rhs.itemID
        }
        return kindRank(lhs.kind) < kindRank(rhs.kind)
    }

    private static func kindRank(_ kind: ListItemKind) -> Int {
        switch kind {
            case .movie: 0
            case .tv: 1
            case .person: 2
        }
    }
}

/// Find-list and in-list filtering. A library search matches the list name or any member title.
enum LibraryQuery {
    static func lists(
        in segment: LibrarySegment,
        snapshot: LibrarySnapshot,
        matching query: String
    ) -> [LibraryList] {
        let ordered = snapshot.lists(in: segment)
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return ordered }
        return ordered.filter { list in
            list.name.localizedStandardContains(trimmed)
                || snapshot.entries.contains {
                    $0.listID == list.id && $0.title.localizedStandardContains(trimmed)
                }
        }
    }

    /// Movies / TV filter applies only inside a Movies & TV list. People lists pass `.all`.
    static func entries(
        _ entries: [ListEntry],
        matching query: String,
        filter: TitleMediaFilter
    ) -> [ListEntry] {
        let kindFiltered = entries.filter { entry in
            switch filter {
                case .all: true
                case .movies: entry.kind == .movie
                case .tv: entry.kind == .tv
            }
        }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return kindFiltered }
        return kindFiltered.filter { $0.title.localizedStandardContains(trimmed) }
    }
}

/// All / Movies / TV inside a Movies & TV list.
enum TitleMediaFilter: String, CaseIterable, Sendable, Equatable {
    case all
    case movies
    case tv

    var title: String {
        switch self {
            case .all: "All"
            case .movies: "Movies"
            case .tv: "TV"
        }
    }
}
