//
//  SearchView.swift
//  SilverScreen
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
    /// Where the iPhone Duo's fold crosses the shelf page, or nil.
    @State private var shelfFold: FoldSplit?
    /// Mirrors the system search field's focus. Not passed into `.searchable`,
    /// because binding `isPresented` clears the visible query after a pop.
    @State private var fieldPresented = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

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

    /// Two cards a row on a phone, more as the width allows; see `ShelfGridMetrics`.
    /// The three award cards never leave empty slots beside them. Across the iPhone
    /// Duo's fold each section becomes one grid per pane, so no card sits on the crease.
    private var shelfGrid: some View {
        ContentWidthReader { width in
            let columns = ShelfGridMetrics.columnCount(forWidth: width)
            ScrollView {
                VStack(alignment: .leading, spacing: DesignSpacing.lg) {
                    shelves(
                        viewModel.shelves,
                        id: \.id,
                        columns: min(columns, viewModel.shelves.count),
                        cell: awardShelfButton
                    )

                    Text("Genre")
                        .font(DesignTypography.section)
                        .foregroundStyle(DesignTheme.textPrimary)
                        .padding(.horizontal, DesignSpacing.lg)

                    shelves(MergedGenre.searchShelf, id: \.self, columns: columns, cell: genreShelfButton)
                        .padding(.vertical, DesignSpacing.lg)
                }
            }
            .onFoldSplitChange { shelfFold = $0 }
        }
    }

    private func awardShelfButton(_ shelf: AwardShelf) -> some View {
        Button {
            openShelf(shelf)
        } label: {
            AwardShelfCard(shelf: shelf)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(shelf.title), \(shelf.subtitle)")
        .accessibilityHint("Opens this award list")
    }

    private func genreShelfButton(_ genre: MergedGenre) -> some View {
        Button {
            open(.genreBrowse(genre))
        } label: {
            GenreShelfCard(genre: genre)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens this genre list")
    }

    /// One shelf section: a single grid, or one grid per pane across a fold with the
    /// cards dealt row by row so reading order holds.
    @ViewBuilder
    private func shelves<Item, ID: Hashable, Cell: View>(
        _ items: [Item],
        id: KeyPath<Item, ID>,
        columns: Int,
        cell: @escaping (Item) -> Cell
    ) -> some View {
        if let shelfFold {
            let perPane = FoldLayout.columnsPerPane(
                split: shelfFold,
                minimumCardWidth: ShelfGridMetrics.minimumCardWidth,
                spacing: ShelfGridMetrics.cardSpacing,
                sideInset: ShelfGridMetrics.sideInset
            )
            let panes = FoldLayout.distribute(items, perPane: perPane)
            FoldPanesLayout(split: shelfFold) {
                shelfGridSection(panes.leading, id: id, columns: perPane, cell: cell)
                    .padding(.leading, ShelfGridMetrics.sideInset)
                shelfGridSection(panes.trailing, id: id, columns: perPane, cell: cell)
                    .padding(.trailing, ShelfGridMetrics.sideInset)
            }
        } else {
            shelfGridSection(items, id: id, columns: columns, cell: cell)
                .padding(.horizontal, ShelfGridMetrics.sideInset)
        }
    }

    private func shelfGridSection<Item, ID: Hashable, Cell: View>(
        _ items: [Item],
        id: KeyPath<Item, ID>,
        columns: Int,
        cell: @escaping (Item) -> Cell
    ) -> some View {
        LazyVGrid(
            columns: Array(
                repeating: GridItem(.flexible(), spacing: ShelfGridMetrics.cardSpacing),
                count: max(columns, 1)
            ),
            spacing: ShelfGridMetrics.cardSpacing
        ) {
            ForEach(items, id: id) { item in
                cell(item)
            }
        }
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
        ContentWidthReader { width in
            let columns = catalogColumns(forWidth: width)
            List {
                switch sections.emphasis {
                    case .titlesFirst:
                        previewMoviesSection(sections.movies, columns: columns)
                        previewTVSection(sections.tv, columns: columns)
                        previewPeopleSection(sections.people, columns: columns)
                    case .peopleFirst:
                        previewPeopleSection(sections.people, columns: columns)
                        previewMoviesSection(sections.movies, columns: columns)
                        previewTVSection(sections.tv, columns: columns)
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
    }

    private func catalogColumns(forWidth width: CGFloat) -> Int {
        CatalogGridMetrics.columnCount(forWidth: width, isAccessibilitySize: dynamicTypeSize.isAccessibilitySize)
    }

    @ViewBuilder
    private func previewMoviesSection(_ rows: [CatalogMovieRow], columns: Int) -> some View {
        if !rows.isEmpty {
            Section {
                resultRows(
                    rows,
                    columns: columns,
                    scrollPrefix: "m-",
                    loadsMore: false,
                    showsLoadingRow: false
                ) { row in
                    resultCell(density: .compact) {
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
    private func previewTVSection(_ rows: [CatalogTVRow], columns: Int) -> some View {
        if !rows.isEmpty {
            Section {
                resultRows(
                    rows,
                    columns: columns,
                    scrollPrefix: "t-",
                    loadsMore: false,
                    showsLoadingRow: false
                ) { row in
                    resultCell(density: .compact) {
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
    private func previewPeopleSection(_ rows: [CatalogPersonRow], columns: Int) -> some View {
        if !rows.isEmpty {
            Section {
                resultRows(
                    rows,
                    columns: columns,
                    scrollPrefix: "p-",
                    loadsMore: false,
                    showsLoadingRow: false
                ) { row in
                    resultCell(density: .compact) {
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
        ContentWidthReader { width in
            List {
                Section {
                    resultRows(
                        items,
                        columns: catalogColumns(forWidth: width),
                        scrollPrefix: "",
                        loadsMore: true,
                        showsLoadingRow: activity == .loadingMore
                    ) { item in
                        resultCell(density: .standard) {
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
            nextUp: nil,
            genre: row.genreNames.joined(separator: ", "),
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
            nextUp: row.nextUp,
            genre: row.genreNames.joined(separator: ", "),
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
            nextUp: nil,
            genre: "",
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

    /// List rows of `columns` results each. `scrollPrefix` keeps scroll ids unique
    /// when a movie and a show share a TMDB id; `loadsMore` pages when the last row appears.
    private func resultRows<Item: Identifiable, Cell: View>(
        _ items: [Item],
        columns: Int,
        scrollPrefix: String,
        loadsMore: Bool,
        showsLoadingRow: Bool,
        @ViewBuilder cell: @escaping (Item) -> Cell
    ) -> some View {
        ForEach(CatalogGrid.rows(items, columns: columns, id: \.id)) { gridRow in
            CatalogColumnsRow(row: gridRow, columns: columns, id: \.id, cell: cell)
                .id("\(scrollPrefix)\(gridRow.id)")
                .listRowInsets(EdgeInsets(
                    top: loadsMore ? 8 : 4,
                    leading: 16,
                    bottom: loadsMore ? 8 : 4,
                    trailing: 8
                ))
                .listRowSeparatorBetweenCells(isFirst: gridRow.isFirst, isLast: gridRow.isLast && !showsLoadingRow)
                .onAppear {
                    if loadsMore, gridRow.isLast {
                        Task { await viewModel.loadMore() }
                    }
                }
        }
    }

    private func resultCell<Label: View, Star: View>(
        density: CatalogRowView.Density,
        action: @escaping () -> Void,
        @ViewBuilder label: () -> Label,
        @ViewBuilder star: () -> Star
    ) -> some View {
        CatalogRowLayout(density: density) {
            Button(action: action) {
                label()
            }
            .buttonStyle(.plain)
        } control: {
            star()
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
