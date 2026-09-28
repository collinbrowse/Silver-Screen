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
            _ = try await repository.saveScore(7.5, for: key, at: updatedAt)
            _ = try await repository.saveNote("Worth rewatching", for: key, at: updatedAt)
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

    func test_saveScore_leavesExistingNote() async throws {
        let repository = AnnotationsRepository(store: InMemoryAnnotationsStore(), logger: SilentLogger())
        _ = try await repository.saveNote("A note", for: .movie(1), at: updatedAt)

        let saved = try await repository.saveScore(8, for: .movie(1), at: updatedAt)

        XCTAssertEqual(saved.score, 8)
        XCTAssertEqual(saved.note, "A note")
        XCTAssertEqual(saved.watchedAt, updatedAt)
    }

    func test_deleteNote_leavesScore() async throws {
        let repository = AnnotationsRepository(store: InMemoryAnnotationsStore(), logger: SilentLogger())
        _ = try await repository.saveScore(9.5, for: .movie(1), at: updatedAt)
        _ = try await repository.saveNote("A note", for: .movie(1), at: updatedAt)

        let saved = try await repository.deleteNote(for: .movie(1))

        XCTAssertEqual(saved?.score, 9.5)
        XCTAssertNil(saved?.note)
        XCTAssertEqual(saved?.watchedAt, updatedAt)
    }

    func test_saveWhitespaceNote_storesItAsAbsent() async throws {
        let repository = AnnotationsRepository(store: InMemoryAnnotationsStore(), logger: SilentLogger())
        _ = try await repository.saveScore(6, for: .movie(1), at: updatedAt)

        let saved = try await repository.saveNote("   \n", for: .movie(1), at: updatedAt)

        XCTAssertEqual(saved?.score, 6)
        XCTAssertNil(saved?.note)
    }

    func test_saveWhitespaceNote_withoutScore_removesTheRecord() async throws {
        let repository = AnnotationsRepository(store: InMemoryAnnotationsStore(), logger: SilentLogger())
        _ = try await repository.saveNote("Hello", for: .series(2), at: updatedAt)

        let saved = try await repository.saveNote("  ", for: .series(2), at: updatedAt)

        XCTAssertNil(saved)
        let loaded = try await repository.annotation(for: .series(2))
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

    func test_saveNote_doesNotMoveTheRatingDate() async throws {
        let repository = AnnotationsRepository(store: InMemoryAnnotationsStore(), logger: SilentLogger())
        let rated = Date(timeIntervalSince1970: 1_700_000_000)
        let noted = Date(timeIntervalSince1970: 1_800_000_000)
        _ = try await repository.saveScore(7.5, for: .movie(1), at: rated)

        let saved = try await repository.saveNote("Later", for: .movie(1), at: noted)

        XCTAssertEqual(saved?.watchedAt, rated)
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
