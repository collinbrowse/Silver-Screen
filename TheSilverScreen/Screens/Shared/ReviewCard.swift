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
    @State private var expanded = false
    @State private var topOffset: CGFloat = 0

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
                Text(review.content)
                    .font(DesignTypography.body)
                    .foregroundStyle(DesignTheme.textSecondary)
                    .lineLimit(expanded ? nil : 6)
                    .fixedSize(horizontal: false, vertical: true)
                if review.content.count > 280 {
                    Button(expanded ? "Show Less" : "Show More") {
                        toggleExpanded()
                    }
                    .font(DesignTypography.chip.weight(.semibold))
                    .foregroundStyle(DesignTheme.accent)
                }
            }
        }
        .background {
            GeometryReader { geo in
                Color.clear
                    .onChange(of: geo.frame(in: .named("detailScroll")).minY, initial: true) { _, minY in
                        topOffset = minY
                    }
            }
        }
        .animation(.smooth(duration: 0.35), value: expanded)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(review.author), \(review.username), \(DisplayDate.day(review.updatedAt)). \(review.content)"
        )
    }

    /// Grow and shrink the card in one motion. If the open card starts above the screen,
    /// keep that card on screen so the collapse does not snap the scroll offset.
    private func toggleExpanded() {
        withAnimation(.smooth(duration: 0.35)) {
            if expanded, topOffset < 0 {
                scrollTo(review.id)
            }
            expanded.toggle()
        }
    }
}

/// One page of reviews, five at a time, with earlier and later pages.
struct ReviewPageList: View {
    let items: [MovieReview]
    let hasMore: Bool
    let totalCount: Int
    let isLoadingPage: Bool
    let pageError: AppError?
    let loadMore: () async -> Void
    var scrollTo: (String) -> Void = { _ in }

    @State private var page = 0
    @State private var awaitingPage = false

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSpacing.md) {
            Text("Reviews")
                .font(DesignTypography.section)
                .foregroundStyle(DesignTheme.textPrimary)
                .accessibilityAddTraits(.isHeader)

            VStack(alignment: .leading, spacing: DesignSpacing.md) {
                ForEach(ReviewWindow.page(items, index: page)) { review in
                    ReviewCard(review: review, scrollTo: scrollTo)
                        .id(review.id)
                }

                if isLoadingPage {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, DesignSpacing.sm)
                }

                if let pageError {
                    Text("\(pageError.title): \(pageError.message)")
                        .font(DesignTypography.metadata)
                        .foregroundStyle(DesignTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if showsPager {
                    pager
                }
            }
        }
        .padding(.horizontal, DesignSpacing.lg)
        .onChange(of: items.count) { _, count in
            advanceIfReady(itemCount: count)
        }
        .onChange(of: isLoadingPage) { _, loading in
            if awaitingPage, !loading {
                advanceIfReady(itemCount: items.count)
                awaitingPage = false
            }
        }
    }

    private var pageCount: Int {
        ReviewWindow.pageCount(totalCount: max(totalCount, items.count))
    }

    /// The row is only useful when another page exists in one direction.
    private var showsPager: Bool {
        canMoveBack || canMoveForward
    }

    private var canMoveBack: Bool {
        ReviewWindow.canMoveBack(index: page)
    }

    private var canMoveForward: Bool {
        ReviewWindow.canMoveForward(index: page, itemCount: items.count, hasMore: hasMore)
    }

    private var pager: some View {
        ZStack {
            Text("Page \(page + 1) / \(pageCount)")
                .font(DesignTypography.chip)
                .foregroundStyle(DesignTheme.textSecondary)
                .accessibilityLabel("Page \(page + 1) of \(pageCount)")

            HStack(spacing: 0) {
                if canMoveBack {
                    Button("Previous page") {
                        withAnimation(.smooth(duration: 0.3)) {
                            page -= 1
                        }
                    }
                }

                Spacer(minLength: 0)

                if canMoveForward {
                    Button("Next page") {
                        Task { await goForward() }
                    }
                    .disabled(isLoadingPage)
                }
            }
        }
        .font(DesignTypography.chip.weight(.semibold))
        .foregroundStyle(DesignTheme.accent)
        .padding(.top, DesignSpacing.sm)
    }

    private func goForward() async {
        let start = (page + 1) * ReviewWindow.size
        if start < items.count {
            withAnimation(.smooth(duration: 0.3)) {
                page += 1
            }
            return
        }
        guard hasMore, !isLoadingPage else { return }
        awaitingPage = true
        await loadMore()
    }

    private func advanceIfReady(itemCount: Int) {
        guard awaitingPage else { return }
        let start = (page + 1) * ReviewWindow.size
        guard start < itemCount else { return }
        withAnimation(.smooth(duration: 0.3)) {
            page += 1
        }
        awaitingPage = false
    }
}
