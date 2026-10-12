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
    static let clearSeriesTitle = "Clear Watch Progress?"
    static let clearSeasonTitle = "Clear Season Progress?"
    static let confirmButtonTitle = "Mark Watched"
    static let clearButtonTitle = "Clear Progress"

    /// Body copy for the confirm alert when `count` episodes would be newly completed.
    static func message(episodeCount count: Int) -> String {
        if count == 1 {
            return "This marks 1 episode as watched."
        }
        return "This marks \(count) episodes as watched."
    }

    /// Body copy when clearing completed episodes.
    static func clearMessage(episodeCount count: Int) -> String {
        if count == 1 {
            return "This clears 1 watched episode."
        }
        return "This clears \(count) watched episodes."
    }
}
