//
//  AwardShelfCard.swift
//  TheSilverScreen
//
//  Search-home card. The ceremony lockup is the whole card. The Oscars mark is
//  clear, so the card fill switches between white and black. BAFTA and the Emmys
//  supply their own light and dark pictures.
//

import SwiftUI

struct AwardShelfCard: View {
    let shelf: AwardShelf
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Color.clear
            .frame(maxWidth: .infinity)
            .frame(height: 112)
            .overlay {
                if let family = shelf.family {
                    Image(family.shelfImage)
                        .resizable()
                        .renderingMode(.original)
                        .scaledToFit()
                        .padding(.horizontal, DesignSpacing.md)
                        .padding(.vertical, DesignSpacing.sm)
                        .accessibilityHidden(true)
                }
            }
            .background(fill)
            .clipShape(RoundedRectangle(cornerRadius: DesignRadius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DesignRadius.card, style: .continuous)
                    .strokeBorder(DesignTheme.separator.opacity(0.5), lineWidth: 1)
            )
            .accessibilityElement(children: .ignore)
    }

    /// Matches the picture’s own field, so fitting the logo does not leave a mismatched border.
    private var fill: Color {
        let dark = colorScheme == .dark
        switch shelf.family {
            case .emmy:
                return dark ? Color(red: 0.008, green: 0.016, blue: 0.13) : .white
            case .academy, .bafta, nil:
                return dark ? .black : .white
        }
    }
}
