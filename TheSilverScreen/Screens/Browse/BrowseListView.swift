//
//  BrowseListView.swift
//  TheSilverScreen
//
//  Movies, TV, and the mixed list. Media spans the width under the title.
//  Window and sort live in the Filters menu. The list control is its own button.
//

import SwiftUI

struct BrowseListView: View {
    @Bindable var viewModel: BrowseListViewModel
    let imageLoader: ImageLoader
    let lists: ListsRepository
    let listsIndex: ListsIndex
    var router: NavigationRouter?

    @State private var scrolledID: String?

    var body: some View {
        content
            .background(DesignTheme.canvas)
            .refreshable { await viewModel.refresh() }
            .safeAreaInset(edge: .top, spacing: 0) {
                mediaControl
                    .background(DesignTheme.canvas)
            }
            .navigationTitle("Browse")
            .toolbarTitleDisplayMode(.inlineLarge)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    filterMenu
                }
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
        .onChange(of: viewModel.selectionToken) { _, _ in
            scrolledID = nil
        }
    }

    private var mediaControl: some View {
        FittingSegmentedControl(
            title: "Media",
            options: BrowseMedia.allCases,
            selection: Binding(
                get: { viewModel.media },
                set: { newValue in Task { await viewModel.setMedia(newValue) } }
            ),
            label: { $0.title },
            symbol: { $0.symbol }
        )
        .padding(.horizontal, DesignSpacing.lg)
        .padding(.vertical, DesignSpacing.sm)
    }

    /// Window and sort, in the trailing navigation-bar slot.
    private var filterMenu: some View {
        Menu {
            Picker("Window", selection: windowSelection) {
                ForEach(BrowseWindow.allCases, id: \.self) { option in
                    Label(option.title, systemImage: option.symbol).tag(option)
                }
            }
            .pickerStyle(.inline)

            Picker("Sort", selection: sortSelection) {
                ForEach(BrowseSort.allCases, id: \.self) { option in
                    Label(option.title, systemImage: option.symbol).tag(option)
                }
            }
            .pickerStyle(.inline)
            .disabled(viewModel.window != .all)
        } label: {
            Image(systemName: "line.3.horizontal.decrease.circle")
        }
        .accessibilityLabel("Filters")
        .accessibilityValue("\(viewModel.window.title), \(viewModel.sort.title)")
    }

    private var windowSelection: Binding<BrowseWindow> {
        Binding(
            get: { viewModel.window },
            set: { newValue in Task { await viewModel.setWindow(newValue) } }
        )
    }

    private var sortSelection: Binding<BrowseSort> {
        Binding(
            get: { viewModel.sort },
            set: { newValue in Task { await viewModel.setSort(newValue) } }
        )
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
            case .idle, .loading:
                ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .empty:
                EmptyStateView(
                    title: "Nothing to Browse",
                    message: "No titles match \(viewModel.media.title), \(viewModel.window.title).",
                    systemImage: "film"
                )
            case .loaded(let rows, let activity):
                list(rows, activity: activity)
            case .failed(let error):
                ErrorStateView(error: error) {
                await viewModel.retry()
                }
        }
    }

    private func list(_ rows: [BrowseRow], activity: LoadActivity) -> some View {
        List {
            Section {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    HStack(alignment: .center, spacing: DesignSpacing.sm) {
                        Button {
                            open(row)
                        } label: {
                            CatalogRowView(
                                title: row.title,
                                subtitle: row.genreLine,
                                metadata: row.formattedDate,
                                userScore: row.formattedUserScore,
                                imagePath: row.posterPath,
                                imageKind: .poster,
                                placeholderSystemImage: row.media == .movie ? "film" : "tv",
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
                    .id(row.id)
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
        .scrollPosition(id: $scrolledID)
        .overlay(alignment: .top) {
            LoadActivityBanner(activity: activity)
        }
    }

    private func open(_ row: BrowseRow) {
        switch row.media {
            case .movie:
                router?.push(.movieDetail(id: row.mediaID))
            case .tv:
                router?.push(.tvSeries(id: row.mediaID))
        }
    }
}
