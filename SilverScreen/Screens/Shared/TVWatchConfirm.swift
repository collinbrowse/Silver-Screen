//
//  TVWatchConfirm.swift
//  SilverScreen
//
//  Pre-save confirm when marking or clearing a whole season or series watched.
//

import Foundation

enum TVWatchConfirm {
    static let seriesTitle = "Mark as Watched?"
    static let seasonTitle = "Mark Season as Watched?"
    static let clearSeriesTitle = "Remove Watches?"
    static let clearSeasonTitle = "Remove Season Watches?"
    static let confirmButtonTitle = "Mark Watched"
    static let clearButtonTitle = "Remove"

    /// Body copy for the confirm alert when `count` episodes would be newly completed.
    static func message(episodeCount count: Int) -> String {
        if count == 1 {
            return "This marks 1 episode as watched."
        }
        return "This marks \(count) episodes as watched."
    }

    /// Body copy when removing the watches of completed episodes.
    static func clearMessage(episodeCount count: Int) -> String {
        if count == 1 {
            return "This removes 1 watched episode and its ratings and reviews."
        }
        return "This removes \(count) watched episodes and their ratings and reviews."
    }
}
