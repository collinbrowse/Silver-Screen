//
//  DiaryContext.swift
//  SilverScreen
//
//  What diary screens need, installed once in the environment at the root. Passing it
//  this way keeps the diary out of every route view's initializer.
//

import Foundation

/// Diary dependencies plus a change counter. Any screen that writes an entry calls
/// `noteChange()`, and any screen that shows entries reloads when `revision` moves, so
/// a watch logged on a movie appears in an open diary (and the reverse).
@Observable
@MainActor
final class DiaryContext {
    let diary: DiaryRepository
    /// Logging a watch also puts the title on Watched.
    let lists: ListsRepository
    let logger: any AppLogging
    private(set) var revision = 0

    init(diary: DiaryRepository, lists: ListsRepository, logger: any AppLogging) {
        self.diary = diary
        self.lists = lists
        self.logger = logger
    }

    func noteChange() {
        revision += 1
    }
}
