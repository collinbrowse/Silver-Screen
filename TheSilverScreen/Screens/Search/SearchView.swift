//
//  SearchView.swift
//  TheSilverScreen
//
//  Search tab. An empty field shows award shelves. Typing shows a Spotify-style
//  preview (top five per type; People first when results say so). View all /
//  Enter opens the ranked list with niche and Genre filters.
//

import SwiftUI
import UIKit

struct SearchView: View {
    @Bindable var viewModel: SearchViewModel
    let imageLoader: ImageLoader
    let lists: ListsRepository
    let listsIndex: ListsIndex
    let shows: TVRepository
    let tvWatch: TVWatchRepository
    var router: NavigationRouter?

    @State private var scrollID: String?
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
            if viewModel.showsFilterPills {
                SearchFilterPills(
                    typeNiche: viewModel.typeNiche,
                    genreFilter: viewModel.genreFilter,
                    onSelectNiche: { viewModel.selectTypeNiche($0) },
                    onSelectGenre: { viewModel.selectGenreFilter($0) }
                )
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
            prompt: "Search movies, TV, and people",
            isFocused: $fieldPresented,
            onSubmit: { viewModel.openAllResults() }
        )
        .scrollDismissesKeyboard(.immediately)
        .onChange(of: viewModel.query) { _, _ in
            viewModel.scheduleQueryChange()
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
            scrollID = nil
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
            case .loaded(let content, let activity):
                results(content, activity: activity)
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

    @ViewBuilder
    private func results(_ content: SearchContent, activity: LoadActivity) -> some View {
        switch content {
            case .preview(let sections):
                previewList(sections, activity: activity)
            case .allResults(let items):
                allResultsList(items, activity: activity)
        }
    }

    private func previewList(_ sections: SearchPreviewSections, activity: LoadActivity) -> some View {
        List {
            switch sections.emphasis {
                case .titlesFirst:
                    previewMoviesSection(sections.movies)
                    previewTVSection(sections.tv)
                    previewPeopleSection(sections.people)
                case .peopleFirst:
                    previewPeopleSection(sections.people)
                    previewMoviesSection(sections.movies)
                    previewTVSection(sections.tv)
            }

            Section {
                SearchViewAllRow(query: viewModel.committedQuery) {
                    viewModel.openAllResults()
                }
                .listRowInsets(EdgeInsets(
                    top: DesignSpacing.sm,
                    leading: DesignSpacing.lg,
                    bottom: DesignSpacing.md,
                    trailing: DesignSpacing.lg
                ))
                .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .scrollPosition(id: $scrollID)
        .overlay(alignment: .top) {
            LoadActivityBanner(activity: activity)
        }
    }

    @ViewBuilder
    private func previewMoviesSection(_ rows: [CatalogMovieRow]) -> some View {
        if !rows.isEmpty {
            Section {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    resultButton(
                        index: index,
                        count: rows.count,
                        showsLoadingRow: false,
                        rowID: "m-\(row.id)",
                        loadsMore: false
                    ) {
                        open(.movieDetail(id: row.id))
                    } label: {
                        movieRowLabel(row)
                    } star: {
                        listControl(row.listItem())
                    }
                }
            } header: {
                Text("Movies")
            }
        }
    }

    @ViewBuilder
    private func previewTVSection(_ rows: [CatalogTVRow]) -> some View {
        if !rows.isEmpty {
            Section {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    resultButton(
                        index: index,
                        count: rows.count,
                        showsLoadingRow: false,
                        rowID: "t-\(row.id)",
                        loadsMore: false
                    ) {
                        open(.tvSeries(id: row.id))
                    } label: {
                        tvRowLabel(row)
                    } star: {
                        listControl(row.listItem())
                    }
                }
            } header: {
                Text("TV")
            }
        }
    }

    @ViewBuilder
    private func previewPeopleSection(_ rows: [CatalogPersonRow]) -> some View {
        if !rows.isEmpty {
            Section {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    resultButton(
                        index: index,
                        count: rows.count,
                        showsLoadingRow: false,
                        rowID: "p-\(row.id)",
                        loadsMore: false
                    ) {
                        open(.person(id: row.id))
                    } label: {
                        personRowLabel(row)
                    } star: {
                        listControl(row.listItem())
                    }
                }
            } header: {
                Text("People")
            }
        }
    }

    private func allResultsList(_ items: [SearchResultItem], activity: LoadActivity) -> some View {
        List {
            Section {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    resultButton(
                        index: index,
                        count: items.count,
                        showsLoadingRow: activity == .loadingMore,
                        rowID: item.id,
                        loadsMore: true
                    ) {
                        open(route(for: item))
                    } label: {
                        itemLabel(item)
                    } star: {
                        listControl(listItem(for: item))
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
        .scrollPosition(id: $scrollID)
        .overlay(alignment: .top) {
            LoadActivityBanner(activity: activity)
        }
    }

    @ViewBuilder
    private func itemLabel(_ item: SearchResultItem) -> some View {
        switch item {
            case .movie(let row):
                movieRowLabel(row, density: .standard, showsKind: true)
            case .tv(let row):
                tvRowLabel(row, density: .standard, showsKind: true)
            case .person(let row):
                personRowLabel(row, density: .standard, showsKind: true)
        }
    }

    private func movieRowLabel(
        _ row: CatalogMovieRow,
        density: CatalogRowView.Density = .compact,
        showsKind: Bool = false
    ) -> some View {
        CatalogRowView(
            title: row.title,
            subtitle: row.genreNames.joined(separator: ", "),
            metadata: row.formattedReleaseDate,
            userScore: row.formattedUserScore,
            kindLabel: showsKind ? "Movie" : nil,
            density: density,
            imagePath: row.posterPath,
            imageKind: .poster,
            placeholderSystemImage: "film",
            imageLoader: imageLoader
        )
    }

    private func tvRowLabel(
        _ row: CatalogTVRow,
        density: CatalogRowView.Density = .compact,
        showsKind: Bool = false
    ) -> some View {
        CatalogRowView(
            title: row.name,
            subtitle: row.genreNames.joined(separator: ", "),
            metadata: row.formattedFirstAirDate,
            userScore: row.formattedUserScore,
            kindLabel: showsKind ? "TV" : nil,
            density: density,
            imagePath: row.posterPath,
            imageKind: .poster,
            placeholderSystemImage: "tv",
            imageLoader: imageLoader
        )
    }

    private func personRowLabel(
        _ row: CatalogPersonRow,
        density: CatalogRowView.Density = .compact,
        showsKind: Bool = false
    ) -> some View {
        CatalogRowView(
            title: row.name,
            subtitle: "",
            metadata: row.knownForDepartment ?? "",
            kindLabel: showsKind ? "Person" : nil,
            density: density,
            imagePath: row.profilePath,
            imageKind: .profile,
            placeholderSystemImage: "person.fill",
            imageLoader: imageLoader
        )
    }

    private func route(for item: SearchResultItem) -> Route {
        switch item {
            case .movie(let row): .movieDetail(id: row.id)
            case .tv(let row): .tvSeries(id: row.id)
            case .person(let row): .person(id: row.id)
        }
    }

    private func listItem(for item: SearchResultItem) -> ListItemDraft {
        switch item {
            case .movie(let row): row.listItem()
            case .tv(let row): row.listItem()
            case .person(let row): row.listItem()
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
        rowID: String,
        loadsMore: Bool,
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
        .listRowInsets(EdgeInsets(
            top: loadsMore ? 8 : 4,
            leading: 16,
            bottom: loadsMore ? 8 : 4,
            trailing: 8
        ))
        .listRowSeparatorBetweenCells(isFirst: index == 0, isLast: index == count - 1 && !showsLoadingRow)
        .onAppear {
            if loadsMore, index == count - 1 {
                Task { await viewModel.loadMore() }
            }
        }
    }

    @ViewBuilder
    private func listControl(_ draft: ListItemDraft) -> some View {
        switch draft.kind {
            case .movie, .tv:
                WatchedToggleButton(
                    draft: draft,
                    lists: lists,
                    index: listsIndex,
                    tvWatch: tvWatch,
                    shows: shows
                ) {
                    viewModel.noteListSaveFailed()
                }
            case .person:
                ListMembershipButton(draft: draft, lists: lists, index: listsIndex) {
                    viewModel.noteListSaveFailed()
                }
        }
    }
}
