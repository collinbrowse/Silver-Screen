//
//  AnnotationsRepositoryTests.swift
//  TheSilverScreenTests
//

import XCTest
@testable import TheSilverScreen

final class AnnotationsRepositoryTests: XCTestCase {
    private let updatedAt = Date(timeIntervalSince1970: 1_700_000_000)

    func test_saveScoreAndNote_roundTripsEachKind() async throws {
        let repository = AnnotationsRepository(store: InMemoryAnnotationsStore(), logger: SilentLogger())
        let keys: [AnnotationKey] = [
            .movie(500),
            .series(500),
            .season(seriesID: 1396, seasonNumber: 0),
            .episode(seriesID: 1396, seasonNumber: 1, episodeNumber: 3),
        ]

        for key in keys {
            _ = try await repository.save(score: 7.5, note: "Worth rewatching", for: key, at: updatedAt)
        }

        let movie = try await repository.annotation(for: .movie(500))
        let series = try await repository.annotation(for: .series(500))
        let season = try await repository.annotation(for: .season(seriesID: 1396, seasonNumber: 0))
        let episode = try await repository.annotation(for: .episode(seriesID: 1396, seasonNumber: 1, episodeNumber: 3))

        XCTAssertEqual(movie?.score, 7.5)
        XCTAssertEqual(movie?.note, "Worth rewatching")
        XCTAssertEqual(series?.score, 7.5)
        XCTAssertEqual(series?.key.kind, .tvSeries)
        XCTAssertNotEqual(movie?.key, series?.key)
        XCTAssertEqual(season?.key.seasonNumber, 0)
        XCTAssertEqual(episode?.key.episodeNumber, 3)
    }

    func test_save_scoreAndNote_together_roundTrips() async throws {
        let repository = AnnotationsRepository(store: InMemoryAnnotationsStore(), logger: SilentLogger())

        let saved = try await repository.save(
            score: 8.5,
            note: "Together",
            for: .movie(12),
            at: updatedAt
        )

        XCTAssertEqual(saved.score, 8.5)
        XCTAssertEqual(saved.note, "Together")
        XCTAssertEqual(saved.watchedAt, updatedAt)
        let loaded = try await repository.annotation(for: .movie(12))
        XCTAssertEqual(loaded, saved)
    }

    func test_save_blankNote_clearsExistingNote() async throws {
        let repository = AnnotationsRepository(store: InMemoryAnnotationsStore(), logger: SilentLogger())
        _ = try await repository.save(score: 7, note: "Keep for now", for: .movie(12), at: updatedAt)

        let saved = try await repository.save(score: 7, note: "  \n", for: .movie(12), at: updatedAt)

        XCTAssertEqual(saved.score, 7)
        XCTAssertNil(saved.note)
    }

    func test_save_rejectsInvalidScore() async {
        let repository = AnnotationsRepository(store: InMemoryAnnotationsStore(), logger: SilentLogger())

        do {
            _ = try await repository.save(score: 0, note: "Nope", for: .movie(12), at: updatedAt)
            XCTFail("Expected persistence error")
        } catch let error as AppError {
            XCTAssertEqual(error, .persistence)
        } catch {
            XCTFail("Unexpected error \(error)")
        }
        let loaded = try? await repository.annotation(for: .movie(12))
        XCTAssertNil(loaded)
    }

    func test_save_again_keepsTheWatchedDay() async throws {
        let repository = AnnotationsRepository(store: InMemoryAnnotationsStore(), logger: SilentLogger())
        let watched = Date(timeIntervalSince1970: 1_700_000_000)
        let later = Date(timeIntervalSince1970: 1_800_000_000)
        _ = try await repository.save(score: 7.5, note: "First", for: .movie(12), at: watched)

        let saved = try await repository.save(score: 9, note: "Second", for: .movie(12), at: later)

        XCTAssertEqual(saved.score, 9)
        XCTAssertEqual(saved.note, "Second")
        XCTAssertEqual(saved.watchedAt, watched)
    }

    func test_restore_putsBackPreviousAnnotation() async throws {
        let repository = AnnotationsRepository(store: InMemoryAnnotationsStore(), logger: SilentLogger())
        let previous = try await repository.save(
            score: 7.5,
            note: "Keep",
            for: .movie(12),
            at: updatedAt
        )
        _ = try await repository.save(score: 9, note: "Temp", for: .movie(12), at: updatedAt)

        try await repository.restore(previous, for: .movie(12))

        let loaded = try await repository.annotation(for: .movie(12))
        XCTAssertEqual(loaded, previous)
    }

    func test_restore_nil_removesAnnotation() async throws {
        let repository = AnnotationsRepository(store: InMemoryAnnotationsStore(), logger: SilentLogger())
        _ = try await repository.save(score: 8, note: "Temp", for: .movie(12), at: updatedAt)

        try await repository.restore(nil, for: .movie(12))

        let loaded = try await repository.annotation(for: .movie(12))
        XCTAssertNil(loaded)
    }

    func test_saveScore_leavesExistingLegacyNote() async throws {
        let store = InMemoryAnnotationsStore(records: [
            MediaAnnotation(key: .movie(1), score: nil, note: "A note", watchedAt: updatedAt),
        ])
        let repository = AnnotationsRepository(store: store, logger: SilentLogger())

        let saved = try await repository.saveScore(8, for: .movie(1), at: updatedAt)

        XCTAssertEqual(saved.score, 8)
        XCTAssertEqual(saved.note, "A note")
        XCTAssertEqual(saved.watchedAt, updatedAt)
    }

    func test_deleteNote_leavesScore() async throws {
        let repository = AnnotationsRepository(store: InMemoryAnnotationsStore(), logger: SilentLogger())
        _ = try await repository.save(score: 9.5, note: "A note", for: .movie(1), at: updatedAt)

        let saved = try await repository.deleteNote(for: .movie(1))

        XCTAssertEqual(saved?.score, 9.5)
        XCTAssertNil(saved?.note)
        XCTAssertEqual(saved?.watchedAt, updatedAt)
    }

    func test_deleteNote_onLegacyNoteOnly_removesTheRecord() async throws {
        let store = InMemoryAnnotationsStore(records: [
            MediaAnnotation(key: .series(2), score: nil, note: "Hello", watchedAt: updatedAt),
        ])
        let repository = AnnotationsRepository(store: store, logger: SilentLogger())

        let saved = try await repository.deleteNote(for: .series(2))

        XCTAssertNil(saved)
        let loaded = try await repository.annotation(for: .series(2))
        XCTAssertNil(loaded)
    }

    func test_clear_removesScoreAndNote() async throws {
        let repository = AnnotationsRepository(store: InMemoryAnnotationsStore(), logger: SilentLogger())
        _ = try await repository.save(score: 8, note: "Gone", for: .movie(1), at: updatedAt)

        try await repository.clear(for: .movie(1))

        let loaded = try await repository.annotation(for: .movie(1))
        XCTAssertNil(loaded)
    }

    func test_clear_whenMissing_isNoOp() async throws {
        let repository = AnnotationsRepository(store: InMemoryAnnotationsStore(), logger: SilentLogger())

        try await repository.clear(for: .movie(1))

        let loaded = try await repository.annotation(for: .movie(1))
        XCTAssertNil(loaded)
    }

    func test_saveScore_rejectsValueOutsideTheMenu() async {
        let repository = AnnotationsRepository(store: InMemoryAnnotationsStore(), logger: SilentLogger())

        do {
            _ = try await repository.saveScore(0, for: .movie(1), at: updatedAt)
            XCTFail("Expected persistence error")
        } catch let error as AppError {
            XCTAssertEqual(error, .persistence)
        } catch {
            XCTFail("Unexpected error \(error)")
        }
        let loaded = try? await repository.annotation(for: .movie(1))
        XCTAssertNil(loaded)
    }

    func test_save_whenStoreFails_throwsPersistenceAndKeepsPrevious() async throws {
        let store = InMemoryAnnotationsStore()
        let repository = AnnotationsRepository(store: store, logger: SilentLogger())
        _ = try? await repository.saveScore(7.5, for: .movie(1), at: updatedAt)
        await store.setSaveError(CocoaError(.fileWriteUnknown))

        do {
            _ = try await repository.saveScore(9, for: .movie(1), at: updatedAt)
            XCTFail("Expected persistence error")
        } catch let error as AppError {
            XCTAssertEqual(error, .persistence)
        } catch {
            XCTFail("Unexpected error \(error)")
        }

        let kept = try await repository.annotation(for: .movie(1))
        XCTAssertEqual(kept?.score, 7.5)
    }

    func test_saveScore_again_keepsTheWatchedDay() async throws {
        let repository = AnnotationsRepository(store: InMemoryAnnotationsStore(), logger: SilentLogger())
        let watched = Date(timeIntervalSince1970: 1_700_000_000)
        let later = Date(timeIntervalSince1970: 1_800_000_000)
        _ = try await repository.saveScore(7.5, for: .movie(1), at: watched)

        let saved = try await repository.saveScore(9, for: .movie(1), at: later)

        XCTAssertEqual(saved.score, 9)
        XCTAssertEqual(saved.watchedAt, watched)
    }

    func test_save_noteChange_doesNotMoveTheRatingDate() async throws {
        let repository = AnnotationsRepository(store: InMemoryAnnotationsStore(), logger: SilentLogger())
        let rated = Date(timeIntervalSince1970: 1_700_000_000)
        let noted = Date(timeIntervalSince1970: 1_800_000_000)
        _ = try await repository.save(score: 7.5, note: "First", for: .movie(1), at: rated)

        let saved = try await repository.save(score: 7.5, note: "Later", for: .movie(1), at: noted)

        XCTAssertEqual(saved.watchedAt, rated)
        XCTAssertEqual(saved.note, "Later")
    }

    func test_legacyNoteOnly_stillLoads() async throws {
        let store = InMemoryAnnotationsStore(records: [
            MediaAnnotation(key: .movie(9), score: nil, note: "Old note", watchedAt: updatedAt),
        ])
        let repository = AnnotationsRepository(store: store, logger: SilentLogger())

        let loaded = try await repository.annotation(for: .movie(9))

        XCTAssertNil(loaded?.score)
        XCTAssertEqual(loaded?.note, "Old note")
    }
}

final class FileAnnotationsStoreTests: XCTestCase {
    private var tempDirectory: URL!

    override func setUpWithError() throws {
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TheSilverScreenAnnotationsTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDirectory)
    }

    func test_load_oneBadRecord_keepsValidRecordsAndRewritesClean() async throws {
        let good = MediaAnnotation(
            key: .movie(1),
            score: 8,
            note: "Keep",
            watchedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let goodData = try encoder.encode(good)
        let goodObject = try JSONSerialization.jsonObject(with: goodData)
        let envelope: [String: Any] = [
            "version": 1,
            "records": [goodObject, ["garbage": true]],
        ]
        let data = try JSONSerialization.data(withJSONObject: envelope)
        try data.write(to: fileURL(), options: .atomic)
        let store = FileAnnotationsStore(fileURL: fileURL())

        let loaded = try await store.load()

        XCTAssertEqual(loaded.map(\.key), [.movie(1)])
        XCTAssertEqual(loaded.first?.note, "Keep")
        let rewritten = try Data(contentsOf: fileURL())
        let object = try JSONSerialization.jsonObject(with: rewritten) as? [String: Any]
        let records = object?["records"] as? [Any]
        XCTAssertEqual(records?.count, 1)
    }

    func test_load_invalidScore_dropsTheScoreAndKeepsTheNote() async throws {
        let record = MediaAnnotation(
            key: .series(4),
            score: 11,
            note: "Still here",
            watchedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let encoded = try encoder.encode(record)
        var object = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]
        object["score"] = 11
        let envelope: [String: Any] = ["version": 1, "records": [object]]
        try JSONSerialization.data(withJSONObject: envelope).write(to: fileURL(), options: .atomic)
        let store = FileAnnotationsStore(fileURL: fileURL())

        let loaded = try await store.load()

        XCTAssertEqual(loaded.count, 1)
        XCTAssertNil(loaded.first?.score)
        XCTAssertEqual(loaded.first?.note, "Still here")
    }

    func test_load_unreadableFile_quarantinesAndReturnsEmpty() async throws {
        try Data("not json at all".utf8).write(to: fileURL(), options: .atomic)
        let store = FileAnnotationsStore(fileURL: fileURL())

        let loaded = try await store.load()

        XCTAssertTrue(loaded.isEmpty)
        let quarantine = fileURL().appendingPathExtension("corrupt")
        XCTAssertTrue(FileManager.default.fileExists(atPath: quarantine.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL().path))
    }

    func test_load_legacyUpdatedAt_becomesTheRatingAndNoteDates() async throws {
        let envelope: [String: Any] = [
            "version": 1,
            "records": [[
                "key": [
                    "kind": "movie",
                    "subjectID": 1,
                    "seasonNumber": 0,
                    "episodeNumber": 0,
                ],
                "score": 7.5,
                "note": "Old",
                "updatedAt": "2023-11-14T22:13:20Z",
            ]],
        ]
        try JSONSerialization.data(withJSONObject: envelope).write(to: fileURL(), options: .atomic)
        let store = FileAnnotationsStore(fileURL: fileURL())

        let loaded = try await store.load()

        let expected = Date(timeIntervalSince1970: 1_700_000_000)
        XCTAssertEqual(loaded.first?.watchedAt, expected)
    }

    private func fileURL() -> URL {
        tempDirectory.appendingPathComponent("annotations.json")
    }
}
