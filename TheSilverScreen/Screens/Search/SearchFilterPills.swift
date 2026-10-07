//
//  SearchFilterPills.swift
//  TheSilverScreen
//
//  View-all niche chips and Genre menu. Hidden during typeahead preview.
//

import SwiftUI

/// Horizontal Movies / TV / People niches plus a Genre dropdown filter.
struct SearchFilterPills: View {
    let typeNiche: SearchTypeNiche
    let genreFilter: MergedGenre?
    let onSelectNiche: (SearchTypeNiche) -> Void
    let onSelectGenre: (MergedGenre?) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DesignSpacing.sm) {
                ForEach(SearchTypeNiche.pillCases, id: \.self) { niche in
                    SearchFilterChip(
                        title: niche.title,
                        isSelected: typeNiche == niche
                    ) {
                        onSelectNiche(niche)
                    }
                    .accessibilityLabel(niche.title)
                    .accessibilityAddTraits(typeNiche == niche ? [.isSelected, .isButton] : .isButton)
                    .accessibilityHint(
                        typeNiche == niche
                            ? "Selected. Double tap to show all types."
                            : "Shows only \(niche.title.lowercased()) results."
                    )
                }

                genreMenu
            }
            .padding(.horizontal, DesignSpacing.lg)
            .padding(.vertical, DesignSpacing.sm)
        }
        .background(DesignTheme.canvas)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Search filters")
    }

    private var genreMenu: some View {
        Menu {
            if genreFilter != nil {
                Button("Clear Genre", role: .destructive) {
                    onSelectGenre(nil)
                }
            }
            ForEach(MergedGenre.searchShelf, id: \.self) { genre in
                Button {
                    onSelectGenre(genre)
                } label: {
                    if genreFilter == genre {
                        Label(genre.title, systemImage: "checkmark")
                    } else {
                        Text(genre.title)
                    }
                }
            }
        } label: {
            HStack(spacing: DesignSpacing.xs) {
                Text(genreFilter?.title ?? "Genre")
                    .font(DesignTypography.chip)
                Image(systemName: "chevron.down")
                    .font(DesignTypography.chip.weight(.semibold))
            }
            .foregroundStyle(genreFilter == nil ? DesignTheme.textPrimary : DesignTheme.accentOnFill)
            .padding(.horizontal, DesignSpacing.md)
            .padding(.vertical, DesignSpacing.xs + 2)
            .background(genreFilter == nil ? DesignTheme.surface : DesignTheme.accent)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(DesignTheme.separator.opacity(genreFilter == nil ? 0.35 : 0), lineWidth: 0.5)
            )
            .frame(minHeight: 44)
            .contentShape(Capsule())
        }
        .accessibilityLabel(genreFilter.map { "Genre, \($0.title)" } ?? "Genre")
        .accessibilityHint("Filters movie and TV results by genre")
        .accessibilityValue(genreFilter?.title ?? "None")
    }
}

/// Tappable filter chip. Selected state uses the brand accent fill.
private struct SearchFilterChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(DesignTypography.chip)
                .foregroundStyle(isSelected ? DesignTheme.accentOnFill : DesignTheme.textPrimary)
                .padding(.horizontal, DesignSpacing.md)
                .padding(.vertical, DesignSpacing.xs + 2)
                .background(isSelected ? DesignTheme.accent : DesignTheme.surface)
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .strokeBorder(DesignTheme.separator.opacity(isSelected ? 0 : 0.35), lineWidth: 0.5)
                )
                .frame(minHeight: 44)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
