//
//  InMemoryAnnotationsStore.swift
//  SilverScreenTests
//

import Foundation
@testable import SilverScreen

actor InMemoryAnnotationsStore: AnnotationsStore {
    private var records: [MediaAnnotation]
    var loadError: Error?
    var saveError: Error?
    /// Fails on the Nth `save` call (1-based). Nil disables the counter.
    private var failOnSaveNumber: Int?
    private var saveCount = 0

    init(records: [MediaAnnotation] = []) {
        self.records = records
    }

    /// Makes every later `load` throw `error`, as an unreadable store would.
    func setLoadError(_ error: Error?) {
        loadError = error
    }

    func load() async throws -> [MediaAnnotation] {
        if let loadError {
            throw loadError
        }
        return records
    }

    func save(_ records: [MediaAnnotation]) async throws {
        saveCount += 1
        if let failOnSaveNumber, saveCount == failOnSaveNumber {
            throw CocoaError(.fileWriteUnknown)
        }
        if let saveError {
            throw saveError
        }
        self.records = records
    }

    func setSaveError(_ error: Error?) {
        saveError = error
    }

    func setFailOnSaveNumber(_ number: Int?) {
        failOnSaveNumber = number
        saveCount = 0
    }
}
