//
//  DiaryViewModelTests.swift
//  SilverScreenTests
//

import XCTest
@testable import SilverScreen

@MainActor
final class DiaryViewModelTests: XCTestCase {
    private let locale = Locale(identifier: "en_US")

    func test_load_withNoEntries_isEmpty() async {
        let viewModel = makeViewModel(store: InMemoryDiaryStore())

        await viewModel.load()

        XCTAssertEqual(viewModel.state, .empty)
    }

    func test_load_whenStoreFails_isFailedPersistence() async {
        let store = InMemoryDiaryStore()
        await store.setLoadError(CocoaError(.fileReadCorruptFile))
        let viewModel = makeViewModel(store: store)

        await viewModel.load()

        XCTAssertEqual(viewModel.state, .failed(.persistence))
    }

    func test_load_groupsByMonthNewestFirst() async {
        let september = DiaryFixtures.entry(title: "A", watchedOn: DiaryDay(year: 2026, month: 9, day: 30))
        let earlyOctober = DiaryFixtures.entry(title: "B", watchedOn: DiaryDay(year: 2026, month: 10, day: 2))
        let lateOctober = DiaryFixtures.entry(title: "C", watchedOn: DiaryDay(year: 2026, month: 10, day: 16))
        let viewModel = makeViewModel(store: InMemoryDiaryStore(entries: [september, lateOctober, earlyOctober]))

        await viewModel.load()

        let months = loadedMonths(viewModel)
        XCTAssertEqual(months.map(\.id), ["2026-10", "2026-09"])
        XCTAssertEqual(months.map(\.title), ["October 2026", "September 2026"])
        XCTAssertEqual(months.first?.rows.map(\.title), ["C", "B"])
        XCTAssertEqual(months.last?.rows.map(\.title), ["A"])
    }

    func test_load_rowFormatsDayRatingAndSpokenLabel() async {
        let entry = DiaryFixtures.entry(score: 8, review: "Rules.", isRewatch: true, tags: ["noir"])
        let viewModel = makeViewModel(store: InMemoryDiaryStore(entries: [entry]))

        await viewModel.load()

        let row = try? XCTUnwrap(loadedMonths(viewModel).first?.rows.first)
        XCTAssertEqual(row?.dayNumber, "16")
        XCTAssertEqual(row?.weekday, "Fri")
        XCTAssertEqual(row?.yearText, "1999")
        XCTAssertEqual(row?.ratingText, "8.0")
        XCTAssertEqual(row?.tagsText, "#noir")
        XCTAssertEqual(
            row?.accessibilityLabel,
            "Fight Club, 1999. Watched Friday, October 16, 2026. Rated 8.0 out of 10. Rewatch. Has a review. Tags: noir."
        )
    }

    func test_load_afterRefreshFailure_keepsMonthsWithFailedActivity() async throws {
        let store = InMemoryDiaryStore(entries: [DiaryFixtures.entry()])
        let repository = DiaryRepository(store: store, logger: SilentLogger())
        let viewModel = makeViewModel(repository: repository)
        await viewModel.load()
        let months = loadedMonths(viewModel)
        await store.setSaveError(CocoaError(.fileWriteUnknown))

        await viewModel.delete(try XCTUnwrap(months.first?.rows.first))

        XCTAssertEqual(viewModel.state, .loaded(months, activity: .failed(.persistence)))
    }

    func test_edit_opensSessionWithSavedValues() async throws {
        let entry = DiaryFixtures.entry(score: 6, review: "Fine", isRewatch: true, tags: ["a", "b"])
        let viewModel = makeViewModel(store: InMemoryDiaryStore(entries: [entry]))
        await viewModel.load()

        viewModel.edit(try XCTUnwrap(loadedMonths(viewModel).first?.rows.first))

        let session = try XCTUnwrap(viewModel.editor)
        XCTAssertFalse(session.isNew)
        XCTAssertTrue(session.canDelete)
        XCTAssertEqual(session.draft.score, 6)
        XCTAssertEqual(session.draft.review, "Fine")
        XCTAssertEqual(session.draft.tagsText, "a, b")
        XCTAssertEqual(DiaryDay(session.draft.watchedOn, calendar: DiaryFixtures.utcCalendar), entry.watchedOn)
    }

    func test_save_editedDraft_updatesEntryClosesEditorAndNotesChange() async throws {
        let entry = DiaryFixtures.entry(score: 6)
        let store = InMemoryDiaryStore(entries: [entry])
        let context = makeContext(store: store)
        let viewModel = makeViewModel(context: context)
        await viewModel.load()
        viewModel.edit(try XCTUnwrap(loadedMonths(viewModel).first?.rows.first))
        var draft = try XCTUnwrap(viewModel.editor?.draft)
        draft.score = 9
        draft.watchedOn = DiaryDay(year: 2026, month: 9, day: 1).date(in: DiaryFixtures.utcCalendar)

        let result = await viewModel.save(draft)

        XCTAssertEqual(result, .succeeded)
        XCTAssertNil(viewModel.editor)
        XCTAssertEqual(context.revision, 1)
        let stored = await store.entries
        XCTAssertEqual(stored.count, 1)
        XCTAssertEqual(stored.first?.id, entry.id)
        XCTAssertEqual(stored.first?.score, 9)
        XCTAssertEqual(stored.first?.watchedOn, DiaryDay(year: 2026, month: 9, day: 1))
        XCTAssertEqual(stored.first?.loggedAt, entry.loggedAt)
        XCTAssertEqual(loadedMonths(viewModel).map(\.id), ["2026-09"])
    }

    func test_save_whenStoreFails_keepsEditorOpen() async throws {
        let store = InMemoryDiaryStore(entries: [DiaryFixtures.entry()])
        let viewModel = makeViewModel(store: store)
        await viewModel.load()
        viewModel.edit(try XCTUnwrap(loadedMonths(viewModel).first?.rows.first))
        var draft = try XCTUnwrap(viewModel.editor?.draft)
        draft.review = "Changed"
        await store.setSaveError(CocoaError(.fileWriteUnknown))

        let result = await viewModel.save(draft)

        XCTAssertEqual(result, .failed)
        XCTAssertNotNil(viewModel.editor)
    }

    func test_deleteEditorEntry_removesEntryAndShowsEmpty() async throws {
        let store = InMemoryDiaryStore(entries: [DiaryFixtures.entry()])
        let viewModel = makeViewModel(store: store)
        await viewModel.load()
        viewModel.edit(try XCTUnwrap(loadedMonths(viewModel).first?.rows.first))

        let result = await viewModel.deleteEditorEntry()

        XCTAssertEqual(result, .succeeded)
        XCTAssertNil(viewModel.editor)
        XCTAssertEqual(viewModel.state, .empty)
        let stored = await store.entries
        XCTAssertTrue(stored.isEmpty)
    }

    func test_delete_row_keepsOtherEntries() async throws {
        let kept = DiaryFixtures.entry(title: "Kept", watchedOn: DiaryDay(year: 2026, month: 10, day: 1))
        let removed = DiaryFixtures.entry(title: "Removed")
        let store = InMemoryDiaryStore(entries: [kept, removed])
        let viewModel = makeViewModel(store: store)
        await viewModel.load()
        let row = try XCTUnwrap(loadedMonths(viewModel).first?.rows.first { $0.id == removed.id })

        await viewModel.delete(row)

        XCTAssertEqual(loadedMonths(viewModel).flatMap(\.rows).map(\.title), ["Kept"])
    }

    func test_route_seriesEntry_opensSeries() async throws {
        let viewModel = makeViewModel(store: InMemoryDiaryStore(entries: [DiaryFixtures.entry(subject: .series(42))]))
        await viewModel.load()

        let route = viewModel.route(for: try XCTUnwrap(loadedMonths(viewModel).first?.rows.first))

        XCTAssertEqual(route, .tvSeries(id: 42))
    }

    func test_route_movieEntry_opensMovie() async throws {
        let viewModel = makeViewModel(store: InMemoryDiaryStore(entries: [DiaryFixtures.entry(subject: .movie(550))]))
        await viewModel.load()

        let route = viewModel.route(for: try XCTUnwrap(loadedMonths(viewModel).first?.rows.first))

        XCTAssertEqual(route, .movieDetail(id: 550))
    }

    func test_load_groupsEpisodesByShowAndDay() async {
        let store = InMemoryDiaryStore(episodeWatches: [
            episodeWatch(series: 7, season: 2, episode: 3, at: "2026-10-16T20:00:00.000Z"),
            episodeWatch(series: 7, season: 2, episode: 4, at: "2026-10-16T21:00:00.000Z"),
            episodeWatch(series: 7, season: 2, episode: 5, at: "2026-10-17T20:00:00.000Z"),
            episodeWatch(series: 8, season: 1, episode: 1, at: "2026-10-16T22:00:00.000Z"),
        ])
        let viewModel = makeViewModel(store: store)

        await viewModel.load()

        let groups = episodeGroups(viewModel)
        XCTAssertEqual(groups.map(\.id), ["episodes-7-2026-10-17", "episodes-8-2026-10-16", "episodes-7-2026-10-16"])
        XCTAssertEqual(groups.map(\.episodesText), ["S2 · E5", "S1 · E1", "S2 · E3–E4"])
        XCTAssertEqual(groups.last?.accessibilityLabel, "Show 7. 2 episodes. Watched Friday, October 16, 2026.")
    }

    func test_load_mergesEpisodesAndEntriesByDayNewestFirst() async {
        let entry = DiaryFixtures.entry(title: "Movie", watchedOn: DiaryDay(year: 2026, month: 10, day: 15))
        let store = InMemoryDiaryStore(
            entries: [entry],
            episodeWatches: [episodeWatch(series: 7, season: 1, episode: 1, at: "2026-10-16T20:00:00.000Z")]
        )
        let viewModel = makeViewModel(store: store)

        await viewModel.load()

        let items = loadedMonths(viewModel).first?.items ?? []
        XCTAssertEqual(items.map(\.id), ["episodes-7-2026-10-16", entry.id.uuidString])
        XCTAssertEqual(loadedMonths(viewModel).first?.rows.map(\.title), ["Movie"])
    }

    func test_load_onlyEpisodes_isLoadedNotEmpty() async {
        let store = InMemoryDiaryStore(episodeWatches: [
            episodeWatch(series: 7, season: 1, episode: 1, at: "2026-10-16T20:00:00.000Z"),
        ])
        let viewModel = makeViewModel(store: store)

        await viewModel.load()

        XCTAssertEqual(episodeGroups(viewModel).count, 1)
    }

    func test_load_whenEpisodeHistoryFails_stillShowsEntries() async {
        let store = InMemoryDiaryStore(entries: [DiaryFixtures.entry(title: "Kept")])
        await store.setEpisodeLoadError(CocoaError(.fileReadCorruptFile))
        let viewModel = makeViewModel(store: store)

        await viewModel.load()

        XCTAssertEqual(loadedMonths(viewModel).flatMap(\.rows).map(\.title), ["Kept"])
    }

    func test_route_episodeGroup_opensSeries() async throws {
        let store = InMemoryDiaryStore(episodeWatches: [
            episodeWatch(series: 7, season: 1, episode: 1, at: "2026-10-16T20:00:00.000Z"),
        ])
        let viewModel = makeViewModel(store: store)
        await viewModel.load()

        let route = viewModel.route(for: try XCTUnwrap(episodeGroups(viewModel).first))

        XCTAssertEqual(route, .tvSeries(id: 7))
    }

    func test_load_scopedToMovie_showsOnlyThatTitle() async {
        let store = InMemoryDiaryStore(
            entries: [
                DiaryFixtures.entry(subject: .movie(550), title: "Fight Club"),
                DiaryFixtures.entry(subject: .movie(1), title: "Other"),
            ],
            episodeWatches: [episodeWatch(series: 550, season: 1, episode: 1, at: "2026-10-16T20:00:00.000Z")]
        )
        let viewModel = makeViewModel(store: store, scope: DiaryScope(subject: .movie(550), title: "Fight Club"))

        await viewModel.load()

        XCTAssertEqual(loadedMonths(viewModel).flatMap(\.items).count, 1)
        XCTAssertEqual(loadedMonths(viewModel).flatMap(\.rows).map(\.title), ["Fight Club"])
        XCTAssertEqual(viewModel.navigationTitle, "Fight Club")
        XCTAssertFalse(viewModel.showsTitleLinks)
    }

    func test_load_scopedToSeries_includesItsEpisodesOnly() async {
        let store = InMemoryDiaryStore(
            entries: [DiaryFixtures.entry(subject: .series(7), title: "Show 7")],
            episodeWatches: [
                episodeWatch(series: 7, season: 1, episode: 1, at: "2026-10-16T20:00:00.000Z"),
                episodeWatch(series: 8, season: 1, episode: 1, at: "2026-10-16T20:00:00.000Z"),
            ]
        )
        let viewModel = makeViewModel(store: store, scope: DiaryScope(subject: .series(7), title: "Show 7"))

        await viewModel.load()

        XCTAssertEqual(episodeGroups(viewModel).map(\.seriesID), [7])
        XCTAssertEqual(loadedMonths(viewModel).flatMap(\.rows).count, 1)
    }

    func test_fullDiary_showsTitleLinks() {
        let viewModel = makeViewModel(store: InMemoryDiaryStore())

        XCTAssertEqual(viewModel.navigationTitle, "Diary")
        XCTAssertTrue(viewModel.showsTitleLinks)
        XCTAssertTrue(viewModel.showsRowTitles)
        XCTAssertFalse(viewModel.prefersInlineTitle)
    }

    func test_titleHistory_hidesRowTitlesAndUsesInlineTitle() {
        let viewModel = makeViewModel(
            store: InMemoryDiaryStore(),
            scope: DiaryScope(subject: .movie(550), title: "Spider-Man: Brand New Day")
        )

        XCTAssertFalse(viewModel.showsRowTitles)
        XCTAssertTrue(viewModel.prefersInlineTitle)
    }

    func test_load_laterWatchOfSameTitle_isRewatchAutomatically() async {
        let first = DiaryFixtures.entry(subject: .movie(550), title: "First", watchedOn: DiaryDay(year: 2026, month: 10, day: 1))
        let second = DiaryFixtures.entry(subject: .movie(550), title: "Second", watchedOn: DiaryDay(year: 2026, month: 10, day: 9))
        let other = DiaryFixtures.entry(subject: .movie(1), title: "Other", watchedOn: DiaryDay(year: 2026, month: 10, day: 12))
        let viewModel = makeViewModel(store: InMemoryDiaryStore(entries: [first, second, other]))

        await viewModel.load()

        let rows = loadedMonths(viewModel).flatMap(\.rows)
        XCTAssertEqual(rows.map(\.title), ["Other", "Second", "First"])
        XCTAssertEqual(rows.map(\.isRewatch), [false, true, false])
    }

    func test_load_importedRewatchFlagOnFirstWatch_isKept() async {
        let imported = DiaryFixtures.entry(isRewatch: true)
        let viewModel = makeViewModel(store: InMemoryDiaryStore(entries: [imported]))

        await viewModel.load()

        XCTAssertEqual(loadedMonths(viewModel).first?.rows.first?.isRewatch, true)
    }

    func test_load_deletingFirstWatch_makesNextOneTheFirst() async throws {
        let first = DiaryFixtures.entry(title: "First", watchedOn: DiaryDay(year: 2026, month: 10, day: 1))
        let second = DiaryFixtures.entry(title: "Second", watchedOn: DiaryDay(year: 2026, month: 10, day: 9))
        let viewModel = makeViewModel(store: InMemoryDiaryStore(entries: [first, second]))
        await viewModel.load()

        let firstRow = try XCTUnwrap(loadedMonths(viewModel).flatMap(\.rows).first { $0.id == first.id })
        await viewModel.delete(firstRow)

        XCTAssertEqual(loadedMonths(viewModel).flatMap(\.rows).map(\.isRewatch), [false])
    }

    // MARK: - Helpers

    private func episodeWatch(series: Int, season: Int, episode: Int, at iso: String) -> EpisodeWatch {
        EpisodeWatch(
            seriesID: series,
            seriesTitle: "Show \(series)",
            posterPath: nil,
            episode: TVEpisodeRef(seasonNumber: season, episodeNumber: episode),
            completedAt: LibrarySQLDate.decode(iso)!
        )
    }

    private func episodeGroups(_ viewModel: DiaryViewModel) -> [DiaryEpisodeGroup] {
        loadedMonths(viewModel).flatMap(\.items).compactMap { item -> DiaryEpisodeGroup? in
            guard case .episodes(let group) = item else { return nil }
            return group
        }
    }

    private func makeContext(store: InMemoryDiaryStore) -> DiaryContext {
        DiaryContext(
            diary: DiaryRepository(store: store, logger: SilentLogger()),
            lists: ListsRepository.empty(),
            logger: SilentLogger()
        )
    }

    private func makeViewModel(store: InMemoryDiaryStore, scope: DiaryScope? = nil) -> DiaryViewModel {
        makeViewModel(context: makeContext(store: store), scope: scope)
    }

    private func makeViewModel(repository: DiaryRepository) -> DiaryViewModel {
        makeViewModel(context: DiaryContext(diary: repository, lists: ListsRepository.empty(), logger: SilentLogger()))
    }

    private func makeViewModel(context: DiaryContext, scope: DiaryScope? = nil) -> DiaryViewModel {
        DiaryViewModel(
            context: context,
            scope: scope,
            calendar: DiaryFixtures.utcCalendar,
            locale: locale,
            now: { Date(timeIntervalSince1970: 1_792_000_000) }
        )
    }

    private func loadedMonths(_ viewModel: DiaryViewModel) -> [DiaryMonth] {
        guard case .loaded(let months, _) = viewModel.state else { return [] }
        return months
    }
}

final class DiaryEpisodesTextTests: XCTestCase {
    private func refs(_ pairs: [(Int, Int)]) -> [TVEpisodeRef] {
        pairs.map { TVEpisodeRef(seasonNumber: $0.0, episodeNumber: $0.1) }
    }

    func test_oneEpisode() {
        XCTAssertEqual(DiaryContent.episodesText(refs([(2, 3)])), "S2 · E3")
    }

    func test_runInOneSeason() {
        XCTAssertEqual(DiaryContent.episodesText(refs([(2, 3), (2, 4), (2, 5)])), "S2 · E3–E5")
    }

    func test_gapsInOneSeason_countsEpisodes() {
        XCTAssertEqual(DiaryContent.episodesText(refs([(2, 1), (2, 3), (2, 6), (2, 7)])), "S2 · 4 episodes")
    }

    func test_acrossSeasons_namesSeasonRange() {
        XCTAssertEqual(DiaryContent.episodesText(refs([(1, 9), (1, 10), (3, 1)])), "S1–S3 · 3 episodes")
    }
}

final class DiaryLayoutTests: XCTestCase {
    func test_compactWidth_usesFullWidthAndSmallPosters() {
        let layout = DiaryLayout(width: 393)

        XCTAssertFalse(layout.isRegular)
        XCTAssertEqual(layout.horizontalMargin, 0)
        XCTAssertEqual(layout.posterWidth, 40)
        XCTAssertEqual(layout.reviewLineLimit, 2)
    }

    func test_regularWidth_centersReadableColumn() {
        let layout = DiaryLayout(width: 1024)

        XCTAssertTrue(layout.isRegular)
        XCTAssertEqual(layout.horizontalMargin, (1024 - DiaryLayout.readableWidth) / 2)
        XCTAssertEqual(layout.posterWidth, 56)
        XCTAssertEqual(layout.reviewLineLimit, 3)
    }

    func test_regularWidthNarrowerThanColumn_hasNoMargin() {
        let layout = DiaryLayout(width: 700)

        XCTAssertTrue(layout.isRegular)
        XCTAssertEqual(layout.horizontalMargin, 0)
    }
}
