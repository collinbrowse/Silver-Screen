//
//  SearchView.swift
//  TheSilverScreen
//
//  Search tab. An empty field shows award shelves. A query searches Movies,
//  TV, and People. Dismissing the keyboard leaves the current results in place.
//

import SwiftUI
import UIKit

struct SearchView: View {
    @Bindable var viewModel: SearchViewModel
    let imageLoader: ImageLoader
    let lists: ListsRepository
    let listsIndex: ListsIndex
    var router: NavigationRouter?

    @State private var scrollIDs: [SearchScope: Int] = [:]
    /// Mirrors the system search field's focus. Not passed into `.searchable`,
    /// because binding `isPresented` clears the visible query after a pop.
    @State private var fieldPresented = false

    var body: some View {
        Group {
            if viewModel.showsAwardShelves {
                shelfGrid
            } else {
                searchBody
            }
        }
        .background(DesignTheme.canvas)
        .refreshable { await viewModel.refresh() }
        .safeAreaInset(edge: .top, spacing: 0) {
            if viewModel.showsScopePicker {
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
        }
        .navigationTitle("Search")
        .toolbarTitleDisplayMode(.inlineLarge)
        .background {
            if !ProcessInfo.processInfo.isiOSAppOnMac {
                SearchFocusObserver { focused in
                    fieldPresented = focused
                }
            }
        }
        .navigationSearch(
            text: $viewModel.query,
            prompt: searchPrompt,
            isFocused: $fieldPresented
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

    @ViewBuilder
    private var searchBody: some View {
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

    private var shelfGrid: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignSpacing.lg) {
                shelfSection {
                    ForEach(viewModel.shelves) { shelf in
                        Button {
                            openShelf(shelf)
                        } label: {
                            AwardShelfCard(shelf: shelf)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(shelf.title), \(shelf.subtitle)")
                        .accessibilityHint("Opens this award list")
                    }
                }
                
                Text("Genre")
                    .font(DesignTypography.section)
                    .foregroundStyle(DesignTheme.textPrimary)
                    .padding(.horizontal, DesignSpacing.lg)
                
                shelfSection {
                    ForEach(MergedGenre.searchShelf, id: \.self) { genre in
                        Button {
                            open(.genreBrowse(genre))
                        } label: {
                            GenreShelfCard(genre: genre)
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Opens this genre list")
                    }
                }
                .padding(.vertical, DesignSpacing.lg)
            }
        }
    }

    private func shelfSection<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: DesignSpacing.md),
                GridItem(.flexible(), spacing: DesignSpacing.md),
            ],
            spacing: DesignSpacing.md
        ) {
            content()
        }
        .padding(.horizontal, DesignSpacing.lg)
    }

    private func openShelf(_ shelf: AwardShelf) {
        switch shelf.destination {
            case .family(let family):
                open(.awardFamily(family))
            case .titles(let request):
                open(.awardTitles(request))
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
        guard viewModel.showsScopePicker else { return "Search movies, TV, and people" }
        switch viewModel.scope {
            case .movies: return "Search movies"
            case .tv: return "Search TV"
            case .people: return "Search people"
        }
    }

    @ViewBuilder
    private func results(_ listing: SearchListing, activity: LoadActivity) -> some View {
        List {
            Section {
                switch listing {
                    case .movies(let rows):
                        ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                        resultButton(index: index, count: rows.count, showsLoadingRow: activity == .loadingMore, rowID: row.id) {
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
                        resultButton(index: index, count: rows.count, showsLoadingRow: activity == .loadingMore, rowID: row.id) {
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
                        resultButton(index: index, count: rows.count, showsLoadingRow: activity == .loadingMore, rowID: row.id) {
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
            .listSectionSeparatorBetweenCells(isFirstSection: true, isLastSection: true)
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
        if ProcessInfo.processInfo.isiOSAppOnMac {
            fieldPresented = false
        }
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    private func resultButton<Label: View, Star: View>(
        index: Int,
        count: Int,
        showsLoadingRow: Bool,
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
        .listRowSeparatorBetweenCells(isFirst: index == 0, isLast: index == count - 1 && !showsLoadingRow)
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
