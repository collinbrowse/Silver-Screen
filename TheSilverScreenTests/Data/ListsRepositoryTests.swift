//
//  ListsRepositoryTests.swift
//  TheSilverScreenTests
//

import XCTest
@testable import TheSilverScreen

@MainActor
final class ListsRepositoryTests: XCTestCase {

    func test_snapshot_seedsWatchedAndWatchlistSortedByDateAdded() async throws {
        let repository = makeRepository()

        let snapshot = try await repository.snapshot()

        let movies = snapshot.lists(in: .moviesAndTV)
        XCTAssertEqual(movies.map(\.name), ["Watched", "Watchlist"])
        XCTAssertEqual(movies.map(\.sort), [.dateAdded, .dateAdded])
        XCTAssertTrue(snapshot.lists(in: .people).isEmpty)
    }

    func test_add_persistsSnapshotFields() async throws {
        let repository = makeRepository()
        let watched = try await systemList(.watched, repository: repository)
        let draft = movie(
            id: 278,
            title: "The Shawshank Redemption",
            vote: 8.7,
            popularity: 42.5,
            date: TestMovies.date("1994-09-23"),
            genres: ["Drama", "Crime"],
            imagePath: "/poster.jpg"
        )

        let change = try await repository.add(draft: draft, listID: watched.id, at: TestMovies.date("2024-06-01"))

        XCTAssertEqual(change.action, .added)
        XCTAssertEqual(change.confirmation, "Added to Watched")
        let snapshot = try await repository.snapshot()
        let entry = try XCTUnwrap(snapshot.entries.first)
        XCTAssertEqual(entry.title, "The Shawshank Redemption")
        XCTAssertEqual(entry.imagePath, "/poster.jpg")
        XCTAssertEqual(entry.releaseDate, TestMovies.date("1994-09-23"))
        XCTAssertEqual(entry.genreNames, ["Drama", "Crime"])
        XCTAssertEqual(entry.voteAverage, 8.7)
        XCTAssertEqual(entry.popularity, 42.5)
        XCTAssertEqual(entry.addedAt, TestMovies.date("2024-06-01"))
        XCTAssertEqual(entry.kind, .movie)
    }

    func test_enrich_fillsSparseSnapshotAndPreservesAddedAt() async throws {
        let repository = makeRepository()
        let watched = try await systemList(.watched, repository: repository)
        let addedAt = TestMovies.date("2024-04-01")
        _ = try await repository.add(
            draft: ListItemDraft(
                id: 99,
                kind: .tv,
                title: "Alone: Frozen",
                imagePath: nil,
                releaseDate: nil,
                genreNames: [],
                voteAverage: 0,
                popularity: 0
            ),
            listID: watched.id,
            at: addedAt
        )

        try await repository.enrich(
            draft: ListItemDraft(
                id: 99,
                kind: .tv,
                title: "Alone: Frozen",
                imagePath: "/alone.jpg",
                releaseDate: TestMovies.date("2022-08-11"),
                genreNames: ["Reality"],
                voteAverage: 7.5,
                popularity: 12
            )
        )

        let snapshot = try await repository.snapshot()
        let entry = try XCTUnwrap(snapshot.entries.first { $0.itemID == 99 })
        XCTAssertEqual(entry.imagePath, "/alone.jpg")
        XCTAssertEqual(entry.releaseDate, TestMovies.date("2022-08-11"))
        XCTAssertEqual(entry.genreNames, ["Reality"])
        XCTAssertEqual(entry.voteAverage, 7.5)
        XCTAssertEqual(entry.popularity, 12)
        XCTAssertEqual(entry.addedAt, addedAt)
    }

    func test_enrich_leavesRicherRowAlone() async throws {
        let repository = makeRepository()
        let watched = try await systemList(.watched, repository: repository)
        let addedAt = TestMovies.date("2024-04-01")
        _ = try await repository.add(
            draft: movie(
                id: 1,
                title: "Batman Begins",
                vote: 8,
                popularity: 40,
                date: TestMovies.date("2005-06-10"),
                genres: ["Action"],
                imagePath: "/batman.jpg"
            ),
            listID: watched.id,
            at: addedAt
        )

        try await repository.enrich(
            draft: movie(
                id: 1,
                title: "Batman Begins",
                vote: 1,
                popularity: 1,
                date: TestMovies.date("2099-01-01"),
                genres: ["Wrong"],
                imagePath: "/other.jpg"
            )
        )

        let snapshot = try await repository.snapshot()
        let entry = try XCTUnwrap(snapshot.entries.first)
        XCTAssertEqual(entry.imagePath, "/batman.jpg")
        XCTAssertEqual(entry.releaseDate, TestMovies.date("2005-06-10"))
        XCTAssertEqual(entry.genreNames, ["Action"])
        XCTAssertEqual(entry.voteAverage, 8)
        XCTAssertEqual(entry.popularity, 40)
        XCTAssertEqual(entry.addedAt, addedAt)
    }

    func test_addWhenAlreadyPresent_enrichesSparseSnapshot() async throws {
        let repository = makeRepository()
        let watched = try await systemList(.watched, repository: repository)
        let addedAt = TestMovies.date("2024-04-01")
        _ = try await repository.add(
            draft: ListItemDraft(
                id: 42,
                kind: .tv,
                title: "The Wire",
                imagePath: nil,
                releaseDate: nil,
                genreNames: [],
                voteAverage: 0,
                popularity: 0
            ),
            listID: watched.id,
            at: addedAt
        )

        let change = try await repository.add(
            draft: ListItemDraft(
                id: 42,
                kind: .tv,
                title: "The Wire",
                imagePath: "/wire.jpg",
                releaseDate: TestMovies.date("2002-06-02"),
                genreNames: ["Drama", "Crime"],
                voteAverage: 9.3,
                popularity: 70
            ),
            listID: watched.id,
            at: TestMovies.date("2024-08-01")
        )

        XCTAssertEqual(change.action, .unchanged)
        let snapshot = try await repository.snapshot()
        let entry = try XCTUnwrap(snapshot.entries.first { $0.itemID == 42 })
        XCTAssertEqual(entry.imagePath, "/wire.jpg")
        XCTAssertEqual(entry.releaseDate, TestMovies.date("2002-06-02"))
        XCTAssertEqual(entry.genreNames, ["Drama", "Crime"])
        XCTAssertEqual(entry.addedAt, addedAt)
    }

    func test_watched_sortsFromStoredNumbers() async throws {
        let repository = makeRepository()
        let watched = try await systemList(.watched, repository: repository)
        _ = try await repository.add(
            draft: movie(id: 1, title: "Low", vote: 9, popularity: 1),
            listID: watched.id,
            at: TestMovies.date("2024-01-01")
        )
        _ = try await repository.add(
            draft: movie(id: 2, title: "High", vote: 2, popularity: 50),
            listID: watched.id,
            at: TestMovies.date("2024-02-01")
        )
        _ = try await repository.add(
            draft: movie(id: 3, title: "Mid", vote: 7, popularity: 10),
            listID: watched.id,
            at: TestMovies.date("2024-03-01")
        )

        try await repository.setSort(.popular, listID: watched.id)
        var snapshot = try await repository.snapshot()
        var list = try XCTUnwrap(snapshot.list(.watched))
        XCTAssertEqual(LibraryOrdering.displayed(snapshot.entries, list: list).map(\.title), ["High", "Mid", "Low"])

        try await repository.setSort(.topRated, listID: watched.id)
        snapshot = try await repository.snapshot()
        list = try XCTUnwrap(snapshot.list(.watched))
        XCTAssertEqual(LibraryOrdering.displayed(snapshot.entries, list: list).map(\.title), ["Low", "Mid", "High"])
    }

    func test_dateAdded_listsNewestFirst() async throws {
        let repository = makeRepository()
        let watched = try await systemList(.watched, repository: repository)
        _ = try await repository.add(
            draft: movie(id: 1, title: "Older"),
            listID: watched.id,
            at: TestMovies.date("2024-01-01")
        )
        _ = try await repository.add(
            draft: movie(id: 2, title: "Newer"),
            listID: watched.id,
            at: TestMovies.date("2024-06-15")
        )

        let snapshot = try await repository.snapshot()
        let list = try XCTUnwrap(snapshot.list(.watched))
        XCTAssertEqual(list.sort, .dateAdded)
        XCTAssertEqual(LibraryOrdering.displayed(snapshot.entries, list: list).map(\.itemID), [2, 1])
    }

    func test_customList_prependsNewItemAfterReorder() async throws {
        let repository = makeRepository()
        let list = try await repository.createList(name: "Friday", segment: .moviesAndTV).list
        _ = try await repository.add(draft: movie(id: 1, title: "A"), listID: list.id, at: TestMovies.date("2024-01-01"))
        _ = try await repository.add(draft: movie(id: 2, title: "B"), listID: list.id, at: TestMovies.date("2024-01-02"))
        try await repository.moveEntries(listID: list.id, fromOffsets: IndexSet(integer: 1), toOffset: 0)

        _ = try await repository.add(draft: movie(id: 3, title: "C"), listID: list.id, at: TestMovies.date("2024-01-03"))

        let snapshot = try await repository.snapshot()
        let stored = try XCTUnwrap(snapshot.lists.first { $0.id == list.id })
        XCTAssertEqual(LibraryOrdering.displayed(snapshot.entries, list: stored).map(\.title), ["C", "A", "B"])
    }

    func test_peopleList_prependsNewItemAfterReorder() async throws {
        let repository = makeRepository()
        let list = try await repository.createList(name: "Directors", segment: .people).list
        _ = try await repository.add(draft: person(id: 1, title: "A"), listID: list.id, at: TestMovies.date("2024-01-01"))
        _ = try await repository.add(draft: person(id: 2, title: "B"), listID: list.id, at: TestMovies.date("2024-01-02"))
        try await repository.moveEntries(listID: list.id, fromOffsets: IndexSet(integer: 1), toOffset: 0)

        _ = try await repository.add(draft: person(id: 3, title: "C"), listID: list.id, at: TestMovies.date("2024-01-03"))

        let snapshot = try await repository.snapshot()
        let stored = try XCTUnwrap(snapshot.lists.first { $0.id == list.id })
        XCTAssertEqual(LibraryOrdering.displayed(snapshot.entries, list: stored).map(\.title), ["C", "A", "B"])
    }

    func test_addToWatched_recordsTheMovieAndDropsWatchlist() async throws {
        let repository = makeRepository()
        let watchlist = try await systemList(.watchlist, repository: repository)
        let custom = try await repository.createList(name: "Friday", segment: .moviesAndTV).list
        let draft = movie(id: 15, title: "Heat", imagePath: "/heat.jpg")
        _ = try await repository.add(draft: draft, listID: watchlist.id, at: TestMovies.date("2024-04-01"))
        _ = try await repository.add(draft: draft, listID: custom.id)
        let rated = TestMovies.date("2024-05-01")

        let change = try await repository.addToWatched(draft, at: rated)

        XCTAssertEqual(change.action, .added)
        XCTAssertEqual(change.confirmation, "Added to Watched")
        XCTAssertEqual(change.restore?.listID, watchlist.id)
        let snapshot = try await repository.snapshot()
        let watched = try XCTUnwrap(snapshot.list(.watched))
        let entry = try XCTUnwrap(snapshot.entries.first { $0.listID == watched.id && $0.itemID == 15 })
        XCTAssertEqual(entry.addedAt, rated)
        XCTAssertEqual(entry.title, "Heat")
        XCTAssertFalse(snapshot.entries.contains { $0.listID == watchlist.id && $0.itemID == 15 })
        XCTAssertTrue(snapshot.entries.contains { $0.listID == custom.id && $0.itemID == 15 })
    }

    func test_addToWatched_again_keepsTheAddedDate() async throws {
        let repository = makeRepository()
        let draft = movie(id: 15, title: "Heat")
        let rated = TestMovies.date("2024-05-01")
        _ = try await repository.addToWatched(draft, at: rated)

        let again = try await repository.addToWatched(draft, at: TestMovies.date("2024-08-01"))

        XCTAssertEqual(again.action, .unchanged)
        XCTAssertNil(again.confirmation)
        let snapshot = try await repository.snapshot()
        let watched = try XCTUnwrap(snapshot.list(.watched))
        let matches = snapshot.entries.filter { $0.listID == watched.id && $0.itemID == 15 }
        XCTAssertEqual(matches.count, 1)
        XCTAssertEqual(matches.first?.addedAt, rated)
    }

    func test_sync_movesAWatchlistMovieUsingTheStoredRow() async throws {
        let lists = makeRepository()
        let annotations = AnnotationsRepository(store: InMemoryAnnotationsStore(), logger: SilentLogger())
        let watchlist = try await systemList(.watchlist, repository: lists)
        let draft = movie(id: 15, title: "Heat", imagePath: "/heat.jpg")
        _ = try await lists.add(draft: draft, listID: watchlist.id, at: TestMovies.date("2024-04-01"))
        let rated = TestMovies.date("2020-03-01")
        _ = try await annotations.saveScore(9, for: .movie(15), at: rated)
        let movies = MovieRepository.test(
            client: FakeHTTPClient(stub: .success(TMDBFixtures.movieDetailShawshank))
        )

        await WatchedRatings.sync(
            annotations: annotations,
            lists: lists,
            movies: movies,
            logger: SilentLogger()
        )

        let snapshot = try await lists.snapshot()
        let watched = try XCTUnwrap(snapshot.list(.watched))
        let entry = try XCTUnwrap(snapshot.entries.first { $0.listID == watched.id })
        XCTAssertEqual(entry.itemID, 15)
        XCTAssertEqual(entry.title, "Heat")
        XCTAssertEqual(entry.imagePath, "/heat.jpg")
        XCTAssertEqual(entry.addedAt, rated)
        XCTAssertFalse(snapshot.entries.contains { $0.listID == watchlist.id })
    }

    func test_sync_loadsAScoredMovieThatIsNotOnAList() async throws {
        let lists = makeRepository()
        let annotations = AnnotationsRepository(store: InMemoryAnnotationsStore(), logger: SilentLogger())
        let rated = TestMovies.date("2019-06-01")
        _ = try await annotations.saveScore(8, for: .movie(278), at: rated)
        let movies = MovieRepository.test(
            client: FakeHTTPClient(stub: .success(TMDBFixtures.movieDetailShawshank))
        )

        await WatchedRatings.sync(
            annotations: annotations,
            lists: lists,
            movies: movies,
            logger: SilentLogger()
        )

        let snapshot = try await lists.snapshot()
        let watched = try XCTUnwrap(snapshot.list(.watched))
        let entry = try XCTUnwrap(snapshot.entries.first { $0.listID == watched.id })
        XCTAssertEqual(entry.itemID, 278)
        XCTAssertEqual(entry.title, "The Shawshank Redemption")
        XCTAssertEqual(entry.addedAt, rated)
    }

    func test_sync_ignoresNotesAndSeriesScores() async throws {
        let lists = makeRepository()
        let annotations = AnnotationsRepository(store: InMemoryAnnotationsStore(), logger: SilentLogger())
        _ = try await annotations.saveNote("Just a note", for: .movie(278))
        _ = try await annotations.saveScore(9, for: .series(1396), at: TestMovies.date("2021-01-01"))
        let movies = MovieRepository.test(
            client: FakeHTTPClient(stub: .success(TMDBFixtures.movieDetailShawshank))
        )

        await WatchedRatings.sync(
            annotations: annotations,
            lists: lists,
            movies: movies,
            logger: SilentLogger()
        )

        let snapshot = try await lists.snapshot()
        let watched = try XCTUnwrap(snapshot.list(.watched))
        XCTAssertFalse(snapshot.entries.contains { $0.listID == watched.id })
    }

    func test_sync_leavesAnExistingWatchedDateAlone() async throws {
        let lists = makeRepository()
        let annotations = AnnotationsRepository(store: InMemoryAnnotationsStore(), logger: SilentLogger())
        let watched = try await systemList(.watched, repository: lists)
        let added = TestMovies.date("2018-01-01")
        _ = try await lists.add(
            draft: movie(id: 278, title: "The Shawshank Redemption"),
            listID: watched.id,
            at: added
        )
        _ = try await annotations.saveScore(8, for: .movie(278), at: TestMovies.date("2022-01-01"))
        let movies = MovieRepository.test(
            client: FakeHTTPClient(stub: .success(TMDBFixtures.movieDetailShawshank))
        )

        await WatchedRatings.sync(
            annotations: annotations,
            lists: lists,
            movies: movies,
            logger: SilentLogger()
        )

        let snapshot = try await lists.snapshot()
        let matches = snapshot.entries.filter { $0.listID == watched.id && $0.itemID == 278 }
        XCTAssertEqual(matches.count, 1)
        XCTAssertEqual(matches.first?.addedAt, added)
    }

    func test_addToWatched_removesWatchlistEntryAndLeavesCustomList() async throws {
        let repository = makeRepository()
        let watched = try await systemList(.watched, repository: repository)
        let watchlist = try await systemList(.watchlist, repository: repository)
        let custom = try await repository.createList(name: "Friday", segment: .moviesAndTV).list
        let draft = movie(id: 15, title: "Heat")
        _ = try await repository.add(draft: draft, listID: watchlist.id)
        _ = try await repository.add(draft: draft, listID: custom.id)

        let change = try await repository.add(draft: draft, listID: watched.id, at: TestMovies.date("2024-05-01"))

        XCTAssertEqual(change.action, .added)
        XCTAssertEqual(change.restore?.listID, watchlist.id)
        let snapshot = try await repository.snapshot()
        XCTAssertFalse(snapshot.entries.contains { $0.listID == watchlist.id && $0.itemID == 15 })
        XCTAssertTrue(snapshot.entries.contains { $0.listID == watched.id && $0.itemID == 15 })
        XCTAssertTrue(snapshot.entries.contains { $0.listID == custom.id && $0.itemID == 15 })
    }

    func test_undoAddToWatched_restoresWatchlistMembership() async throws {
        let repository = makeRepository()
        let watched = try await systemList(.watched, repository: repository)
        let watchlist = try await systemList(.watchlist, repository: repository)
        let draft = movie(id: 15, title: "Heat")
        _ = try await repository.add(draft: draft, listID: watchlist.id, at: TestMovies.date("2024-04-01"))
        let added = try await repository.add(draft: draft, listID: watched.id, at: TestMovies.date("2024-05-01"))

        try await repository.undo(added)

        let snapshot = try await repository.snapshot()
        let restored = snapshot.entries.filter { $0.itemID == 15 }
        XCTAssertEqual(restored.map(\.listID), [watchlist.id])
        XCTAssertEqual(restored.first?.addedAt, TestMovies.date("2024-04-01"))
    }

    func test_duplicateAndEmptyNamesFail() async throws {
        let repository = makeRepository()
        _ = try await repository.createList(name: "Friday", segment: .moviesAndTV)

        await assertNameError(.duplicateName) {
            _ = try await repository.createList(name: " friday ", segment: .moviesAndTV)
        }
        await assertNameError(.emptyName) {
            _ = try await repository.createList(name: "   ", segment: .moviesAndTV)
        }
        await assertNameError(.duplicateName) {
            _ = try await repository.createList(name: "Watchlist", segment: .moviesAndTV)
        }

        let people = try await repository.createList(name: "Watchlist", segment: .people)
        XCTAssertEqual(people.list.name, "Watchlist")
    }

    func test_systemList_cannotBeDeletedOrRenamed() async throws {
        let repository = makeRepository()
        let watched = try await systemList(.watched, repository: repository)

        do {
            try await repository.deleteList(id: watched.id)
            XCTFail("Expected system list to stay")
        } catch let error as ListEditError {
            XCTAssertEqual(error, .systemListLocked)
        }
        do {
            try await repository.renameList(id: watched.id, name: "Seen")
            XCTFail("Expected system list to stay")
        } catch let error as ListEditError {
            XCTAssertEqual(error, .systemListLocked)
        }

        let snapshot = try await repository.snapshot()
        XCTAssertEqual(snapshot.list(.watched)?.name, "Watched")
    }

    func test_deleteCustomList_keepsTitleOnOtherLists() async throws {
        let repository = makeRepository()
        let first = try await repository.createList(name: "One", segment: .moviesAndTV).list
        let second = try await repository.createList(name: "Two", segment: .moviesAndTV).list
        let draft = movie(id: 9, title: "Heat")
        _ = try await repository.add(draft: draft, listID: first.id)
        _ = try await repository.add(draft: draft, listID: second.id)

        try await repository.deleteList(id: first.id)

        let snapshot = try await repository.snapshot()
        XCTAssertNil(snapshot.lists.first { $0.id == first.id })
        XCTAssertTrue(snapshot.entries.contains { $0.listID == second.id && $0.itemID == 9 })
    }

    func test_movieAndPerson_sameID_stayDistinct() async throws {
        let index = ListsIndex()
        let tracked = ListsRepository(store: InMemoryListsStore(), logger: SilentLogger(), index: index)
        let watchlist = try await systemList(.watchlist, repository: tracked)
        let people = try await tracked.createList(name: "Cast", segment: .people).list

        _ = try await tracked.add(draft: movie(id: 500, title: "Reservoir Dogs"), listID: watchlist.id)
        _ = try await tracked.add(draft: person(id: 500, title: "Tom Cruise"), listID: people.id)

        let snapshot = try await tracked.snapshot()
        XCTAssertEqual(Set(snapshot.entries.map(\.itemKey)), ["movie-500", "person-500"])
        XCTAssertTrue(index.contains("movie-500"))
        XCTAssertTrue(index.contains("person-500"))
        XCTAssertTrue(index.contains("movie-500", listID: watchlist.id))
        XCTAssertFalse(index.contains("person-500", listID: watchlist.id))
    }

    func test_add_whenAlreadyOnList_isUnchanged() async throws {
        let repository = makeRepository()
        let watchlist = try await systemList(.watchlist, repository: repository)
        let draft = movie(id: 4, title: "Once")
        _ = try await repository.add(draft: draft, listID: watchlist.id, at: TestMovies.date("2024-01-01"))

        let again = try await repository.add(draft: draft, listID: watchlist.id, at: TestMovies.date("2024-08-01"))

        XCTAssertEqual(again.action, .unchanged)
        XCTAssertNil(again.confirmation)
        let snapshot = try await repository.snapshot()
        let entries = snapshot.entries.filter { $0.listID == watchlist.id }
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.addedAt, TestMovies.date("2024-01-01"))
    }

    func test_add_whenSaveFails_throwsPersistence() async {
        let store = InMemoryListsStore()
        await store.setSaveError(CocoaError(.fileWriteUnknown))
        let repository = ListsRepository(store: store, logger: SilentLogger())

        do {
            _ = try await repository.snapshot()
            XCTFail("Expected persistence error")
        } catch let error as AppError {
            XCTAssertEqual(error, .persistence)
        } catch {
            XCTFail("Expected AppError, got \(error)")
        }
    }

    func test_snapshot_whenLoadFails_throwsPersistence() async {
        let store = InMemoryListsStore()
        await store.setLoadError(CocoaError(.fileReadUnknown))
        let repository = ListsRepository(store: store, logger: SilentLogger())

        do {
            _ = try await repository.snapshot()
            XCTFail("Expected persistence error")
        } catch let error as AppError {
            XCTAssertEqual(error, .persistence)
        } catch {
            XCTFail("Expected AppError, got \(error)")
        }
    }

    func test_concurrentAdds_allPersist() async throws {
        let repository = makeRepository()
        let watchlist = try await systemList(.watchlist, repository: repository)
        let drafts = (0..<20).map { movie(id: $0, title: "Movie \($0)") }

        await withTaskGroup(of: Void.self) { group in
            for draft in drafts {
                group.addTask {
                    _ = try? await repository.add(
                        draft: draft,
                        listID: watchlist.id,
                        at: TestMovies.date("2024-01-01")
                    )
                }
            }
        }

        let snapshot = try await repository.snapshot()
        let ids = Set(snapshot.entries.filter { $0.listID == watchlist.id }.map(\.itemID))
        XCTAssertEqual(ids, Set(drafts.map(\.id)))
    }

    func test_findList_matchesMemberTitle() async throws {
        let repository = makeRepository()
        let list = try await repository.createList(
            name: "Noir",
            segment: .moviesAndTV,
            adding: movie(id: 8, title: "The Third Man")
        ).list
        let snapshot = try await repository.snapshot()

        let matches = LibraryQuery.lists(in: .moviesAndTV, snapshot: snapshot, matching: "third")

        XCTAssertEqual(matches.map(\.id), [list.id])
    }

    func test_genreCatalog_mapsKnownIds() {
        XCTAssertEqual(MovieGenreCatalog.names(for: [18, 80]), ["Drama", "Crime"])
        XCTAssertEqual(MovieGenreCatalog.names(for: [99999]), [])
    }

    private func makeRepository() -> ListsRepository {
        ListsRepository(store: InMemoryListsStore(), logger: SilentLogger())
    }

    private func systemList(_ kind: SystemListKind, repository: ListsRepository) async throws -> LibraryList {
        let snapshot = try await repository.snapshot()
        return try XCTUnwrap(snapshot.list(kind))
    }

    private func movie(
        id: Int,
        title: String,
        vote: Double = 0,
        popularity: Double = 0,
        date: Date? = nil,
        genres: [String] = [],
        imagePath: String? = nil
    ) -> ListItemDraft {
        ListItemDraft(
            id: id,
            kind: .movie,
            title: title,
            imagePath: imagePath,
            releaseDate: date,
            genreNames: genres,
            voteAverage: vote,
            popularity: popularity
        )
    }

    private func person(id: Int, title: String) -> ListItemDraft {
        ListItemDraft(
            id: id,
            kind: .person,
            title: title,
            imagePath: nil,
            releaseDate: nil,
            genreNames: ["Acting"],
            voteAverage: 0,
            popularity: 1
        )
    }

    private func assertNameError(
        _ expected: ListEditError,
        _ body: () async throws -> Void
    ) async {
        do {
            try await body()
            XCTFail("Expected \(expected)")
        } catch let error as ListEditError {
            XCTAssertEqual(error, expected)
        } catch {
            XCTFail("Expected ListEditError, got \(error)")
        }
    }
}

final class ListSnapshotMappingTests: XCTestCase {
    func test_movieDetail_passesPopularityAndStoresZeroWhenOmitted() throws {
        let withPopularity = try decodeMovie(#"{"id":7,"title":"Heat","vote_average":8.2,"popularity":55.5}"#)
        XCTAssertEqual(withPopularity.popularity, 55.5)
        XCTAssertEqual(withPopularity.listItem().voteAverage, 8.2)
        XCTAssertEqual(withPopularity.listItem().popularity, 55.5)

        let omitted = try decodeMovie(#"{"id":7,"title":"Heat","vote_average":8.2}"#)
        XCTAssertEqual(omitted.popularity, 0)
        XCTAssertEqual(omitted.listItem().popularity, 0)
    }

    func test_tvDetail_passesPopularityAndStoresZeroWhenOmitted() throws {
        let withPopularity = try decodeSeries(#"{"id":3,"name":"The Wire","vote_average":9.3,"popularity":70}"#)
        XCTAssertEqual(withPopularity.popularity, 70)
        XCTAssertEqual(withPopularity.listItem().voteAverage, 9.3)

        let omitted = try decodeSeries(#"{"id":3,"name":"The Wire","vote_average":9.3}"#)
        XCTAssertEqual(omitted.popularity, 0)
        XCTAssertEqual(omitted.listItem().popularity, 0)
    }

    func test_personCredit_passesVoteAverageAndStoresZeroWhenOmitted() throws {
        let data = #"{"id":42,"media_type":"movie","title":"Heat","vote_average":8.1,"popularity":12,"genre_ids":[80]}"#
            .data(using: .utf8)!
        let dto = try JSONDecoder().decode(PersonCombinedCreditDTO.self, from: data)
        let credit = try XCTUnwrap(PersonRepository.mapCastCredits([dto], logger: SilentLogger()).first)
        XCTAssertEqual(credit.voteAverage, 8.1)
        XCTAssertEqual(credit.listItem().popularity, 12)
        XCTAssertEqual(credit.listItem().voteAverage, 8.1)

        let omittedData = #"{"id":42,"media_type":"movie","title":"Heat","popularity":12}"#.data(using: .utf8)!
        let omitted = try JSONDecoder().decode(PersonCombinedCreditDTO.self, from: omittedData)
        let zero = try XCTUnwrap(PersonRepository.mapCastCredits([omitted], logger: SilentLogger()).first)
        XCTAssertEqual(zero.voteAverage, 0)
    }

    func test_browseAndCatalogRows_keepPopularityAndVoteAverage() {
        let movie = TestMovies.make(id: 4, title: "Heat", voteAverage: 6, popularity: 33)
        let browse = BrowseRow(candidate: .movie(movie))
        XCTAssertEqual(browse.asMovie().popularity, 33)
        XCTAssertEqual(browse.listItem().popularity, 33)
        XCTAssertEqual(browse.listItem().voteAverage, 6)

        let catalog = CatalogMovieRow(movie: movie)
        XCTAssertEqual(catalog.asMovie().popularity, 33)
        XCTAssertEqual(catalog.listItem().voteAverage, 6)

        let series = TVSeriesSummary(
            id: 9,
            name: "Show",
            posterPath: nil,
            firstAirDate: nil,
            genreIDs: [],
            voteAverage: 4,
            popularity: 9
        )
        let tv = CatalogTVRow(series: series)
        XCTAssertEqual(tv.listItem().voteAverage, 4)
        XCTAssertEqual(tv.listItem().popularity, 9)
    }

    func test_seriesListSnapshot_prefersSeasonPosterThenFallsBackToSeries() throws {
        let detail = try decodeSeries(
            #"{"id":99,"name":"Alone: Frozen","poster_path":"/series.jpg","first_air_date":"2022-08-11","genres":[{"id":10764,"name":"Reality"}],"vote_average":7.5,"popularity":12}"#
        )
        let snapshot = SeriesListSnapshot(detail: detail)

        let withSeasonArt = snapshot.listItem(id: 99, title: "Alone: Frozen", imagePath: "/season.jpg")
        XCTAssertEqual(withSeasonArt.imagePath, "/season.jpg")
        XCTAssertEqual(withSeasonArt.releaseDate, TestMovies.date("2022-08-11"))
        XCTAssertEqual(withSeasonArt.genreNames, ["Reality"])
        XCTAssertEqual(withSeasonArt.voteAverage, 7.5)

        let episodeDraft = snapshot.listItem(id: 99, title: "Alone: Frozen")
        XCTAssertEqual(episodeDraft.imagePath, "/series.jpg")
        XCTAssertEqual(episodeDraft.releaseDate, TestMovies.date("2022-08-11"))

        let missingSeasonArt = snapshot.listItem(id: 99, title: "Alone: Frozen", imagePath: nil)
        XCTAssertEqual(missingSeasonArt.imagePath, "/series.jpg")
    }

    private func decodeMovie(_ json: String) throws -> MovieDetail {
        let dto = try JSONDecoder().decode(MovieDetailDTO.self, from: Data(json.utf8))
        return MovieRepository.map(dto, trailers: [], logger: SilentLogger())
    }

    private func decodeSeries(_ json: String) throws -> TVSeriesDetail {
        let dto = try JSONDecoder().decode(TVSeriesDetailDTO.self, from: Data(json.utf8))
        return TVRepository.mapSeries(
            dto,
            logger: SilentLogger(),
            images: [],
            recommendations: [],
            cast: [],
            directorsAndWriters: [],
            trailers: []
        )
    }
}
