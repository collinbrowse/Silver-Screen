//
//  MediaMetadataPills.swift
//  TheSilverScreen
//
//  Genre pills on detail screens, plus trailer play pills.
//

import SwiftUI

/// Wrapping genre pills on a detail screen.
struct GenreChipRow: View {
    let names: [String]

    var body: some View {
        FlowLayout(spacing: DesignSpacing.sm) {
            ForEach(Array(names.enumerated()), id: \.offset) { _, name in
                TagChip(title: name)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Genres: \(names.joined(separator: ", "))")
    }
}

/// Play control in the genre-pill shape. The triangle becomes a spinner while that trailer is opening.
struct TrailerChip: View {
    let title: String
    var isLoading = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: DesignSpacing.xs) {
                if isLoading {
                    ProgressView()
                        .controlSize(.mini)
                        .tint(DesignTheme.accent)
                        .frame(width: 14, height: 14)
                        .accessibilityHidden(true)
                } else {
                    Image(systemName: "play.fill")
                        .font(.caption2)
                        .accessibilityHidden(true)
                }
                Text(title)
                    .multilineTextAlignment(.leading)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .font(DesignTypography.chip)
            .foregroundStyle(DesignTheme.textPrimary)
            .padding(.horizontal, DesignSpacing.sm)
            .padding(.vertical, DesignSpacing.xs)
            .background(DesignTheme.surface)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(DesignTheme.separator.opacity(0.35), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
        .accessibilityLabel(isLoading ? "Loading \(title)" : "Play \(title)")
    }
}

/// Genre pills, then one play pill for each official trailer.
struct MediaMetadataPills: View {
    var genres: [MovieGenre] = []
    var trailers: [MediaTrailer] = []
    /// YouTube id of the pill that should show a spinner. Nil means every pill shows play.
    var loadingTrailerID: String? = nil
    var playTrailer: (MediaTrailer) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSpacing.sm) {
            if !genres.isEmpty {
                GenreChipRow(names: genres.map(\.name))
            }
            if !trailers.isEmpty {
                FlowLayout(spacing: DesignSpacing.sm) {
                    ForEach(trailers) { trailer in
                        TrailerChip(title: trailer.title, isLoading: loadingTrailerID == trailer.id) {
                            playTrailer(trailer)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}
