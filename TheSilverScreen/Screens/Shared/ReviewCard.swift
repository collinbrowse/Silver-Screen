//
//  ReviewCard.swift
//  TheSilverScreen
//
//  Shared review cell for movie and TV review lists.
//

import SwiftUI

/// How many reviews a detail screen shows before the next page control.
enum ReviewWindow {
    static let size = 5

    static func page<T>(_ items: [T], index: Int) -> [T] {
        let start = max(0, index) * size
        guard start < items.count else { return [] }
        let end = min(start + size, items.count)
        return Array(items[start..<end])
    }

    static func canMoveBack(index: Int) -> Bool {
        index > 0
    }

    static func canMoveForward(index: Int, itemCount: Int, hasMore: Bool) -> Bool {
        (index + 1) * size < itemCount || hasMore
    }

    /// Pages of `size` reviews. At least one page when any reviews exist.
    static func pageCount(totalCount: Int) -> Int {
        guard totalCount > 0 else { return 1 }
        return (totalCount + size - 1) / size
    }
}

struct ReviewCard: View {
    let review: MovieReview
    var scrollTo: (String) -> Void = { _ in }

    var body: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: DesignSpacing.sm) {
                Text(review.author)
                    .font(DesignTypography.metadata.weight(.semibold))
                    .foregroundStyle(DesignTheme.textPrimary)
                Text("@\(review.username)")
                    .font(DesignTypography.chip)
                    .foregroundStyle(DesignTheme.textSecondary)
                Text(DisplayDate.day(review.updatedAt))
                    .font(DesignTypography.chip)
                    .foregroundStyle(DesignTheme.textMuted)
                ExpandableTextToggle(
                    text: review.content,
                    scrollTo: scrollTo,
                    scrollID: review.id
                )
            }
        }
        .id(review.id)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(review.author), \(review.username), \(DisplayDate.day(review.updatedAt)). \(review.content)"
        )
    }
}
