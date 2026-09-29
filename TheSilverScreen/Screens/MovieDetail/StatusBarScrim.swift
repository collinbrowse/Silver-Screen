//
//  StatusBarScrim.swift
//  TheSilverScreen
//
//  Soft shade under the time and status icons. Darkest at the screen edge, gone before the artwork.
//

import SwiftUI

struct StatusBarScrim: View {
    let height: CGFloat
    let reduceTransparency: Bool

    var body: some View {
        LinearGradient(
            stops: [
                .init(color: Color.black.opacity(reduceTransparency ? 0.42 : 0.28), location: 0),
                .init(color: Color.black.opacity(reduceTransparency ? 0.16 : 0.08), location: 0.38),
                .init(color: Color.black.opacity(0), location: 1)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(height: height)
        .frame(maxWidth: .infinity)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
