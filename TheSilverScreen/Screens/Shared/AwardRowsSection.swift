//
//  AwardRowsSection.swift
//  TheSilverScreen
//
//  Awards card shared by person screens and movie, series, season, and episode screens.
//

import SwiftUI

/// How many award rows stay visible before the user expands the list.
enum AwardRowsDisplay {
    static let collapsedLimit = 5

    /// Rows to render for the current expand state. Short lists always show in full.
    static func visibleRows<Row>(from rows: [Row], isExpanded: Bool) -> [Row] {
        guard rows.count > collapsedLimit, !isExpanded else { return rows }
        return Array(rows.prefix(collapsedLimit))
    }

    /// Only offer Show more / Show less when the list is longer than the collapsed limit.
    static func showsToggle(total: Int) -> Bool {
        total > collapsedLimit
    }

    static func toggleTitle(isExpanded: Bool) -> String {
        isExpanded ? "Show less" : "Show more"
    }
}

/// Trophy, category, and a second line. A row opens its title when `route` is set.
struct AwardRowsSection: View {
    let rows: [AwardRow]
    var open: (Route) -> Void = { _ in }

    @State private var isExpanded = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .body) private var trophyHeight: CGFloat = 36

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSpacing.sm) {
            Text("Awards")
                .font(DesignTypography.section)
                .foregroundStyle(DesignTheme.textPrimary)
                .accessibilityAddTraits(.isHeader)

            SurfaceCard {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(visibleRows.enumerated()), id: \.element.id) { index, row in
                        if index > 0 {
                            Divider()
                                .padding(.vertical, DesignSpacing.md)
                        }
                        awardRow(row)
                    }
                }
            }

            if AwardRowsDisplay.showsToggle(total: rows.count) {
                HStack {
                    Spacer(minLength: 0)
                    Button {
                        isExpanded.toggle()
                    } label: {
                        Text(AwardRowsDisplay.toggleTitle(isExpanded: isExpanded))
                            .font(DesignTypography.chip.weight(.semibold))
                            .foregroundStyle(DesignTheme.accent)
                            .padding(.horizontal, DesignSpacing.sm)
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(AwardRowsDisplay.toggleTitle(isExpanded: isExpanded))
                    .accessibilityAddTraits(.isButton)
                }
            }
        }
    }

    private var visibleRows: [AwardRow] {
        AwardRowsDisplay.visibleRows(from: rows, isExpanded: isExpanded)
    }

    @ViewBuilder
    private func awardRow(_ row: AwardRow) -> some View {
        let contents = rowContents(row)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())

        if let route = row.route {
            Button {
                open(route)
            } label: {
                contents
            }
            .buttonStyle(.plain)
            .accessibilityLabel(row.accessibilityName)
            .accessibilityHint("Opens this title")
        } else {
            contents
                .accessibilityElement(children: .combine)
                .accessibilityLabel(row.accessibilityName)
        }
    }

    @ViewBuilder
    private func rowContents(_ row: AwardRow) -> some View {
        let trophy = AwardTrophy(family: row.family)
            .frame(
                width: trophyHeight * CGFloat(row.family.trophyAspect),
                height: trophyHeight
            )
        let text = VStack(alignment: .leading, spacing: DesignSpacing.xs) {
            Text(row.categoryLabel)
                .font(DesignTypography.body.weight(.semibold))
                .foregroundStyle(DesignTheme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Text(row.detailLine)
                .font(DesignTypography.metadata)
                .foregroundStyle(DesignTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }

        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: DesignSpacing.sm) {
                trophy
                text
            }
        } else {
            HStack(alignment: .center, spacing: DesignSpacing.md) {
                trophy
                text
                    .frame(maxWidth: .infinity, alignment: .leading)
                if row.route != nil {
                    Image(systemName: "chevron.right")
                        .font(DesignTypography.chip.weight(.semibold))
                        .foregroundStyle(DesignTheme.textMuted)
                        .accessibilityHidden(true)
                }
            }
        }
    }
}

/// Picture of this prize’s trophy. Hidden from VoiceOver; the label names the prize.
struct AwardTrophy: View {
    let family: AwardFamily

    var body: some View {
        Image(family.trophyImage)
            .resizable()
            .scaledToFit()
            .accessibilityHidden(true)
    }
}
