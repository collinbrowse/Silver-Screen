//
//  CatalogRowView.swift
//  TheSilverScreen
//
//  One row layout for movie, TV, and people catalog lists.
//

import SwiftUI

struct CatalogRowView: View {
    let title: String
    let subtitle: String
    let metadata: String
    /// Personal score shown under the date. Not a control.
    var userScore: String? = nil
    let imagePath: String?
    let imageKind: ImageLoader.ImageKind
    let placeholderSystemImage: String
    let imageLoader: ImageLoader

    private let imageWidth: CGFloat = 120

    var body: some View {
        HStack(alignment: .top, spacing: DesignSpacing.md) {
            RemoteImageView(
                path: imagePath,
                kind: imageKind,
                width: imageWidth,
                aspectRatio: imageKind == .profile || imageKind == .poster ? 2 / 3 : 16 / 9,
                imageLoader: imageLoader,
                placeholderSystemImage: placeholderSystemImage
            )
            VStack(alignment: .leading, spacing: DesignSpacing.sm) {
                Text(title)
                    .font(DesignTypography.section)
                    .foregroundStyle(DesignTheme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(DesignTypography.metadata)
                        .foregroundStyle(DesignTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !metadata.isEmpty {
                    Text(metadata)
                        .font(DesignTypography.chip)
                        .foregroundStyle(DesignTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let userScore {
                    Text(userScore)
                        .font(DesignTypography.metadata)
                        .foregroundStyle(DesignTheme.accent)
                        .accessibilityLabel("Your rating, \(userScore)")
                }
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        [title, subtitle, metadata, userScore ?? ""]
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }
}

/// Inline failure while a list that already has content stays on screen.
struct LoadActivityBanner: View {
    let activity: LoadActivity

    var body: some View {
        if case .failed(let error) = activity {
            Text("\(error.title): \(error.message)")
                .font(DesignTypography.chip)
                .foregroundStyle(.white)
                .padding(DesignSpacing.sm)
                .frame(maxWidth: .infinity)
                .background(Color.red)
                .accessibilityLabel("\(error.title). \(error.message)")
        }
    }
}
