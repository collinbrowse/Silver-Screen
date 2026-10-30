//
//  TitleWatchViewModelTests.swift
//  SilverScreenTests
//

import XCTest
@testable import SilverScreen

@MainActor
final class TitleWatchViewModelTests: XCTestCase {
    private let older = DiaryDay(year: 2026, month: 2, day: 3)
    private let newer = DiaryDay(year: 2026, month: 10, day: 16)

    func test_load_unwatched_offersNothingOfItsOwn() async {
        let viewModel = makeViewModel(entries: [DiaryFixtures.entry(subject: .movie(1))])

        await viewModel.load()

        XCTAssertFalse(viewModel.isWatched)
        XCTAssertNil(viewModel.formattedUserScore)
        viewModel.beginRewatch()
        viewModel.openRating()
        XCTAssertNil(viewModel.editor)
    }

    func test_load_showsNewestRatedWatchAndSaysWhich() async {
        let viewModel = makeViewModel(entries: [
            DiaryFixtures.entry(watchedOn: older, score: 6),
            DiaryFixtures.entry(watchedOn: newer, score: 8.5),
        ])

        await viewModel.load()

        XCTAssertEqual(viewModel.formattedUserScore, "8.5")
        XCTAssertEqual(viewModel.scoreCaption, "from your Oct 16 watch")
        XCTAssertEqual(viewModel.scoreAccessibilityLabel, "Your rating 8.5, from your Oct 16 watch. Edit.")
    }

    func test_newestWatchUnrated_cardKeepsOlderRating() async {
        let rated = DiaryFixtures.entry(watchedOn: older, score: 6)
        let viewModel = makeViewModel(entries: [rated, DiaryFixtures.entry(watchedOn: newer)])
        await viewModel.load()

        viewModel.openRating()

        XCTAssertEqual(viewModel.formattedUserScore, "6.0")
        XCTAssertEqual(viewModel.editor?.base.id, rated.id)
    }

    func test_noRatedWatch_cardOpensNewestWatch() async {
        let newest = DiaryFixtures.entry(watchedOn: newer)
        let viewModel = makeViewModel(entries: [DiaryFixtures.entry(watchedOn: older), newest])
        await viewModel.load()

        viewModel.openRating()

        XCTAssertEqual(viewModel.editor?.base.id, newest.id)
    }

    func test_undatedRatedWatch_saysEarlierWatch() async {
        var undated = DiaryFixtures.entry(score: 7)
        undated.isDateKnown = false
        let viewModel = makeViewModel(entries: [undated])

        await viewModel.load()

        XCTAssertEqual(viewModel.scoreCaption, "from an earlier watch")
    }

    func test_beginRewatch_thenSave_addsANewWatch() async throws {
        let store = InMemoryDiaryStore(entries: [DiaryFixtures.entry(watchedOn: older)])
        let viewModel = makeViewModel(store: store)
        await viewModel.load()

        viewModel.beginRewatch()
        let session = try XCTUnwrap(viewModel.editor)
        XCTAssertTrue(session.isNew)
        let result = await viewModel.save(session.draft)

        XCTAssertEqual(result, .succeeded)
        XCTAssertNil(viewModel.editor)
        XCTAssertEqual(viewModel.watches.count, 2)
    }

    func test_save_whenStoreFails_keepsSheetOpen() async {
        let store = InMemoryDiaryStore(entries: [DiaryFixtures.entry(watchedOn: older)])
        let viewModel = makeViewModel(store: store)
        await viewModel.load()
        viewModel.openRating()
        await store.setSaveError(AppError.persistence)

        var draft = viewModel.editor?.draft
        draft?.score = 9
        let result = await viewModel.save(draft!)

        XCTAssertEqual(result, .failed)
        XCTAssertNotNil(viewModel.editor)
    }

    func test_deleteOpenWatch_removesItAndClosesSheet() async {
        let viewModel = makeViewModel(entries: [DiaryFixtures.entry(watchedOn: older)])
        await viewModel.load()
        viewModel.openRating()

        let result = await viewModel.deleteOpenWatch()

        XCTAssertEqual(result, .succeeded)
        XCTAssertFalse(viewModel.isWatched)
        XCTAssertNil(viewModel.editor)
    }

    func test_reviewWatch_isNewestWithAReview_andOpens() async {
        let reviewed = DiaryFixtures.entry(watchedOn: older, review: "Tense")
        let viewModel = makeViewModel(entries: [reviewed, DiaryFixtures.entry(watchedOn: newer)])
        await viewModel.load()

        viewModel.openReview()

        XCTAssertEqual(viewModel.reviewWatch?.id, reviewed.id)
        XCTAssertEqual(viewModel.formattedReviewDay, "Feb 3")
        XCTAssertEqual(viewModel.editor?.base.id, reviewed.id)
    }

    private func makeViewModel(entries: [DiaryEntry]) -> TitleWatchViewModel {
        makeViewModel(store: InMemoryDiaryStore(entries: entries))
    }

    private func makeViewModel(store: InMemoryDiaryStore) -> TitleWatchViewModel {
        let draft = ListItemDraft(
            id: 550,
            kind: .movie,
            title: "Fight Club",
            imagePath: nil,
            releaseDate: nil,
            genreNames: [],
            voteAverage: 8,
            popularity: 1
        )
        return TitleWatchViewModel(
            title: LogWatchTitle(
                subject: .movie(550),
                title: "Fight Club",
                releaseYear: 1999,
                posterPath: nil,
                listItem: draft
            ),
            context: DiaryContext(
                diary: DiaryRepository(store: store, logger: SilentLogger()),
                lists: .empty(),
                logger: SilentLogger()
            ),
            calendar: DiaryFixtures.utcCalendar,
            locale: Locale(identifier: "en_US")
        )
    }
}
