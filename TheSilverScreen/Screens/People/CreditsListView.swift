//
//  CreditsListView.swift
//  TheSilverScreen
//

import SwiftUI

struct CreditsListView: View {
    @State private var viewModel: CreditsListViewModel
    let imageLoader: ImageLoader
    var router: NavigationRouter?

    init(
        personID: Int,
        personName: String,
        department: CreditDepartment,
        people: PersonRepository,
        imageLoader: ImageLoader,
        router: NavigationRouter? = nil
    ) {
        _viewModel = State(
            initialValue: CreditsListViewModel(
                personID: personID,
                personName: personName,
                department: department,
                people: people
            )
        )
        self.imageLoader = imageLoader
        self.router = router
    }

    var body: some View {
        Group {
            switch viewModel.state {
                case .idle, .loading:
                    ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .empty:
                    EmptyStateView(
                    title: "No Credits",
                    message: "No credits were found for this section.",
                    systemImage: "film"
                    )
                case .loaded(let content, _):
                    List {
                    Section {
                        ForEach(Array(content.items.enumerated()), id: \.element.id) { index, item in
                            creditRow(item)
                                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                                .listRowSeparatorBetweenCells(
                                    isFirst: index == 0,
                                    isLast: index == content.items.count - 1
                                )
                        }
                    }
                    .listSectionSeparatorBetweenCells(isFirstSection: true, isLastSection: true)
                    }
                    .listStyle(.plain)
                case .failed(let error):
                    ErrorStateView(error: error) {
                    await viewModel.retry()
                    }
            }
        }
        .background(DesignTheme.canvas)
        .navigationTitle(viewModel.navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if case .idle = viewModel.state {
                await viewModel.load()
            }
        }
    }

    @ViewBuilder
    private func creditRow(_ item: CreditsListItem) -> some View {
        let row = CreditsListRow(item: item, imageLoader: imageLoader)
        if let router {
            Button {
                switch item.credit.mediaType {
                    case .movie:
                        router.push(.movieDetail(id: item.credit.mediaID))
                    case .tv:
                        router.push(.tvSeries(id: item.credit.mediaID))
                }
            } label: {
                row
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(.isButton)
        } else {
            row
        }
    }
}

private struct CreditsListRow: View {
    let item: CreditsListItem
    let imageLoader: ImageLoader

    private let posterWidth: CGFloat = 70
    private let posterAspect: CGFloat = 2 / 3

    var body: some View {
        HStack(alignment: .top, spacing: DesignSpacing.md) {
            RemoteImageView(
                path: item.credit.posterPath,
                kind: .poster,
                width: posterWidth,
                aspectRatio: posterAspect,
                imageLoader: imageLoader,
                placeholderSystemImage: item.credit.mediaType == .tv ? "tv" : "film"
            )
            .clipShape(RoundedRectangle(cornerRadius: DesignRadius.poster, style: .continuous))

            VStack(alignment: .leading, spacing: DesignSpacing.sm) {
                Text(item.credit.title)
                    .font(DesignTypography.metadata.weight(.semibold))
                    .foregroundStyle(DesignTheme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                if !item.genreNames.isEmpty {
                    Text(item.genreNames.joined(separator: ", "))
                        .font(DesignTypography.chip)
                        .foregroundStyle(DesignTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(item.formattedReleaseDate)
                    .font(DesignTypography.chip)
                    .foregroundStyle(DesignTheme.textMuted)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    private var accessibilitySummary: String {
        var parts = [item.credit.title]
        if !item.genreNames.isEmpty {
            parts.append(item.genreNames.joined(separator: ", "))
        }
        if item.formattedReleaseDate != "Not available" {
            parts.append(item.formattedReleaseDate)
        }
        switch item.credit.mediaType {
            case .movie: parts.append("Movie")
            case .tv: parts.append("TV series")
        }
        return parts.joined(separator: ", ")
    }
}
