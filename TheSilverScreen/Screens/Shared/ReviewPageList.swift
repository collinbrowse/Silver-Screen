//
//  ReviewPageList.swift
//  TheSilverScreen
//
//  One page of reviews, five at a time, with earlier and later pages.
//

import SwiftUI

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
