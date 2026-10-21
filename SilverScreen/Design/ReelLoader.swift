//
//  ReelLoader.swift
//  SilverScreen
//
//  The app icon's film strip as a looping loading indicator.
//

import SwiftUI

/// A looping loading indicator that starts and ends each loop as the app icon's film strip,
/// winding along its cylinder off the right and back in from the left. Each loader starts its
/// first loop at the icon pose when it appears. Holds the icon pose when Reduce Motion is on.
struct ReelLoader: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// When this loader appeared, so its first loop starts at the icon pose.
    @State private var start = Date()

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { timeline in
            ReelLoaderFrame(
                phase: reduceMotion ? 0 : ReelLoaderMotion.phase(after: timeline.date.timeIntervalSince(start))
            )
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityElement()
        .accessibilityLabel("Loading")
    }
}

#Preview {
    ReelLoader()
        .frame(width: 200)
}
