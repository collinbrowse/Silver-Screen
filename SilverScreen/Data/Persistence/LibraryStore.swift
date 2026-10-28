//
//  LibraryStore.swift
//  SilverScreen
//
//  Unified disk boundary for lists, annotations, TV progress, and the diary. Repositories
//  keep product rules; this store owns transactions against library.sqlite.
//

import Foundation

enum LibraryStoreMutation: Sendable, Equatable {
    /// Make list / media / membership rows match the snapshot: insert, update changed rows,
    /// and tombstone missing ones. Does not touch annotations or TV watch.
    case replaceLists(LibrarySnapshot)
    /// Make annotation rows match the records, diffed the same way. Does not touch lists or TV watch.
    case replaceAnnotations([MediaAnnotation])
    /// Make TV watch and completed-episode rows match the states, diffed the same way.
    /// Does not touch lists or annotations.
    case replaceTVWatch([TVSeriesWatchState])
    /// Make diary rows match the entries, diffed the same way. Does not touch other domains.
    case replaceDiary([DiaryEntry])
}

protocol LibraryStore: Sendable {
    func bootstrap() async throws
    func fetchSnapshot() async throws -> LibrarySnapshot
    func fetchAnnotations() async throws -> [MediaAnnotation]
    func fetchTVWatchStates() async throws -> [TVSeriesWatchState]
    func fetchDiaryEntries() async throws -> [DiaryEntry]
    /// Every live completed episode that has a completion time and a stored series title.
    func fetchEpisodeWatches() async throws -> [EpisodeWatch]
    func apply(_ mutation: LibraryStoreMutation) async throws
}
