//
//  LibraryStore.swift
//  SilverScreen
//
//  Unified disk boundary for lists, annotations, and TV progress. Repositories
//  keep product rules; this store owns transactions against library.sqlite.
//

import Foundation

enum LibraryStoreMutation: Sendable, Equatable {
    /// Replace all list / media / membership rows. Does not touch annotations or TV watch.
    case replaceLists(LibrarySnapshot)
    /// Replace all annotation rows. Does not touch lists or TV watch.
    case replaceAnnotations([MediaAnnotation])
    /// Replace all TV watch rows. Does not touch lists or annotations.
    case replaceTVWatch([TVSeriesWatchState])
}

protocol LibraryStore: Sendable {
    func bootstrap() async throws
    func fetchSnapshot() async throws -> LibrarySnapshot
    func fetchAnnotations() async throws -> [MediaAnnotation]
    func fetchTVWatchStates() async throws -> [TVSeriesWatchState]
    func apply(_ mutation: LibraryStoreMutation) async throws
}
