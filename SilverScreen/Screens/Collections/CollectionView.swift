//
//  CollectionView.swift
//  SilverScreen
//

import SwiftUI

struct CollectionView: View {
    @Bindable var viewModel: CollectionViewModel
    let imageLoader: ImageLoader
    let lists: ListsRepository
    let listsIndex: ListsIndex
    var router: NavigationRouter?

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            switch viewModel.state {
                case .idle, .loading:
                    ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .empty:
                    EmptyStateView(
                        title: "No Collection",
                        message: "This collection has no details.",
                        systemImage: "square.stack"
                    )
                case .loaded(let content, _):
                    loaded(content)
                case .failed(let error):
                    ErrorStateView(error: error) {
                    await viewModel.retry()
                    }
            }
        }
        .background(DesignTheme.canvas)
        .task {
            if case .idle = viewModel.state {
                await viewModel.load()
            }
        }
        .onAppear {
            Task { await viewModel.reloadDisplayedScores() }
        }
    }

    private var navigationTitle: String {
        if case .loaded(let content, _) = viewModel.state {
            return content.name
        }
        return ""
    }

    /// The header keeps a readable line length on wide screens, and the movies sit
    /// two or three to a row there; see `CatalogGridMetrics`.
    private func loaded(_ content: CollectionContent) -> some View {
        let showsHeader = hasPoster(content) || !content.overview.isEmpty || !content.name.isEmpty
        return ContentWidthReader { width in
            let columns = CatalogGridMetrics.columnCount(
                forWidth: width,
                isAccessibilitySize: dynamicTypeSize.isAccessibilitySize
            )
            parts(content, showsHeader: showsHeader, columns: columns)
        }
    }

    private func parts(_ content: CollectionContent, showsHeader: Bool, columns: Int) -> some View {
        List {
            if showsHeader {
                Section {
                    VStack(alignment: .leading, spacing: DesignSpacing.md) {
                        HStack(alignment: .top, spacing: DesignSpacing.md) {
                            if hasPoster(content) {
                                MoviePosterView(
                                    posterPath: content.posterPath,
                                    imageLoader: imageLoader,
                                    width: 96
                                )
                            }
                            Text(content.name)
                                .font(DesignTypography.title)
                                .foregroundStyle(DesignTheme.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                                .inlineTitleAnchor()
                        }
                        if !content.overview.isEmpty {
                            Text(content.overview)
                                .font(DesignTypography.body)
                                .foregroundStyle(DesignTheme.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: ReadableWidth.maximum, alignment: .leading)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(headerLabel(content))
                    .coordinateSpace(.named("detailScroll"))
                    .listRowSeparatorBetweenCells(isFirst: true, isLast: content.parts.isEmpty)
                }
                .listSectionSeparatorBetweenCells(isFirstSection: true, isLastSection: content.parts.isEmpty)
            }

            if !content.parts.isEmpty {
                Section {
                    ForEach(CatalogGrid.rows(content.parts, columns: columns, id: \.id)) { gridRow in
                        CatalogColumnsRow(row: gridRow, columns: columns, id: \.id) { row in
                            partCell(row)
                        }
                        .listRowSeparatorBetweenCells(
                            isFirst: !showsHeader && gridRow.isFirst,
                            isLast: gridRow.isLast
                        )
                    }
                }
                .listSectionSeparatorBetweenCells(isFirstSection: !showsHeader, isLastSection: true)
            }
        }
        .listStyle(.plain)
        .scrollingInlineTitle(navigationTitle)
    }

    private func partCell(_ row: CatalogMovieRow) -> some View {
        CatalogRowLayout {
            Button {
                router?.push(.movieDetail(id: row.id))
            } label: {
                CatalogRowView(
                    title: row.title,
                    genre: row.genreNames.joined(separator: ", "),
                    metadata: row.formattedReleaseDate,
                    userScore: row.formattedUserScore,
                    kindLabel: "Movie",
                    imagePath: row.posterPath,
                    imageKind: .poster,
                    placeholderSystemImage: "film",
                    imageLoader: imageLoader
                )
            }
            .buttonStyle(.plain)
        } control: {
            WatchedToggleButton(
                draft: row.listItem(),
                lists: lists,
                index: listsIndex
            ) {
                viewModel.noteListSaveFailed()
            }
        }
    }

    private func hasPoster(_ content: CollectionContent) -> Bool {
        guard let path = content.posterPath?.trimmingCharacters(in: .whitespacesAndNewlines) else {
            return false
        }
        return !path.isEmpty
    }

    private func headerLabel(_ content: CollectionContent) -> String {
        if content.overview.isEmpty {
            return content.name
        }
        return "\(content.name). \(content.overview)"
    }
}
