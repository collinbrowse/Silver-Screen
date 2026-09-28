//
//  AnnotationsStore.swift
//  TheSilverScreen
//
//  Disk boundary for personal scores and notes. Tests substitute an in-memory store.
//

import Foundation

protocol AnnotationsStore: Sendable {
    func load() async throws -> [MediaAnnotation]
    func save(_ records: [MediaAnnotation]) async throws
}
