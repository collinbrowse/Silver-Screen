//
//  LetterboxdImportTests.swift
//  SilverScreenTests
//
//  The Letterboxd export reader (CSV quirks and how the files combine), TMDB match
//  picking, and the importer writing through real repositories over in-memory stores
//  and a sequenced fake HTTP client.
//

import XCTest
@testable import SilverScreen

final class LetterboxdExportTests: XCTestCase {
    func test_parseCSV_quotedCommasQuotesAndNewlines_keepFieldsWhole() {
        let rows = LetterboxdExport.parseCSV("\u{FEFF}Name,Review\r\n\"Crash, Again\",\"He said \"\"wow\"\"\nthen left\"\r\n")

        XCTAssertEqual(rows, [["Name", "Review"], ["Crash, Again", "He said \"wow\"\nthen left"]])
    }

    func test_plans_diaryWithReview_joinsReviewByURIAndKeepsDayAndRewatch() {
        let plans = LetterboxdExport.plans(from: [
            .diary: """
            Date,Name,Year,Letterboxd URI,Rating,Rewatch,Tags,Watched Date
            2024-01-05,Arrival,2016,https://boxd.it/a1,4.5,,,2024-01-04
            2024-03-01,Arrival,2016,https://boxd.it/a2,,Yes,,2024-02-28
            """,
            .reviews: """
            Date,Name,Year,Letterboxd URI,Rating,Rewatch,Review,Tags,Watched Date
            2024-01-05,Arrival,2016,https://boxd.it/a1,4.5,,"Quietly huge.",,2024-01-04
            """,
        ])

        XCTAssertEqual(plans.count, 1)
        XCTAssertEqual(plans[0].film, LetterboxdFilm(name: "Arrival", year: 2016))
        XCTAssertEqual(plans[0].watches, [
            LetterboxdWatch(watchedOn: DiaryDay(year: 2024, month: 1, day: 4), stars: 4.5, isRewatch: false, review: "Quietly huge."),
            LetterboxdWatch(watchedOn: DiaryDay(year: 2024, month: 2, day: 28), stars: nil, isRewatch: true, review: nil),
        ])
        XCTAssertFalse(plans[0].onWatchlist)
    }

    func test_plans_reviewWithoutDiaryRow_isKeptAsItsOwnWatch() {
        let plans = LetterboxdExport.plans(from: [
            .reviews: "Date,Name,Year,Letterboxd URI,Rating,Rewatch,Review,Tags,Watched Date\n2023-05-01,Heat,1995,u9,4.5,,Tense.,,\n",
        ])

        XCTAssertEqual(plans.map(\.watches), [[LetterboxdWatch(watchedOn: nil, stars: 4.5, isRewatch: false, review: "Tense.")]])
    }

    func test_plans_ratingWithoutDiary_becomesUndatedRatedWatch() {
        let plans = LetterboxdExport.plans(from: [
            .ratings: "Date,Name,Year,Letterboxd URI,Rating\n2023-05-01,Heat,1995,https://boxd.it/h,5\n",
            .watched: "Date,Name,Year,Letterboxd URI\n2023-05-01,Heat,1995,https://boxd.it/h\n",
        ])

        XCTAssertEqual(plans.map(\.watches), [[LetterboxdWatch(watchedOn: nil, stars: 5, isRewatch: false, review: nil)]])
    }

    func test_plans_ratingWithUnratedDiary_ratesNewestWatch() {
        let plans = LetterboxdExport.plans(from: [
            .diary: "Date,Name,Year,Letterboxd URI,Rating,Rewatch,Tags,Watched Date\n,Heat,1995,u1,,,,2020-01-01\n,Heat,1995,u2,,Yes,,2022-01-01\n",
            .ratings: "Date,Name,Year,Letterboxd URI,Rating\n2023-05-01,Heat,1995,https://boxd.it/h,4\n",
        ])

        XCTAssertEqual(plans[0].watches.map(\.stars), [nil, 4])
    }

    func test_plans_watchlistOnly_hasNoWatches() {
        let plans = LetterboxdExport.plans(from: [
            .watchlist: "Date,Name,Year,Letterboxd URI\n2023-05-01,Dune: Part Two,2024,https://boxd.it/d\n",
        ])

        XCTAssertEqual(plans.count, 1)
        XCTAssertTrue(plans[0].watches.isEmpty)
        XCTAssertTrue(plans[0].onWatchlist)
    }

    func test_plans_blankNameAndBadRating_areSkipped() {
        let plans = LetterboxdExport.plans(from: [
            .ratings: "Date,Name,Year,Letterboxd URI,Rating\n2023-05-01,,1995,u,4\n2023-05-01,Heat,1995,u,9\n",
        ])

        XCTAssertTrue(plans.isEmpty)
    }

    func test_file_matchesExportNamesIgnoringCase() {
        XCTAssertEqual(LetterboxdExport.file(named: "Diary.CSV"), .diary)
        XCTAssertNil(LetterboxdExport.file(named: "likes.csv"))
    }
}

final class LetterboxdMatchTests: XCTestCase {
    func test_bestMatch_prefersExactTitleInTheSameYear() {
        let results = [movie(1, "Heat Wave", "1995-02-01"), movie(2, "Heat", "1995-12-15"), movie(3, "Heat", "1986-01-01")]

        let match = LetterboxdImporter.bestMatch(for: LetterboxdFilm(name: "heat", year: 1995), in: results, yearTolerance: 0)

        XCTAssertEqual(match?.id, 2)
    }

    func test_bestMatch_yearOffByOne_onlyWithTolerance() {
        let results = [movie(5, "Amélie", "2001-04-25")]
        let film = LetterboxdFilm(name: "Amelie", year: 2002)

        XCTAssertNil(LetterboxdImporter.bestMatch(for: film, in: results, yearTolerance: 0))
        XCTAssertEqual(LetterboxdImporter.bestMatch(for: film, in: results, yearTolerance: 1)?.id, 5)
    }

    func test_bestMatch_noYear_takesTopResult() {
        let results = [movie(7, "Untitled", nil), movie(8, "Other", "2000-01-01")]

        XCTAssertEqual(LetterboxdImporter.bestMatch(for: LetterboxdFilm(name: "Something", year: nil), in: results, yearTolerance: 0)?.id, 7)
    }

    private func movie(_ id: Int, _ title: String, _ date: String?) -> Movie {
        let parsed = date.flatMap { DiaryDay(iso: $0)?.date(in: Calendar(identifier: .gregorian)) }
        return Movie(id: id, title: title, posterPath: nil, releaseDate: parsed, voteAverage: 7, genreIDs: [])
    }
}

@MainActor
final class LetterboxdImporterTests: XCTestCase {
    func test_matchThenApply_logsDatedWatchesWithRatingAndWatchlist() async throws {
        let harness = ImportHarness(searchPages: [
            ImportHarness.page([(329865, "Arrival", "2016-11-10")]),
            ImportHarness.page([(693134, "Dune: Part Two", "2024-02-27")]),
        ])
        let plans = [
            LetterboxdFilmPlan(
                film: LetterboxdFilm(name: "Arrival", year: 2016),
                watches: [LetterboxdWatch(watchedOn: DiaryDay(year: 2024, month: 1, day: 4), stars: 4.5, isRewatch: false, review: "Huge.")],
                onWatchlist: false
            ),
            LetterboxdFilmPlan(film: LetterboxdFilm(name: "Dune: Part Two", year: 2024), watches: [], onWatchlist: true),
        ]

        let matches = try await harness.importer.match(plans)
        let summary = try await harness.importer.apply(matches)

        XCTAssertEqual(summary, LetterboxdImportSummary(watchesAdded: 1, filmsLogged: 1, watchlistAdded: 1))
        let stored = await harness.diaryStore.entries
        XCTAssertEqual(stored.count, 1)
        XCTAssertEqual(stored.first?.subject, .movie(329865))
        XCTAssertEqual(stored.first?.score, 9)
        XCTAssertEqual(stored.first?.review, "Huge.")
        XCTAssertEqual(stored.first?.watchedOn, DiaryDay(year: 2024, month: 1, day: 4))
        let snapshot = try await harness.lists.snapshot()
        let watchlist = try XCTUnwrap(snapshot.list(.watchlist))
        XCTAssertTrue(snapshot.entries.contains { $0.listID == watchlist.id && $0.itemID == 693134 })
        let watched = try XCTUnwrap(snapshot.list(.watched))
        XCTAssertTrue(snapshot.entries.contains { $0.listID == watched.id && $0.itemID == 329865 })
    }

    func test_apply_twice_addsNothingTheSecondTime() async throws {
        let harness = ImportHarness(searchPages: [])
        let arrival = Movie(id: 329865, title: "Arrival", posterPath: nil, releaseDate: nil, voteAverage: 8, genreIDs: [])
        let matches = [
            LetterboxdMatch(
                plan: LetterboxdFilmPlan(
                    film: LetterboxdFilm(name: "Arrival", year: 2016),
                    watches: [
                        LetterboxdWatch(watchedOn: DiaryDay(year: 2024, month: 1, day: 4), stars: nil, isRewatch: false, review: nil),
                    ],
                    onWatchlist: false
                ),
                movie: arrival
            ),
        ]

        _ = try await harness.importer.apply(matches)
        let second = try await harness.importer.apply(matches)

        XCTAssertEqual(second, LetterboxdImportSummary(alreadyInLibrary: 1))
        let stored = await harness.diaryStore.entries
        XCTAssertEqual(stored.count, 1)
    }

    func test_apply_unmatchedFilm_isListedAndNothingWritten() async throws {
        let harness = ImportHarness(searchPages: [])
        let film = LetterboxdFilm(name: "Obscure Short", year: 1971)
        let matches = [LetterboxdMatch(plan: LetterboxdFilmPlan(film: film, watches: [], onWatchlist: true), movie: nil)]

        let summary = try await harness.importer.apply(matches)

        XCTAssertEqual(summary.unmatched, [film])
        XCTAssertEqual(summary.watchlistAdded, 0)
    }

    func test_match_offline_stopsWithOfflineError() async {
        let harness = ImportHarness(failure: URLError(.notConnectedToInternet))
        let plans = [LetterboxdFilmPlan(film: LetterboxdFilm(name: "Heat", year: 1995), watches: [], onWatchlist: true)]

        do {
            _ = try await harness.importer.match(plans)
            XCTFail("Expected offline")
        } catch {
            XCTAssertEqual(error as? AppError, .offline)
        }
    }

    func test_viewModel_emptyFiles_isNothingFound() async {
        let viewModel = LetterboxdImportViewModel(importer: ImportHarness(searchPages: []).importer)

        await viewModel.load(files: [.watched: "Date,Name,Year,Letterboxd URI\n"])

        XCTAssertEqual(viewModel.phase, .nothingFound)
    }

    func test_viewModel_loadThenConfirm_finishesAndNotifies() async {
        let harness = ImportHarness(searchPages: [ImportHarness.page([(949, "Heat", "1995-12-15")])])
        var notified = 0
        let viewModel = LetterboxdImportViewModel(importer: harness.importer) { notified += 1 }

        await viewModel.load(files: [.watched: "Date,Name,Year,Letterboxd URI\n2023-05-01,Heat,1995,u\n"])
        guard case .review(let review) = viewModel.phase else {
            return XCTFail("Expected review, got \(viewModel.phase)")
        }
        XCTAssertEqual(review.matchedFilms, 1)
        await viewModel.confirm()

        XCTAssertEqual(viewModel.phase, .finished(LetterboxdImportSummary(watchesAdded: 1, filmsLogged: 1)))
        XCTAssertEqual(notified, 1)
    }
}

/// Real importer and repositories over in-memory stores and a scripted TMDB.
@MainActor
private struct ImportHarness {
    let diaryStore = InMemoryDiaryStore()
    let lists: ListsRepository
    let importer: LetterboxdImporter

    init(searchPages: [Data]) {
        self.init(client: SequencingHTTPClient(stubs: searchPages.map { .success($0, status: 200) }))
    }

    init(failure: Error) {
        self.init(client: FakeHTTPClient(result: .failure(failure)))
    }

    private init(client: any HTTPClient) {
        let diary = DiaryRepository(store: diaryStore, logger: SilentLogger())
        lists = ListsRepository(store: InMemoryListsStore(), logger: SilentLogger())
        let annotations = AnnotationsRepository(store: InMemoryAnnotationsStore(), logger: SilentLogger())
        let watches = WatchRepository(diary: diary, lists: lists, annotations: annotations, logger: SilentLogger())
        importer = LetterboxdImporter(
            movies: .test(client: client),
            watches: watches,
            lists: lists,
            logger: SilentLogger(),
            sleeper: NoopSleeper(),
            spacing: 0
        )
    }

    /// A one-page `search/movie` response.
    static func page(_ movies: [(id: Int, title: String, date: String)]) -> Data {
        let results = movies.map { movie in
            """
            {"id":\(movie.id),"title":"\(movie.title)","poster_path":null,"release_date":"\(movie.date)","vote_average":7.5,"genre_ids":[]}
            """
        }
        return Data(#"{"page":1,"total_pages":1,"results":[\#(results.joined(separator: ","))]}"#.utf8)
    }
}
