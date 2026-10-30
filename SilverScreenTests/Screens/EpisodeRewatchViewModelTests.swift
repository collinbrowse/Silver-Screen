//
//  EpisodeRewatchViewModelTests.swift
//  SilverScreenTests
//

import XCTest
@testable import SilverScreen

@MainActor
final class EpisodeRewatchViewModelTests: XCTestCase {
    /// Fri 16 Oct 2026, 18:00 UTC.
    private let now = Date(timeIntervalSince1970: 1_792_173_600)

    func test_begin_opensNewUnratedEpisodeWatchDatedToday() throws {
        let viewModel = makeViewModel(context: makeContext(store: InMemoryDiaryStore()))

        viewModel.begin()

        let session = try XCTUnwrap(viewModel.editor)
        XCTAssertTrue(session.isNew)
        XCTAssertFalse(session.canDelete)
        XCTAssertNil(session.draft.score)
        XCTAssertEqual(session.draft.watchedOn, now)
        XCTAssertEqual(session.base.subject, .episode(seriesID: 42, season: 2, episode: 3))
        XCTAssertEqual(session.title, "S2 · E3")
        XCTAssertEqual(session.base.title, "Severance")
    }

    func test_save_storesEpisodeEntryAndLeavesListsAlone() async throws {
        let store = InMemoryDiaryStore()
        let lists = ListsRepository.empty()
        let context = makeContext(store: store, lists: lists)
        let viewModel = makeViewModel(context: context)
        viewModel.begin()
        var draft = try XCTUnwrap(viewModel.editor?.draft)
        draft.score = 8.5
        draft.review = "Caught so much more the second time."

        let result = await viewModel.save(draft)

        XCTAssertEqual(result, .succeeded)
        XCTAssertNil(viewModel.editor)
        XCTAssertEqual(context.revision, 1)
        let stored = await store.entries
        XCTAssertEqual(stored.count, 1)
        XCTAssertEqual(stored.first?.subject, .episode(seriesID: 42, season: 2, episode: 3))
        XCTAssertEqual(stored.first?.score, 8.5)
        XCTAssertEqual(stored.first?.posterPath, "/sev.jpg")
        let snapshot = try await lists.snapshot()
        XCTAssertTrue(snapshot.entries.isEmpty)
    }

    func test_save_whenDiaryFails_keepsSheetOpen() async throws {
        let store = InMemoryDiaryStore()
        await store.setSaveError(CocoaError(.fileWriteUnknown))
        let context = makeContext(store: store)
        let viewModel = makeViewModel(context: context)
        viewModel.begin()

        let result = await viewModel.save(try XCTUnwrap(viewModel.editor?.draft))

        XCTAssertEqual(result, .failed)
        XCTAssertNotNil(viewModel.editor)
        XCTAssertEqual(context.revision, 0)
    }

    private func makeContext(store: InMemoryDiaryStore, lists: ListsRepository = .empty()) -> DiaryContext {
        DiaryContext(
            diary: DiaryRepository(store: store, logger: SilentLogger()),
            lists: lists,
            logger: SilentLogger()
        )
    }

    private func makeViewModel(context: DiaryContext) -> EpisodeRewatchViewModel {
        let now = now
        return EpisodeRewatchViewModel(
            title: LogWatchTitle(
                episode: TVEpisodeRef(seasonNumber: 2, episodeNumber: 3),
                seriesID: 42,
                seriesName: "Severance",
                posterPath: "/sev.jpg"
            ),
            context: context,
            now: { now }
        )
    }
}
