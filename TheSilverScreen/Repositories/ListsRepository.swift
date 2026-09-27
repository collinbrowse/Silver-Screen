//
//  ListsRepository.swift
//  TheSilverScreen
//
//  Personal library. Watched and Watchlist are created the first time the
//  library is read. favorites.json is not imported. Writes run one at a time
//  so two adds cannot clobber each other.
//

import Foundation

/// A list that was just created, plus the membership change when it started with a title.
struct ListCreation: Sendable, Equatable {
    let list: LibraryList
    let change: MembershipChange?
}

actor ListsRepository {
    private let store: any ListsStore
    private let logger: any AppLogging
    private let index: ListsIndex
    private var cached: LibrarySnapshot?
    private var loadTask: Task<LibrarySnapshot, Error>?
    /// Tail of the serialized write chain. See `serializeWrite`.
    private var writeBarrier: Task<Void, Never>?

    @MainActor
    init(
        store: any ListsStore,
        logger: any AppLogging,
        index: ListsIndex = ListsIndex()
    ) {
        self.store = store
        self.logger = logger
        self.index = index
    }

    /// Reads persistence into the shared index. Call once at launch; later calls hit the cache.
    func loadIndex() async throws {
        _ = try await loadCache()
    }

    func snapshot() async throws -> LibrarySnapshot {
        try await loadCache()
    }

    /// Adds the title, or removes it when it is already on the list.
    func toggle(draft: ListItemDraft, listID: UUID, at date: Date = Date()) async throws -> MembershipChange {
        try await serializeWrite { [self] in
            try await performToggle(draft: draft, listID: listID, at: date)
        }
    }

    func add(draft: ListItemDraft, listID: UUID, at date: Date = Date()) async throws -> MembershipChange {
        try await serializeWrite { [self] in
            try await performAdd(draft: draft, listID: listID, at: date)
        }
    }

    func remove(itemKey: String, listID: UUID) async throws -> MembershipChange {
        try await serializeWrite { [self] in
            try await performRemove(itemKey: itemKey, listID: listID)
        }
    }

    /// Reverses an add or removal. An add to Watched also puts back the Watchlist row it displaced.
    func undo(_ change: MembershipChange) async throws {
        try await serializeWrite { [self] in
            try await performUndo(change)
        }
    }

    /// Creates a custom list. Pass `adding` to put that title at the top in the same write.
    @discardableResult
    func createList(
        name: String,
        segment: LibrarySegment,
        adding draft: ListItemDraft? = nil,
        at date: Date = Date()
    ) async throws -> ListCreation {
        try await serializeWrite { [self] in
            try await performCreate(name: name, segment: segment, adding: draft, at: date)
        }
    }

    func renameList(id: UUID, name: String) async throws {
        try await serializeWrite { [self] in
            try await performRename(id: id, name: name)
        }
    }

    func deleteList(id: UUID) async throws {
        try await serializeWrite { [self] in
            try await performDelete(id: id)
        }
    }

    /// Reorders custom lists in one segment. Offsets refer to the custom lists only.
    func moveLists(in segment: LibrarySegment, fromOffsets source: IndexSet, toOffset destination: Int) async throws {
        try await serializeWrite { [self] in
            try await performMoveLists(in: segment, fromOffsets: source, toOffset: destination)
        }
    }

    /// Remembers a sort on Watched or Watchlist. Custom lists keep manual order.
    func setSort(_ sort: LibrarySort, listID: UUID) async throws {
        try await serializeWrite { [self] in
            try await performSetSort(sort, listID: listID)
        }
    }

    /// Rewrites manual order. Offsets refer to the list's current position order. System lists ignore this.
    func moveEntries(listID: UUID, fromOffsets source: IndexSet, toOffset destination: Int) async throws {
        try await serializeWrite { [self] in
            try await performMoveEntries(listID: listID, fromOffsets: source, toOffset: destination)
        }
    }

    // MARK: - Write serialization

    /// Runs `work` strictly after any previously enqueued mutation so a save cannot
    /// overwrite a membership the previous write had not finished persisting.
    private func serializeWrite<T: Sendable>(
        _ work: @Sendable @escaping () async throws -> T
    ) async throws -> T {
        let previous = writeBarrier
        let task = Task<T, Error> {
            _ = await previous?.value
            return try await work()
        }
        writeBarrier = Task { _ = try? await task.value }
        return try await task.value
    }

    // MARK: - Mutations

    private func performToggle(draft: ListItemDraft, listID: UUID, at date: Date) async throws -> MembershipChange {
        let snapshot = try await loadCache()
        if snapshot.entries.contains(where: { $0.listID == listID && $0.itemKey == draft.itemKey }) {
            return try await performRemove(itemKey: draft.itemKey, listID: listID)
        }
        return try await performAdd(draft: draft, listID: listID, at: date)
    }

    private func performAdd(draft: ListItemDraft, listID: UUID, at date: Date) async throws -> MembershipChange {
        var snapshot = try await loadCache()
        guard let list = snapshot.lists.first(where: { $0.id == listID }) else {
            throw ListEditError.missingList
        }
        guard draft.kind.segment == list.segment else {
            throw ListEditError.wrongSegment
        }
        if snapshot.entries.contains(where: { $0.listID == listID && $0.itemKey == draft.itemKey }) {
            return MembershipChange(
                action: .unchanged,
                listID: list.id,
                listName: list.name,
                itemKey: draft.itemKey,
                restore: nil,
                removed: nil
            )
        }

        var restore: ListEntry?
        if list.system == .watched, let watchlist = snapshot.list(.watchlist) {
            let removal = Self.removing(itemKey: draft.itemKey, listID: watchlist.id, from: snapshot.entries)
            snapshot.entries = removal.entries
            restore = removal.removed
        }

        snapshot.entries = Self.prepending(draft, listID: list.id, at: date, to: snapshot.entries)
        try await persist(snapshot)
        return MembershipChange(
            action: .added,
            listID: list.id,
            listName: list.name,
            itemKey: draft.itemKey,
            restore: restore,
            removed: nil
        )
    }

    private func performRemove(itemKey: String, listID: UUID) async throws -> MembershipChange {
        var snapshot = try await loadCache()
        guard let list = snapshot.lists.first(where: { $0.id == listID }) else {
            throw ListEditError.missingList
        }
        let removal = Self.removing(itemKey: itemKey, listID: listID, from: snapshot.entries)
        guard let removed = removal.removed else {
            return MembershipChange(
                action: .unchanged,
                listID: list.id,
                listName: list.name,
                itemKey: itemKey,
                restore: nil,
                removed: nil
            )
        }
        snapshot.entries = removal.entries
        try await persist(snapshot)
        return MembershipChange(
            action: .removed,
            listID: list.id,
            listName: list.name,
            itemKey: itemKey,
            restore: nil,
            removed: removed
        )
    }

    private func performUndo(_ change: MembershipChange) async throws {
        guard change.action != .unchanged else { return }
        var snapshot = try await loadCache()
        switch change.action {
        case .added:
            snapshot.entries = Self.removing(
                itemKey: change.itemKey,
                listID: change.listID,
                from: snapshot.entries
            ).entries
            if let restore = change.restore {
                snapshot.entries = Self.inserting(restore, into: snapshot.entries)
            }
        case .removed:
            if let removed = change.removed {
                snapshot.entries = Self.inserting(removed, into: snapshot.entries)
            }
        case .unchanged:
            return
        }
        try await persist(snapshot)
    }

    private func performCreate(
        name: String,
        segment: LibrarySegment,
        adding draft: ListItemDraft?,
        at date: Date
    ) async throws -> ListCreation {
        var snapshot = try await loadCache()
        if let draft, draft.kind.segment != segment {
            throw ListEditError.wrongSegment
        }
        let trimmed = try Self.validatedName(name, segment: segment, lists: snapshot.lists, excluding: nil)
        let position = (snapshot.lists
            .filter { $0.segment == segment && !$0.isSystem }
            .map(\.position)
            .max() ?? -1) + 1
        let list = LibraryList(
            id: UUID(),
            name: trimmed,
            segment: segment,
            system: nil,
            sort: .dateAdded,
            position: position
        )
        snapshot.lists.append(list)
        var change: MembershipChange?
        if let draft {
            snapshot.entries = Self.prepending(draft, listID: list.id, at: date, to: snapshot.entries)
            change = MembershipChange(
                action: .added,
                listID: list.id,
                listName: list.name,
                itemKey: draft.itemKey,
                restore: nil,
                removed: nil
            )
        }
        try await persist(snapshot)
        return ListCreation(list: list, change: change)
    }

    private func performRename(id: UUID, name: String) async throws {
        var snapshot = try await loadCache()
        guard let index = snapshot.lists.firstIndex(where: { $0.id == id }) else {
            throw ListEditError.missingList
        }
        guard snapshot.lists[index].system == nil else {
            throw ListEditError.systemListLocked
        }
        let trimmed = try Self.validatedName(
            name,
            segment: snapshot.lists[index].segment,
            lists: snapshot.lists,
            excluding: id
        )
        snapshot.lists[index].name = trimmed
        try await persist(snapshot)
    }

    private func performDelete(id: UUID) async throws {
        var snapshot = try await loadCache()
        guard let list = snapshot.lists.first(where: { $0.id == id }) else {
            throw ListEditError.missingList
        }
        guard list.system == nil else {
            throw ListEditError.systemListLocked
        }
        snapshot.lists.removeAll { $0.id == id }
        snapshot.entries.removeAll { $0.listID == id }
        try await persist(snapshot)
    }

    private func performMoveLists(
        in segment: LibrarySegment,
        fromOffsets source: IndexSet,
        toOffset destination: Int
    ) async throws {
        var snapshot = try await loadCache()
        var custom = snapshot.lists(in: segment).filter { !$0.isSystem }
        guard !source.isEmpty, custom.count > 1 else { return }
        custom = Self.applyingMove(custom, fromOffsets: source, toOffset: destination)
        for (position, list) in custom.enumerated() {
            guard let index = snapshot.lists.firstIndex(where: { $0.id == list.id }) else { continue }
            snapshot.lists[index].position = position
        }
        try await persist(snapshot)
    }

    private func performSetSort(_ sort: LibrarySort, listID: UUID) async throws {
        var snapshot = try await loadCache()
        guard let index = snapshot.lists.firstIndex(where: { $0.id == listID }) else {
            throw ListEditError.missingList
        }
        guard snapshot.lists[index].system != nil else { return }
        guard snapshot.lists[index].sort != sort else { return }
        snapshot.lists[index].sort = sort
        try await persist(snapshot)
    }

    private func performMoveEntries(
        listID: UUID,
        fromOffsets source: IndexSet,
        toOffset destination: Int
    ) async throws {
        var snapshot = try await loadCache()
        guard let list = snapshot.lists.first(where: { $0.id == listID }) else {
            throw ListEditError.missingList
        }
        guard list.system == nil, !source.isEmpty else { return }
        var ordered = LibraryOrdering.displayed(snapshot.entries, list: list)
        guard ordered.count > 1 else { return }
        ordered = Self.applyingMove(ordered, fromOffsets: source, toOffset: destination)
        var byKey: [String: ListEntry] = [:]
        for entry in snapshot.entries where entry.listID == listID {
            byKey[entry.itemKey] = entry
        }
        for (position, entry) in ordered.enumerated() {
            byKey[entry.itemKey]?.position = position
        }
        snapshot.entries = snapshot.entries.map { entry in
            guard entry.listID == listID, let updated = byKey[entry.itemKey] else { return entry }
            return updated
        }
        try await persist(snapshot)
    }

    // MARK: - Load and save

    private func loadCache() async throws -> LibrarySnapshot {
        if let cached {
            return cached
        }
        if let loadTask {
            return try await loadTask.value
        }
        let task = Task { try await self.performLoad() }
        loadTask = task
        do {
            let snapshot = try await task.value
            loadTask = nil
            return snapshot
        } catch {
            loadTask = nil
            throw error
        }
    }

    private func performLoad() async throws -> LibrarySnapshot {
        do {
            let loaded = try await store.load()
            let seeded = Self.ensuringSystemLists(loaded)
            if seeded != loaded {
                try await store.save(seeded)
            }
            cached = seeded
            await index.replace(with: seeded)
            return seeded
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            logger.error("Lists load failed", category: .persistence)
            throw AppError.persistence
        }
    }

    private func persist(_ snapshot: LibrarySnapshot) async throws {
        do {
            try await store.save(snapshot)
            cached = snapshot
            await index.replace(with: snapshot)
        } catch {
            logger.error("Lists save failed", category: .persistence)
            throw AppError.persistence
        }
    }

    /// Watched and Watchlist exist on Movies & TV. People starts with no lists.
    private static func ensuringSystemLists(_ snapshot: LibrarySnapshot) -> LibrarySnapshot {
        var lists = snapshot.lists
        if !lists.contains(where: { $0.system == .watched }) {
            lists.append(.system(.watched, position: 0))
        }
        if !lists.contains(where: { $0.system == .watchlist }) {
            lists.append(.system(.watchlist, position: 1))
        }
        return LibrarySnapshot(lists: lists, entries: snapshot.entries)
    }

    /// Trimmed name, or a rejection. System names are reserved on Movies & TV.
    private static func validatedName(
        _ raw: String,
        segment: LibrarySegment,
        lists: [LibraryList],
        excluding id: UUID?
    ) throws -> String {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw ListEditError.emptyName }
        if segment == .moviesAndTV, isReservedMovieTVName(name) {
            throw ListEditError.duplicateName
        }
        let duplicate = lists.contains { list in
            list.id != id
                && list.segment == segment
                && list.name.compare(name, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }
        if duplicate {
            throw ListEditError.duplicateName
        }
        return name
    }

    private static func isReservedMovieTVName(_ name: String) -> Bool {
        let folded = name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        return folded.compare("Watched", options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
            || folded.compare("Watchlist", options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
    }

    private static func prepending(
        _ draft: ListItemDraft,
        listID: UUID,
        at date: Date,
        to entries: [ListEntry]
    ) -> [ListEntry] {
        var entries = entries
        for index in entries.indices where entries[index].listID == listID {
            entries[index].position += 1
        }
        entries.append(ListEntry(listID: listID, draft: draft, addedAt: date, position: 0))
        return entries
    }

    private static func removing(
        itemKey: String,
        listID: UUID,
        from entries: [ListEntry]
    ) -> (entries: [ListEntry], removed: ListEntry?) {
        var entries = entries
        guard let index = entries.firstIndex(where: { $0.listID == listID && $0.itemKey == itemKey }) else {
            return (entries, nil)
        }
        let removed = entries.remove(at: index)
        let ordered = entries.indices
            .filter { entries[$0].listID == listID }
            .sorted { entries[$0].position < entries[$1].position }
        for (position, entryIndex) in ordered.enumerated() {
            entries[entryIndex].position = position
        }
        return (entries, removed)
    }

    private static func inserting(_ entry: ListEntry, into entries: [ListEntry]) -> [ListEntry] {
        guard !entries.contains(where: { $0.listID == entry.listID && $0.itemKey == entry.itemKey }) else {
            return entries
        }
        var entries = entries
        for index in entries.indices where entries[index].listID == entry.listID && entries[index].position >= entry.position {
            entries[index].position += 1
        }
        entries.append(entry)
        return entries
    }

    /// SwiftUI `onMove` offsets: `toOffset` is the index before the move.
    private static func applyingMove<T>(_ items: [T], fromOffsets source: IndexSet, toOffset destination: Int) -> [T] {
        var items = items
        let moving = source.sorted().compactMap { index -> T? in
            items.indices.contains(index) ? items[index] : nil
        }
        for index in source.sorted(by: >) where items.indices.contains(index) {
            items.remove(at: index)
        }
        let adjusted = destination - source.filter { $0 < destination }.count
        let index = min(max(adjusted, 0), items.count)
        items.insert(contentsOf: moving, at: index)
        return items
    }
}
