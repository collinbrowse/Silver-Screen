//
//  ReelLoaderMotion.swift
//  SilverScreen
//
//  The loading animation that keeps winding the app icon's film around the cylinder it is
//  wrapped on. Each loop rests as the icon. Then the icon's cylinder tips level while the
//  film starts flowing along its spiral, so it winds straight off the right edge; it winds
//  back in from the left, tips back to the icon's angle, and lands as the icon. The film
//  keeps its length and the cylinder its size the whole way.
//

import Foundation

/// Where the film is at one moment of a loop.
struct ReelWinding: Equatable, Sendable {
    /// Radians the film has flowed along its spiral. It jumps from `exitTurn` to
    /// `-entryTurn` partway through, while the film is entirely out of frame.
    var turn: Double
    /// How far the cylinder has tipped from the icon's angle toward level, from 0 to 1.
    var level: Double
    /// How far the icon has turned into the 3D film, from 0 (the icon artwork in its own pose)
    /// to 1 (the 3D film). It rises as the loop leaves the icon and falls as it lands, so
    /// each end is the real artwork.
    var morph: Double
}

/// How the reel loader winds the app icon's film off and back on, as a loop of `period`
/// seconds that starts and ends as the icon.
enum ReelLoaderMotion {
    /// Seconds for one loop, including the pause in the icon pose.
    static let period = 3.8

    /// Share of each loop spent resting as the app icon: half a second.
    static let restShare = 0.5 / period

    /// How far the film flows, in radians, to be entirely past the frame's right edge.
    static let exitTurn = 10.3
    /// How far back along its spiral the film starts its way in, entirely past the left edge.
    static let entryTurn = 10.3

    /// Share of the motion at each end spent tipping between the icon's angle and level.
    static let leveling = 0.24
    /// Share of the motion at each end spent turning the artwork into the 3D film, or back.
    static let handoff = 0.22

    /// Where in the loop a moment `elapsed` seconds after the loop began falls, from 0 up to
    /// (not including) 1.
    static func phase(after elapsed: TimeInterval) -> Double {
        let within = elapsed.truncatingRemainder(dividingBy: period)
        return (within < 0 ? within + period : within) / period
    }

    /// True while the loop rests as the app icon.
    static func isAtRest(at phase: Double) -> Bool {
        phase <= restShare || phase >= 1
    }

    /// Where the film is at `phase`, or nil while the loop rests as the icon.
    static func winding(at phase: Double) -> ReelWinding? {
        let progress = (phase - restShare) / (1 - restShare)
        guard progress > 0, progress < 1 else { return nil }
        let total = exitTurn + entryTurn
        let travelled = total * ReelEase.inOut(progress)
        return ReelWinding(
            turn: travelled < exitTurn ? travelled : travelled - total,
            level: ReelEase.smooth(progress / leveling) * ReelEase.smooth((1 - progress) / leveling),
            morph: ReelEase.smooth(progress / handoff) * ReelEase.smooth((1 - progress) / handoff)
        )
    }
}

/// Easing curves over 0…1.
enum ReelEase {
    static func smooth(_ t: Double) -> Double {
        let clamped = min(max(t, 0), 1)
        return clamped * clamped * (3 - 2 * clamped)
    }

    static func inOut(_ t: Double) -> Double {
        t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2
    }
}
