//
//  InMemoryLibraryStore.swift
//  SilverScreenTests
//
//  In-memory LibraryStore for tests that talk to the unified store protocol
//  instead of the per-domain ListsStore / AnnotationsStore / TVWatchStore fakes.
//

import Foundation
@testable import SilverScreen

actor InMemoryLibraryStore: LibraryStore {
    private var snapshot: LibrarySnapshot
    private var annotations: [MediaAnnotation]
    private var tvWatch: [TVSeriesWatchState]
    private var diary: [DiaryEntry] = []
    private var bootstrapped = false

    init(
        snapshot: LibrarySnapshot = .empty,
        annotations: [MediaAnnotation] = [],
        tvWatch: [TVSeriesWatchState] = []
    ) {
        self.snapshot = snapshot
        self.annotations = annotations
        self.tvWatch = tvWatch
    }

    func bootstrap() async throws {
        bootstrapped = true
    }

    func fetchSnapshot() async throws -> LibrarySnapshot {
        snapshot
    }

    func fetchAnnotations() async throws -> [MediaAnnotation] {
        annotations
    }

    func fetchTVWatchStates() async throws -> [TVSeriesWatchState] {
        tvWatch
    }

    func fetchDiaryEntries() async throws -> [DiaryEntry] {
        diary
    }

    func apply(_ mutation: LibraryStoreMutation) async throws {
        switch mutation {
            case .replaceLists(let snapshot):
                self.snapshot = snapshot
            case .replaceAnnotations(let records):
                annotations = records
            case .replaceTVWatch(let states):
                tvWatch = states
            case .replaceDiary(let entries):
                diary = entries
        }
    }
}
