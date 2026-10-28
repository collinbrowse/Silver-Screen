//
//  DiaryRepositoryTests.swift
//  SilverScreenTests
//

import XCTest
@testable import SilverScreen

final class DiaryRepositoryTests: XCTestCase {
    func test_save_newEntry_storesNormalizedEntry() async throws {
        let store = InMemoryDiaryStore()
        let repository = DiaryRepository(store: store, logger: SilentLogger())
        let entry = DiaryFixtures.entry(review: "  Loved it  ", tags: ["a", " A "])

        let saved = try await repository.save(entry)

        XCTAssertEqual(saved.review, "Loved it")
        XCTAssertEqual(saved.tags, ["a"])
        let stored = await store.entries
        XCTAssertEqual(stored, [saved])
    }

    func test_save_existingID_replacesEntry() async throws {
        let entry = DiaryFixtures.entry(score: 6)
        let store = InMemoryDiaryStore(entries: [entry])
        let repository = DiaryRepository(store: store, logger: SilentLogger())
        var edited = entry
        edited.score = 9

        try await repository.save(edited)

        let stored = await store.entries
        XCTAssertEqual(stored.map(\.score), [9])
    }

    func test_save_unchangedEntry_skipsWrite() async throws {
        let entry = DiaryFixtures.entry()
        let store = InMemoryDiaryStore(entries: [entry])
        let repository = DiaryRepository(store: store, logger: SilentLogger())

        try await repository.save(entry)

        let saves = await store.saveCount
        XCTAssertEqual(saves, 0)
    }

    func test_save_personSubject_throwsPersistence() async {
        let repository = DiaryRepository(store: InMemoryDiaryStore(), logger: SilentLogger())
        let entry = DiaryFixtures.entry(subject: DiarySubject(kind: .person, tmdbID: 1))

        do {
            try await repository.save(entry)
            XCTFail("Expected a persistence error")
        } catch {
            XCTAssertEqual(error as? AppError, .persistence)
        }
    }

    func test_episodeWatches_whenStoreFails_throwsPersistence() async {
        let store = InMemoryDiaryStore()
        await store.setEpisodeLoadError(CocoaError(.fileReadCorruptFile))
        let repository = DiaryRepository(store: store, logger: SilentLogger())

        do {
            _ = try await repository.episodeWatches()
            XCTFail("Expected a persistence error")
        } catch {
            XCTAssertEqual(error as? AppError, .persistence)
        }
    }

    func test_episodeWatches_seriesID_filtersToThatShow() async throws {
        let watch = { (series: Int) in
            EpisodeWatch(
                seriesID: series,
                seriesTitle: "Show",
                posterPath: nil,
                episode: TVEpisodeRef(seasonNumber: 1, episodeNumber: 1),
                completedAt: Date(timeIntervalSince1970: 1_792_000_000)
            )
        }
        let repository = DiaryRepository(
            store: InMemoryDiaryStore(episodeWatches: [watch(1), watch(2)]),
            logger: SilentLogger()
        )

        let watches = try await repository.episodeWatches(seriesID: 2)

        XCTAssertEqual(watches.map(\.seriesID), [2])
    }

    func test_save_whenStoreFails_throwsPersistenceAndKeepsCache() async throws {
        let existing = DiaryFixtures.entry()
        let store = InMemoryDiaryStore(entries: [existing])
        let repository = DiaryRepository(store: store, logger: SilentLogger())
        _ = try await repository.entries()
        await store.setSaveError(CocoaError(.fileWriteUnknown))

        do {
            try await repository.save(DiaryFixtures.entry(subject: .movie(9)))
            XCTFail("Expected a persistence error")
        } catch {
            XCTAssertEqual(error as? AppError, .persistence)
        }

        let entries = try await repository.entries()
        XCTAssertEqual(entries, [existing])
    }

    func test_entries_whenStoreFails_throwsPersistence() async {
        let store = InMemoryDiaryStore()
        await store.setLoadError(CocoaError(.fileReadCorruptFile))
        let repository = DiaryRepository(store: store, logger: SilentLogger())

        do {
            _ = try await repository.entries()
            XCTFail("Expected a persistence error")
        } catch {
            XCTAssertEqual(error as? AppError, .persistence)
        }
    }

    func test_entries_sortsNewestWatchThenNewestLogFirst() async throws {
        let oldest = DiaryFixtures.entry(watchedOn: DiaryDay(year: 2026, month: 9, day: 30))
        let sameDayEarlier = DiaryFixtures.entry(
            watchedOn: DiaryDay(year: 2026, month: 10, day: 2),
            loggedAt: Date(timeIntervalSince1970: 100)
        )
        let sameDayLater = DiaryFixtures.entry(
            watchedOn: DiaryDay(year: 2026, month: 10, day: 2),
            loggedAt: Date(timeIntervalSince1970: 200)
        )
        let repository = DiaryRepository(
            store: InMemoryDiaryStore(entries: [oldest, sameDayEarlier, sameDayLater]),
            logger: SilentLogger()
        )

        let entries = try await repository.entries()

        XCTAssertEqual(entries.map(\.id), [sameDayLater.id, sameDayEarlier.id, oldest.id])
    }

    func test_entriesForSubject_returnsOnlyThatTitle() async throws {
        let dune = DiaryFixtures.entry(subject: .movie(438631))
        let show = DiaryFixtures.entry(subject: .series(438631))
        let repository = DiaryRepository(
            store: InMemoryDiaryStore(entries: [dune, show]),
            logger: SilentLogger()
        )

        let entries = try await repository.entries(for: .movie(438631))

        XCTAssertEqual(entries.map(\.id), [dune.id])
    }

    func test_delete_removesEntry() async throws {
        let kept = DiaryFixtures.entry()
        let removed = DiaryFixtures.entry()
        let store = InMemoryDiaryStore(entries: [kept, removed])
        let repository = DiaryRepository(store: store, logger: SilentLogger())

        try await repository.delete(id: removed.id)

        let stored = await store.entries
        XCTAssertEqual(stored.map(\.id), [kept.id])
    }

    func test_delete_unknownID_skipsWrite() async throws {
        let store = InMemoryDiaryStore(entries: [DiaryFixtures.entry()])
        let repository = DiaryRepository(store: store, logger: SilentLogger())

        try await repository.delete(id: UUID())

        let saves = await store.saveCount
        XCTAssertEqual(saves, 0)
    }
}

/// Diary entries for tests, dated 16 Oct 2026 unless told otherwise.
enum DiaryFixtures {
    static func entry(
        subject: DiarySubject = .movie(550),
        title: String = "Fight Club",
        watchedOn: DiaryDay = DiaryDay(year: 2026, month: 10, day: 16),
        score: Double? = nil,
        review: String? = nil,
        isRewatch: Bool = false,
        tags: [String] = [],
        loggedAt: Date = Date(timeIntervalSince1970: 1_792_000_000)
    ) -> DiaryEntry {
        DiaryEntry(
            id: UUID(),
            subject: subject,
            title: title,
            releaseYear: 1999,
            posterPath: nil,
            watchedOn: watchedOn,
            score: score,
            review: review,
            isRewatch: isRewatch,
            tags: tags,
            loggedAt: loggedAt
        )
    }

    /// Gregorian calendar fixed to UTC, so day math does not depend on the test machine.
    static var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }
}
