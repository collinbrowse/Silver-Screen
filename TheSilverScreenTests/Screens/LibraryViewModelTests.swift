//
//  LibraryViewModelTests.swift
//  TheSilverScreenTests
//

import XCTest
@testable import TheSilverScreen

@MainActor
final class LibraryViewModelTests: XCTestCase {

    func test_findList_matchesMemberTitle() async throws {
        let repository = ListsRepository(store: InMemoryListsStore(), logger: SilentLogger())
        let viewModel = LibraryHomeViewModel(lists: repository)
        _ = try await repository.createList(
            name: "Noir",
            segment: .moviesAndTV,
            adding: ListItemDraft(
                id: 8,
                kind: .movie,
                title: "The Third Man",
                imagePath: nil,
                releaseDate: nil,
                genreNames: ["Drama"],
                voteAverage: 8,
                popularity: 3
            )
        )
        await viewModel.load()

        viewModel.searchText = "third"

        XCTAssertEqual(viewModel.displayedLists.map(\.name), ["Noir"])
    }

    func test_displayedLists_keepSystemListsPinned() async throws {
        let repository = ListsRepository(store: InMemoryListsStore(), logger: SilentLogger())
        let viewModel = LibraryHomeViewModel(lists: repository)
        _ = try await repository.createList(name: "Friday", segment: .moviesAndTV)
        await viewModel.load()

        XCTAssertEqual(
            viewModel.displayedLists.prefix(3).map(\.name),
            ["Watched", "In Progress", "Watchlist"]
        )
        XCTAssertEqual(viewModel.displayedLists.last?.name, "Friday")
        XCTAssertTrue(viewModel.canReorderLists)
    }

    func test_createList_duplicateName_setsNameError() async throws {
        let repository = ListsRepository(store: InMemoryListsStore(), logger: SilentLogger())
        let viewModel = LibraryHomeViewModel(lists: repository)
        await viewModel.load()

        let saved = await viewModel.createList(named: "Watched")

        XCTAssertFalse(saved)
        XCTAssertEqual(viewModel.nameError, ListEditError.duplicateName.message)
        XCTAssertEqual(viewModel.displayedLists.map(\.name), ["Watched", "In Progress", "Watchlist"])
    }

    func test_detail_dateAddedIsDefaultAndReorderIsDisabledForWatched() async throws {
        let repository = ListsRepository(store: InMemoryListsStore(), logger: SilentLogger())
        let snapshot = try await repository.snapshot()
        let watched = try XCTUnwrap(snapshot.list(.watched))
        _ = try await repository.add(
            draft: ListItemDraft(
                id: 1,
                kind: .movie,
                title: "Older",
                imagePath: nil,
                releaseDate: TestMovies.date("1990-01-01"),
                genreNames: [],
                voteAverage: 1,
                popularity: 1
            ),
            listID: watched.id,
            at: TestMovies.date("2024-01-01")
        )
        _ = try await repository.add(
            draft: ListItemDraft(
                id: 2,
                kind: .movie,
                title: "Newer",
                imagePath: nil,
                releaseDate: TestMovies.date("2020-01-01"),
                genreNames: [],
                voteAverage: 9,
                popularity: 2
            ),
            listID: watched.id,
            at: TestMovies.date("2024-06-01")
        )
        let viewModel = LibraryDetailViewModel(
            listID: watched.id,
            lists: repository,
            annotations: AnnotationsRepository.empty()
        )

        await viewModel.load()

        guard case .loaded(let detail, _) = viewModel.state else {
            return XCTFail("Expected loaded, got \(viewModel.state)")
        }
        XCTAssertEqual(detail.list.sort, .dateAdded)
        XCTAssertEqual(viewModel.displayedEntries.map(\.title), ["Newer", "Older"])
        XCTAssertFalse(viewModel.allowsReorder)
    }

    func test_detail_reorderDisabledWhileSearchHidesRows() async throws {
        let repository = ListsRepository(store: InMemoryListsStore(), logger: SilentLogger())
        let list = try await repository.createList(name: "Friday", segment: .moviesAndTV).list
        for (id, title) in [(1, "Heat"), (2, "Alien")] {
            _ = try await repository.add(
                draft: ListItemDraft(
                    id: id,
                    kind: .movie,
                    title: title,
                    imagePath: nil,
                    releaseDate: nil,
                    genreNames: [],
                    voteAverage: 0,
                    popularity: 0
                ),
                listID: list.id
            )
        }
        let viewModel = LibraryDetailViewModel(
            listID: list.id,
            lists: repository,
            annotations: AnnotationsRepository.empty()
        )
        await viewModel.load()
        XCTAssertTrue(viewModel.allowsReorder)

        viewModel.searchText = "Heat"

        XCTAssertEqual(viewModel.displayedEntries.map(\.title), ["Heat"])
        XCTAssertFalse(viewModel.allowsReorder)
    }

    func test_detail_topRatedSortUsesStoredVoteAverage() async throws {
        let repository = ListsRepository(store: InMemoryListsStore(), logger: SilentLogger())
        let snapshot = try await repository.snapshot()
        let watchlist = try XCTUnwrap(snapshot.list(.watchlist))
        _ = try await repository.add(
            draft: ListItemDraft(
                id: 1,
                kind: .movie,
                title: "Low",
                imagePath: nil,
                releaseDate: nil,
                genreNames: [],
                voteAverage: 2,
                popularity: 90
            ),
            listID: watchlist.id,
            at: TestMovies.date("2024-01-01")
        )
        _ = try await repository.add(
            draft: ListItemDraft(
                id: 2,
                kind: .movie,
                title: "High",
                imagePath: nil,
                releaseDate: nil,
                genreNames: [],
                voteAverage: 9,
                popularity: 1
            ),
            listID: watchlist.id,
            at: TestMovies.date("2024-02-01")
        )
        let viewModel = LibraryDetailViewModel(
            listID: watchlist.id,
            lists: repository,
            annotations: AnnotationsRepository.empty()
        )
        await viewModel.load()

        await viewModel.setSort(.topRated)

        XCTAssertEqual(viewModel.displayedEntries.map(\.title), ["High", "Low"])
    }

    func test_artwork_systemListsStayIconsWhenTheyHavePosters() async throws {
        let repository = ListsRepository(store: InMemoryListsStore(), logger: SilentLogger())
        let viewModel = LibraryHomeViewModel(lists: repository)
        await viewModel.load()
        let snapshot = try await repository.snapshot()
        let watched = try XCTUnwrap(snapshot.list(.watched))
        let inProgress = try XCTUnwrap(snapshot.list(.inProgress))
        let watchlist = try XCTUnwrap(snapshot.list(.watchlist))
        _ = try await repository.add(draft: draft(id: 1, title: "Heat", imagePath: "/heat.jpg"), listID: watched.id)
        _ = try await repository.add(draft: draft(id: 2, title: "Alien", imagePath: "/alien.jpg"), listID: watchlist.id)
        _ = try await repository.add(
            draft: draft(id: 3, title: "Severance", imagePath: "/sev.jpg"),
            listID: inProgress.id
        )
        await viewModel.load()

        XCTAssertEqual(viewModel.artwork(for: watched), .watched)
        XCTAssertEqual(viewModel.artwork(for: inProgress), .inProgress)
        XCTAssertEqual(viewModel.artwork(for: watchlist), .watchlist)
    }

    func test_artwork_customListUsesFirstFourPathsInDisplayOrder() async throws {
        let repository = ListsRepository(store: InMemoryListsStore(), logger: SilentLogger())
        let viewModel = LibraryHomeViewModel(lists: repository)
        let list = try await repository.createList(name: "Friday", segment: .moviesAndTV).list
        for id in 1...5 {
            _ = try await repository.add(
                draft: draft(id: id, title: "Title \(id)", imagePath: "/\(id).jpg"),
                listID: list.id
            )
        }
        await viewModel.load()

        XCTAssertEqual(viewModel.artwork(for: list), .images(["/5.jpg", "/4.jpg", "/3.jpg", "/2.jpg"]))
    }

    func test_artwork_customListSkipsBlankPaths() async throws {
        let repository = ListsRepository(store: InMemoryListsStore(), logger: SilentLogger())
        let viewModel = LibraryHomeViewModel(lists: repository)
        let list = try await repository.createList(name: "Friday", segment: .moviesAndTV).list
        let paths: [String?] = ["/keep-late.jpg", nil, "   ", "/keep-early.jpg"]
        for (id, path) in paths.enumerated() {
            _ = try await repository.add(
                draft: draft(id: id + 1, title: "Title \(id)", imagePath: path),
                listID: list.id
            )
        }
        await viewModel.load()

        XCTAssertEqual(viewModel.artwork(for: list), .images(["/keep-early.jpg", "/keep-late.jpg"]))
    }

    func test_artwork_customListDedupesPaths() async throws {
        let repository = ListsRepository(store: InMemoryListsStore(), logger: SilentLogger())
        let viewModel = LibraryHomeViewModel(lists: repository)
        let list = try await repository.createList(name: "Friday", segment: .moviesAndTV).list
        let paths = ["/extra.jpg", "/b.jpg", "/a.jpg", "/a.jpg", "/c.jpg", "/d.jpg"]
        for (id, path) in paths.enumerated() {
            _ = try await repository.add(
                draft: draft(id: id + 1, title: "Title \(id)", imagePath: path),
                listID: list.id
            )
        }
        await viewModel.load()

        XCTAssertEqual(viewModel.artwork(for: list), .images(["/d.jpg", "/c.jpg", "/a.jpg", "/b.jpg"]))
    }

    func test_artwork_emptyCustomListHasNoPaths() async throws {
        let repository = ListsRepository(store: InMemoryListsStore(), logger: SilentLogger())
        let viewModel = LibraryHomeViewModel(lists: repository)
        let list = try await repository.createList(name: "Friday", segment: .moviesAndTV).list
        await viewModel.load()

        XCTAssertEqual(viewModel.artwork(for: list), .images([]))
    }

    func test_artwork_peopleListUsesProfilePaths() async throws {
        let repository = ListsRepository(store: InMemoryListsStore(), logger: SilentLogger())
        let viewModel = LibraryHomeViewModel(lists: repository)
        let list = try await repository.createList(name: "Directors", segment: .people).list
        _ = try await repository.add(
            draft: draft(id: 9, title: "Agnes", imagePath: "/face.jpg", kind: .person),
            listID: list.id
        )
        await viewModel.load()

        XCTAssertEqual(viewModel.artwork(for: list), .images(["/face.jpg"]))
    }

    func test_detail_inProgressTVRouteOpensSeasonScrolledToLastWatched() async throws {
        let lists = ListsRepository(store: InMemoryListsStore(), logger: SilentLogger())
        let tvWatch = TVWatchRepository(
            store: InMemoryTVWatchStore(),
            lists: lists,
            logger: SilentLogger()
        )
        let seriesDraft = ListItemDraft(
            id: 42,
            kind: .tv,
            title: "Severance",
            imagePath: "/sev.jpg",
            releaseDate: nil,
            genreNames: ["Drama"],
            voteAverage: 8,
            popularity: 10
        )
        let seasons = [
            TVSeasonSummary(
                id: 1,
                name: "Season 1",
                seasonNumber: 1,
                episodeCount: 5,
                airDate: nil,
                posterPath: nil
            )
        ]
        _ = try await tvWatch.markEpisode(
            seriesID: 42,
            seasonNumber: 1,
            episodeNumber: 2,
            title: "Half Loop",
            draft: seriesDraft,
            seasons: seasons
        )
        let snapshot = try await lists.snapshot()
        let inProgress = try XCTUnwrap(snapshot.list(.inProgress))
        let viewModel = LibraryDetailViewModel(
            listID: inProgress.id,
            lists: lists,
            annotations: AnnotationsRepository.empty(),
            tvWatch: tvWatch
        )
        await viewModel.load()
        let entry = try XCTUnwrap(viewModel.displayedEntries.first)

        let route = viewModel.route(for: entry)

        XCTAssertEqual(
            route,
            .tvSeason(
                seriesID: 42,
                seriesName: "Severance",
                seasonNumber: 1,
                seriesSnapshot: SeriesListSnapshot(entry: entry),
                scrollToEpisodeNumber: 2
            )
        )
    }

    func test_detail_watchedTVRouteOpensSeries() async throws {
        let lists = ListsRepository(store: InMemoryListsStore(), logger: SilentLogger())
        let snapshot = try await lists.snapshot()
        let watched = try XCTUnwrap(snapshot.list(.watched))
        _ = try await lists.add(
            draft: draft(id: 7, title: "Finished Show", imagePath: "/done.jpg", kind: .tv),
            listID: watched.id
        )
        let viewModel = LibraryDetailViewModel(
            listID: watched.id,
            lists: lists,
            annotations: AnnotationsRepository.empty()
        )
        await viewModel.load()
        let entry = try XCTUnwrap(viewModel.displayedEntries.first)

        XCTAssertEqual(viewModel.route(for: entry), .tvSeries(id: 7))
    }

    func test_detail_inProgressCaption_usesProgressSubtitle() async throws {
        let lists = ListsRepository(store: InMemoryListsStore(), logger: SilentLogger())
        let tvWatch = TVWatchRepository(
            store: InMemoryTVWatchStore(),
            lists: lists,
            logger: SilentLogger()
        )
        let seriesDraft = draft(id: 42, title: "Severance", imagePath: "/sev.jpg", kind: .tv)
        let seasons = [
            TVSeasonSummary(
                id: 1,
                name: "Season 1",
                seasonNumber: 1,
                episodeCount: 5,
                airDate: nil,
                posterPath: nil
            ),
        ]
        _ = try await tvWatch.markEpisode(
            seriesID: 42,
            seasonNumber: 1,
            episodeNumber: 2,
            title: "Half Loop",
            draft: seriesDraft,
            seasons: seasons,
            knownTitles: [
                TVEpisodeRef(seasonNumber: 1, episodeNumber: 3): "In Perpetuity",
            ]
        )
        let snapshot = try await lists.snapshot()
        let inProgress = try XCTUnwrap(snapshot.list(.inProgress))
        let viewModel = LibraryDetailViewModel(
            listID: inProgress.id,
            lists: lists,
            annotations: AnnotationsRepository.empty(),
            tvWatch: tvWatch
        )
        await viewModel.load()
        let entry = try XCTUnwrap(viewModel.displayedEntries.first)

        XCTAssertEqual(
            viewModel.progressCaptions[entry.itemKey],
            "Next up: S1 · E3 · In Perpetuity"
        )
    }

    func test_detail_watchedCaption_usesSeasonCount() async throws {
        let lists = ListsRepository(store: InMemoryListsStore(), logger: SilentLogger())
        let tvWatch = TVWatchRepository(
            store: InMemoryTVWatchStore(),
            lists: lists,
            logger: SilentLogger()
        )
        let seriesDraft = draft(id: 9, title: "Done", imagePath: "/d.jpg", kind: .tv)
        let seasons = [
            TVSeasonSummary(
                id: 1,
                name: "Season 1",
                seasonNumber: 1,
                episodeCount: 1,
                airDate: nil,
                posterPath: nil
            ),
            TVSeasonSummary(
                id: 2,
                name: "Season 2",
                seasonNumber: 2,
                episodeCount: 1,
                airDate: nil,
                posterPath: nil
            ),
        ]
        _ = try await tvWatch.markSeries(seriesID: 9, seasons: seasons, draft: seriesDraft)
        let snapshot = try await lists.snapshot()
        let watched = try XCTUnwrap(snapshot.list(.watched))
        let viewModel = LibraryDetailViewModel(
            listID: watched.id,
            lists: lists,
            annotations: AnnotationsRepository.empty(),
            tvWatch: tvWatch
        )
        await viewModel.load()
        let entry = try XCTUnwrap(viewModel.displayedEntries.first)

        XCTAssertEqual(viewModel.progressCaptions[entry.itemKey], "2 seasons")
    }

    private func draft(
        id: Int,
        title: String,
        imagePath: String?,
        kind: ListItemKind = .movie
    ) -> ListItemDraft {
        ListItemDraft(
            id: id,
            kind: kind,
            title: title,
            imagePath: imagePath,
            releaseDate: nil,
            genreNames: [],
            voteAverage: 0,
            popularity: 0
        )
    }
}
