//
//  AwardTitlesView.swift
//  SilverScreen
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
                annotations: annotations,
                tvWatch: tvWatch
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
        .onAppear {
            Task { await viewModel.reloadDisplayedScores() }
        }
        .onChange(of: router?.path.count ?? 0) { _, _ in
            Task { await viewModel.reloadDisplayedScores() }
        }
    }

    /// One row per title on a phone. Wider screens put two or three titles in each
    /// list row; see `CatalogGridMetrics`.
    private func list(_ rows: [AwardTitleRow], activity: LoadActivity) -> some View {
        CatalogColumnsReader { columns in
            List {
                Section {
                    ForEach(CatalogGrid.rows(rows, columns: columns, id: \.id)) { gridRow in
                        CatalogColumnsRow(row: gridRow, columns: columns, id: \.id) { row in
                            rowCell(row)
                        }
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 8))
                        .listRowSeparatorBetweenCells(
                            isFirst: gridRow.isFirst,
                            isLast: gridRow.isLast && activity != .loadingMore
                        )
                        .onAppear {
                            if gridRow.isLast {
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

    private func rowCell(_ row: AwardTitleRow) -> some View {
        CatalogRowLayout {
            Button {
                router?.push(row.route)
            } label: {
                CatalogRowView(
                    title: row.title,
                    nextUp: row.nextUp,
                    genre: row.awardYear,
                    metadata: row.genreLine,
                    userScore: row.userScore,
                    kindLabel: row.kindLabel,
                    imagePath: row.imagePath,
                    imageKind: row.artwork == .still ? .backdrop : .poster,
                    placeholderSystemImage: row.artwork == .still ? "tv" : "film",
                    imageLoader: imageLoader
                )
            }
            .buttonStyle(.plain)
        } control: {
            if let draft = row.listDraft {
                WatchedToggleButton(
                    draft: draft,
                    lists: lists,
                    index: listsIndex,
                    tvWatch: tvWatch,
                    shows: shows,
                    onFailure: { viewModel.noteListSaveFailed() }
                )
            }
        }
    }
}

