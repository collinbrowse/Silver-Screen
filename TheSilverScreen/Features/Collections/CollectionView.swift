//
//  CollectionView.swift
//  TheSilverScreen
//

import SwiftUI

struct CollectionView: View {
    @Bindable var viewModel: CollectionViewModel
    let imageLoader: ImageLoader
    let lists: ListsRepository
    let listsIndex: ListsIndex
    var router: NavigationRouter?

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

    private func loaded(_ content: CollectionContent) -> some View {
        let showsHeader = hasPoster(content) || !content.overview.isEmpty || !content.name.isEmpty
        return List {
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
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(headerLabel(content))
                    .coordinateSpace(.named("detailScroll"))
                    .listRowSeparatorBetweenCells(isFirst: true, isLast: content.parts.isEmpty)
                }
                .listSectionSeparatorBetweenCells(isFirstSection: true, isLastSection: content.parts.isEmpty)
            }

            if !content.parts.isEmpty {
                Section {
                    ForEach(Array(content.parts.enumerated()), id: \.element.id) { index, row in
                        HStack(alignment: .center, spacing: DesignSpacing.sm) {
                            Button {
                                router?.push(.movieDetail(id: row.id))
                            } label: {
                                CatalogRowView(
                                    title: row.title,
                                    subtitle: row.genreNames.joined(separator: ", "),
                                    metadata: row.formattedReleaseDate,
                                    userScore: row.formattedUserScore,
                                    imagePath: row.posterPath,
                                    imageKind: .poster,
                                    placeholderSystemImage: "film",
                                    imageLoader: imageLoader
                                )
                            }
                            .buttonStyle(.plain)
                            ListMembershipButton(
                                draft: row.listItem(),
                                lists: lists,
                                index: listsIndex
                            ) {
                                viewModel.noteListSaveFailed()
                            }
                        }
                        .listRowSeparatorBetweenCells(
                            isFirst: !showsHeader && index == 0,
                            isLast: index == content.parts.count - 1
                        )
                    }
                }
                .listSectionSeparatorBetweenCells(isFirstSection: !showsHeader, isLastSection: true)
            }
        }
        .listStyle(.plain)
        .scrollingInlineTitle(navigationTitle)
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
