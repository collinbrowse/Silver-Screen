//
//  TVWatchConfirm.swift
//  TheSilverScreen
//
//  Pre-save confirm when marking a whole season or series watched.
//

import Foundation

enum TVWatchConfirm {
    static let seriesTitle = "Mark as Watched?"
    static let seasonTitle = "Mark Season as Watched?"
    static let confirmButtonTitle = "Mark Watched"

    /// Body copy for the confirm alert when `count` episodes would be newly completed.
    static func message(episodeCount count: Int) -> String {
        if count == 1 {
            return "This marks 1 episode as watched."
        }
        return "This marks \(count) episodes as watched."
    }
}
