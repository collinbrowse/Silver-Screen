//
//  TVDetailComponents.swift
//  TheSilverScreen
//
//  Carousels shared by series, season, and episode screens.
//

import SwiftUI

struct TVCreditCarousel: View {
    let title: String
    let people: [TVCredit]
    let imageLoader: ImageLoader
    let onSelect: (TVCredit) -> Void

    private let cardWidth: CGFloat = 140

    var body: some View {
        DetailCarousel(title: title) {
            ForEach(people) { person in
                Button {
                    onSelect(person)
                } label: {
                    VStack(alignment: .leading, spacing: DesignSpacing.sm) {
                        RemoteImageView(
                            path: person.profilePath,
                            kind: .profile,
                            width: cardWidth,
                            aspectRatio: 2 / 3,
                            imageLoader: imageLoader,
                            placeholderSystemImage: "person.fill"
                        )
                        .carouselCard(width: cardWidth, aspectRatio: 2 / 3)

                        VStack(alignment: .leading, spacing: DesignSpacing.xs) {
                            Text(person.name)
                                .font(DesignTypography.metadata.weight(.semibold))
                                .foregroundStyle(DesignTheme.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                            if !person.role.isEmpty {
                                Text(person.role)
                                    .font(DesignTypography.chip)
                                    .foregroundStyle(DesignTheme.textSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .frame(width: cardWidth, alignment: .leading)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(label(for: person))
                .accessibilityAddTraits(.isButton)
            }
        }
    }

    private func label(for person: TVCredit) -> String {
        person.role.isEmpty ? person.name : "\(person.name), \(person.role)"
    }
}


