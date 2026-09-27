//
//  SearchView.swift
//  TheSilverScreen
//
//  Search tab: Movies, TV, and People segments. The field is the system
//  search UI; dismissing the keyboard leaves the current results in place.
//

import SwiftUI

struct SearchView: View {
    @Bindable var viewModel: SearchViewModel
    let imageLoader: ImageLoader
    let lists: ListsRepository
    let listsIndex: ListsIndex
    var isSearchPresented: Binding<Bool> = .constant(false)
    var router: NavigationRouter?

    @State private var scrollIDs: [SearchScope: Int] = [:]

    var body: some View {
        Group {
            switch viewModel.state {
            case .idle, .loading:
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .empty:
                if viewModel.showsFocusedPlaceholder {
                    Button {
                        isSearchPresented.wrappedValue = false
                    } label: {
                        emptyState
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Dismisses search and restores the last results")
                } else {
                    emptyState
                }
            case .loaded(let listing, let activity):
                results(listing, activity: activity)
            case .failed(let error):
                ErrorStateView(error: error) {
                    await viewModel.retry()
                }
            }
        }
        .background(DesignTheme.canvas)
        .refreshable { await viewModel.refresh() }
        .safeAreaInset(edge: .top, spacing: 0) {
            Picker("Search", selection: $viewModel.scope) {
                ForEach(SearchScope.allCases, id: \.self) { scope in
                    Text(scope.title).tag(scope)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, DesignSpacing.lg)
            .padding(.vertical, DesignSpacing.sm)
            .background(DesignTheme.canvas)
            .accessibilityLabel("Search category")
        }
        .navigationTitle("Search")
        .toolbarTitleDisplayMode(.inlineLarge)
        .searchable(
            text: $viewModel.query,
            isPresented: isSearchPresented,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: searchPrompt
        )
        .scrollDismissesKeyboard(.immediately)
        .onChange(of: viewModel.query) { _, _ in
            viewModel.scheduleQueryChange()
        }
        .onChange(of: viewModel.scope) { _, _ in
            Task { await viewModel.reloadForScopeChange() }
        }
        .onChange(of: isSearchPresented.wrappedValue) { _, focused in
            viewModel.setFieldFocused(focused)
        }
        .onAppear {
            Task { await viewModel.reloadDisplayedScores() }
        }
        .onChange(of: router?.path.count ?? 0) { _, _ in
            Task { await viewModel.reloadDisplayedScores() }
        }
        .onChange(of: viewModel.committedQuery) { _, _ in
            scrollIDs = [:]
        }
        .onDisappear { viewModel.cancelDebounce() }
        .task {
            if case .idle = viewModel.state {
                await viewModel.load()
            }
        }
    }

    private var emptyState: some View {
        EmptyStateView(
            title: viewModel.emptyTitle,
            message: viewModel.emptyMessage,
            systemImage: "magnifyingglass"
        )
    }

    private var searchPrompt: String {
        switch viewModel.scope {
        case .movies: "Search movies"
        case .tv: "Search TV"
        case .people: "Search people"
        }
    }

    @ViewBuilder
    private func results(_ listing: SearchListing, activity: LoadActivity) -> some View {
        List {
            switch listing {
            case .movies(let rows):
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    resultButton(index: index, count: rows.count, rowID: row.id) {
                        open(.movieDetail(id: row.id))
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
                    } star: {
                        listControl(row.listItem())
                    }
                }
            case .tv(let rows):
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    resultButton(index: index, count: rows.count, rowID: row.id) {
                        open(.tvSeries(id: row.id))
                    } label: {
                        CatalogRowView(
                            title: row.name,
                            subtitle: row.genreNames.joined(separator: ", "),
                            metadata: row.formattedFirstAirDate,
                            userScore: row.formattedUserScore,
                            imagePath: row.posterPath,
                            imageKind: .poster,
                            placeholderSystemImage: "tv",
                            imageLoader: imageLoader
                        )
                    } star: {
                        listControl(row.listItem())
                    }
                }
            case .people(let rows):
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    resultButton(index: index, count: rows.count, rowID: row.id) {
                        open(.person(id: row.id))
                    } label: {
                        CatalogRowView(
                            title: row.name,
                            subtitle: "",
                            metadata: row.knownForDepartment ?? "",
                            imagePath: row.profilePath,
                            imageKind: .profile,
                            placeholderSystemImage: "person.fill",
                            imageLoader: imageLoader
                        )
                    } star: {
                        listControl(row.listItem())
                    }
                }
            }

            if activity == .loadingMore {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .scrollPosition(id: Binding(
            get: { scrollIDs[viewModel.scope] },
            set: { scrollIDs[viewModel.scope] = $0 }
        ))
        .overlay(alignment: .top) {
            LoadActivityBanner(activity: activity)
        }
    }

    /// Leaves the field so Back returns to the results instead of a focused search.
    private func open(_ route: Route) {
        isSearchPresented.wrappedValue = false
        router?.push(route)
    }

    private func resultButton<Label: View, Star: View>(
        index: Int,
        count: Int,
        rowID: Int,
        action: @escaping () -> Void,
        @ViewBuilder label: () -> Label,
        @ViewBuilder star: () -> Star
    ) -> some View {
        HStack(alignment: .center, spacing: DesignSpacing.sm) {
            Button(action: action) {
                label()
            }
            .buttonStyle(.plain)
            star()
        }
        .id(rowID)
        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 8))
        .onAppear {
            if index == count - 1 {
                Task { await viewModel.loadMore() }
            }
        }
    }

    private func listControl(_ draft: ListItemDraft) -> some View {
        ListMembershipButton(draft: draft, lists: lists, index: listsIndex) {
            viewModel.noteListSaveFailed()
        }
    }
}
