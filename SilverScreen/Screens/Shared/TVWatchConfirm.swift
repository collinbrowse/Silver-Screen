//
//  TVWatchConfirm.swift
//  SilverScreen
//
//  Pre-save confirm when marking or clearing a whole season or series watched.
//

import Foundation

enum TVWatchConfirm {
    static let seriesTitle = String(localized: "Mark as Watched?")
    static let seasonTitle = String(localized: "Mark Season as Watched?")
    static let clearSeriesTitle = String(localized: "Remove Watches?")
    static let clearSeasonTitle = String(localized: "Remove Season Watches?")
    static let confirmButtonTitle = String(localized: "Mark Watched")
    static let clearButtonTitle = String(localized: "Remove")

    /// Body copy for the confirm alert when `count` episodes would be newly completed.
    static func message(episodeCount count: Int) -> String {
        if count == 1 {
            return String(localized: "This marks 1 episode as watched.")
        }
        return String(localized: "This marks \(count) episodes as watched.")
    }

    /// Body copy when removing the watches of completed episodes.
    static func clearMessage(episodeCount count: Int) -> String {
        if count == 1 {
            return String(localized: "This removes 1 watched episode and its ratings and reviews.")
        }
        return String(localized: "This removes \(count) watched episodes and their ratings and reviews.")
    }
}
