//
//  SearchView.swift
//  TheSilverScreen
//
//  Search tab: Movies, TV, and People segments. The field is the system
//  search UI; dismissing the keyboard leaves the current results in place.
//

import SwiftUI
import UIKit

struct SearchView: View {
    @Bindable var viewModel: SearchViewModel
    let imageLoader: ImageLoader
    let favorites: FavoritesRepository
    let favoritesIndex: FavoritesIndex
    var router: NavigationRouter?

    @State private var scrollIDs: [SearchScope: Int] = [:]
    /// Mirrors the system search field's focus. Not passed into `.searchable`,
    /// because binding `isPresented` clears the visible query after a pop.
    @State private var fieldPresented = false

    var body: some View {
        Group {
            switch viewModel.state {
            case .idle, .loading:
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .empty:
                if viewModel.showsFocusedPlaceholder {
                    Button {
                        dismissSearchKeyboard()
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
        .background {
            SearchFocusObserver { focused in
                fieldPresented = focused
            }
        }
        .searchable(
            text: $viewModel.query,
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
        .onChange(of: fieldPresented) { _, focused in
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
                        favoriteStar(name: row.title, id: row.id, kind: .movie) {
                            await toggleFavorite { try await favorites.toggle(movie: row.asMovie()) }
                        }
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
                        favoriteStar(name: row.name, id: row.id, kind: .tv) {
                            await toggleFavorite { try await favorites.toggle(tv: row.asSeries()) }
                        }
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
                        favoriteStar(name: row.name, id: row.id, kind: .person) {
                            await toggleFavorite { try await favorites.toggle(person: row.asPerson()) }
                        }
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

    /// Dismisses the keyboard, then pushes the result. The query stays in the field.
    private func open(_ route: Route) {
        dismissSearchKeyboard()
        router?.push(route)
    }

    private func dismissSearchKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
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

    private func toggleFavorite(_ save: () async throws -> Void) async {
        do {
            try await save()
        } catch {
            viewModel.noteFavoriteSaveFailed()
        }
    }

    private func favoriteStar(
        name: String,
        id: Int,
        kind: FavoriteKind,
        toggle: @escaping () async -> Void
    ) -> some View {
        CellFavoriteStar(
            name: name,
            isFavorite: favoritesIndex.contains(id, kind: kind)
        ) {
            Task { await toggle() }
        }
    }
}

/// Reads whether the system search field is focused. Lives under `.searchable`
/// so it can see `isSearching`, which the search screen itself cannot.
private struct SearchFocusObserver: View {
    var onChange: (Bool) -> Void
    @Environment(\.isSearching) private var isSearching

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onAppear { onChange(isSearching) }
            .onChange(of: isSearching) { _, focused in
                onChange(focused)
            }
    }
}
