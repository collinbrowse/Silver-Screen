//
//  AwardTitlesView.swift
//  TheSilverScreen
//

import SwiftUI

struct AwardTitlesView: View {
    @State private var viewModel: AwardTitlesViewModel
    let imageLoader: ImageLoader
    let lists: ListsRepository
    let listsIndex: ListsIndex
    let shows: TVRepository
    let tvWatch: TVWatchRepository
    var router: NavigationRouter?

    init(
        request: AwardTitleRequest,
        awards: AwardsRepository,
        movies: MovieRepository,
        shows: TVRepository,
        annotations: AnnotationsRepository,
        lists: ListsRepository,
        listsIndex: ListsIndex,
        tvWatch: TVWatchRepository,
        imageLoader: ImageLoader,
        router: NavigationRouter?
    ) {
        _viewModel = State(
            initialValue: AwardTitlesViewModel(
                request: request,
                awards: awards,
                movies: movies,
                shows: shows,
                annotations: annotations
            )
        )
        self.imageLoader = imageLoader
        self.lists = lists
        self.listsIndex = listsIndex
        self.shows = shows
        self.tvWatch = tvWatch
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
                        title: viewModel.emptyTitle,
                        message: viewModel.emptyMessage,
                        systemImage: "trophy"
                    )
                case .loaded(let rows, let activity):
                    list(rows, activity: activity)
                case .failed(let error):
                    ErrorStateView(error: error) {
                    await viewModel.load()
                    }
            }
        }
        .background(DesignTheme.canvas)
        .navigationTitle(viewModel.navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .top, spacing: 0) {
            Picker("Winners or nominees", selection: Binding(
                get: { viewModel.showingWinners },
                set: { winners in
                    Task { await viewModel.setShowingWinners(winners) }
                }
            )) {
                Text("Winners").tag(true)
                Text("Nominees").tag(false)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, DesignSpacing.lg)
            .padding(.vertical, DesignSpacing.sm)
            .background(DesignTheme.canvas)
            .accessibilityLabel("Winners or nominees")
        }
        .task {
            if case .idle = viewModel.state {
                await viewModel.load()
            }
        }
    }

    private func list(_ rows: [AwardTitleRow], activity: LoadActivity) -> some View {
        List {
            Section {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    HStack(alignment: .center, spacing: DesignSpacing.sm) {
                        Button {
                            router?.push(row.route)
                        } label: {
                            CatalogRowView(
                                title: row.title,
                                subtitle: row.awardYear,
                                metadata: row.genreLine,
                                userScore: row.userScore,
                                imagePath: row.imagePath,
                                imageKind: row.artwork == .still ? .backdrop : .poster,
                                placeholderSystemImage: row.artwork == .still ? "tv" : "film",
                                imageLoader: imageLoader
                            )
                        }
                        .buttonStyle(.plain)

                        if let draft = row.listDraft {
                            WatchedToggleButton(
                                draft: draft,
                                lists: lists,
                                index: listsIndex,
                                tvWatch: tvWatch,
                                shows: shows
                            )
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 8))
                    .listRowSeparatorBetweenCells(
                        isFirst: index == 0,
                        isLast: index == rows.count - 1 && activity != .loadingMore
                    )
                    .onAppear {
                        if index == rows.count - 1 {
                            Task { await viewModel.loadMore() }
                        }
                    }
                }
                if activity == .loadingMore {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .listRowSeparator(.hidden)
                }
            }
            .listSectionSeparatorBetweenCells(isFirstSection: true, isLastSection: true)
        }
        .listStyle(.plain)
        .overlay(alignment: .top) {
            LoadActivityBanner(activity: activity)
        }
    }
}

