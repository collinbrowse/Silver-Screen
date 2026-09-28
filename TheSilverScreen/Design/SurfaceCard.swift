//
//  SurfaceCard.swift
//  TheSilverScreen
//

import SwiftUI

struct SurfaceCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(DesignSpacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DesignTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: DesignRadius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DesignRadius.card, style: .continuous)
                    .strokeBorder(DesignTheme.separator.opacity(0.35), lineWidth: 0.5)
            )
    }
}
