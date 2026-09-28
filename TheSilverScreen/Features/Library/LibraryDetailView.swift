//
//  LibraryDetailView.swift
//  TheSilverScreen
//
//  Titles on one list. Sort is only offered for Watched and Watchlist.
//  Reorder is off while search or the Movies / TV filter is hiding rows.
//

import SwiftUI

struct LibraryDetailView: View {
    @Bindable var viewModel: LibraryDetailViewModel
    let imageLoader: ImageLoader
    var router: NavigationRouter?
    @Environment(ListChangeNotice.self) private var notice
    let lists: ListsRepository

    @State private var editMode: EditMode = .inactive

    var body: some View {
        Group {
            switch viewModel.state {
            case .idle, .loading:
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .empty:
                EmptyStateView(
                    title: "List Unavailable",
                    message: "That list no longer exists.",
                    systemImage: "books.vertical"
                )
            case .loaded(let detail, let activity):
                loaded(detail, activity: activity)
            case .failed(let error):
                ErrorStateView(error: error) {
                    await viewModel.load()
                }
            }
        }
        .background(DesignTheme.canvas)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(
            text: $viewModel.searchText,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Find title"
        )
        .toolbar {
            if case .loaded(let detail, _) = viewModel.state, detail.list.system != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    sortMenu(detail.list)
                }
            } else if viewModel.allowsReorder {
                ToolbarItem(placement: .topBarTrailing) {
                    EditButton()
                        .accessibilityLabel(editMode == .active ? "Done reordering" : "Reorder")
                }
            }
        }
        .environment(\.editMode, $editMode)
        .onChange(of: viewModel.allowsReorder) { _, canReorder in
            if !canReorder {
                editMode = .inactive
            }
        }
        .onAppear {
            Task { await viewModel.load() }
        }
    }

    private var title: String {
        if case .loaded(let detail, _) = viewModel.state {
            return detail.list.name
        }
        return "List"
    }

    private func loaded(_ detail: LibraryListDetail, activity: LoadActivity) -> some View {
        let entries = viewModel.displayedEntries
        return Group {
            if entries.isEmpty {
                EmptyStateView(
                    title: emptyTitle(detail),
                    message: emptyMessage(detail),
                    systemImage: "line.3.horizontal.decrease.circle"
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(entries) { entry in
                        entryLink(entry)
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button("Remove", role: .destructive) {
                                    Task { await remove(entry) }
                                }
                                .accessibilityLabel("Remove \(entry.title)")
                            }
                    }
                    .onMove(perform: viewModel.allowsReorder ? { source, destination in
                        Task { await viewModel.moveEntries(from: source, to: destination) }
                    } : nil)
                }
                .listStyle(.plain)
                .environment(\.editMode, viewModel.allowsReorder ? $editMode : .constant(.inactive))
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if detail.list.segment == .moviesAndTV {
                mediaFilter
                    .background(DesignTheme.canvas)
            }
        }
        .overlay(alignment: .top) {
            LoadActivityBanner(activity: activity)
        }
    }

    private var mediaFilter: some View {
        Picker("Filter titles", selection: $viewModel.mediaFilter) {
            ForEach(TitleMediaFilter.allCases, id: \.self) { filter in
                Text(filter.title).tag(filter)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, DesignSpacing.lg)
        .padding(.vertical, DesignSpacing.sm)
        .accessibilityLabel("Filter titles")
    }

    private func sortMenu(_ list: LibraryList) -> some View {
        Menu {
            Picker("Sort", selection: Binding(
                get: { list.sort },
                set: { sort in Task { await viewModel.setSort(sort) } }
            )) {
                ForEach(LibrarySort.allCases, id: \.self) { sort in
                    Label(sort.title, systemImage: sort.symbol).tag(sort)
                }
            }
        } label: {
            Label("Sort", systemImage: "arrow.up.arrow.down")
        }
        .accessibilityLabel("Sort")
        .accessibilityValue(list.sort.title)
    }

    private func entryLink(_ entry: ListEntry) -> some View {
        Button {
            router?.push(route(for: entry))
        } label: {
            CatalogRowView(
                title: entry.title,
                subtitle: entry.genreNames.joined(separator: ", "),
                metadata: metadata(for: entry),
                userScore: viewModel.userScores[entry.itemKey]?.formatted,
                imagePath: entry.imagePath,
                imageKind: entry.kind == .person ? .profile : .poster,
                placeholderSystemImage: placeholder(for: entry.kind),
                imageLoader: imageLoader
            )
        }
        .buttonStyle(.plain)
        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
    }

    private func route(for entry: ListEntry) -> Route {
        switch entry.kind {
        case .movie: .movieDetail(id: entry.itemID)
        case .tv: .tvSeries(id: entry.itemID)
        case .person: .person(id: entry.itemID)
        }
    }

    private func metadata(for entry: ListEntry) -> String {
        switch entry.kind {
        case .person: "Person"
        case .movie, .tv: DisplayDate.day(entry.releaseDate)
        }
    }

    private func placeholder(for kind: ListItemKind) -> String {
        switch kind {
        case .movie: "film"
        case .tv: "tv"
        case .person: "person.fill"
        }
    }

    private func emptyTitle(_ detail: LibraryListDetail) -> String {
        let query = viewModel.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty || (detail.list.segment == .moviesAndTV && viewModel.mediaFilter != .all) {
            return "No Matches"
        }
        return "Nothing Here"
    }

    private func emptyMessage(_ detail: LibraryListDetail) -> String {
        let query = viewModel.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty {
            return "Nothing matches \"\(query)\"."
        }
        if detail.list.segment == .moviesAndTV, viewModel.mediaFilter == .movies {
            return "No movies on this list."
        }
        if detail.list.segment == .moviesAndTV, viewModel.mediaFilter == .tv {
            return "No TV on this list."
        }
        if detail.list.segment == .people {
            return "Add a person from Search."
        }
        return "Add a title from Browse or Search."
    }

    private func remove(_ entry: ListEntry) async {
        guard let change = await viewModel.remove(entry) else { return }
        notice.show(change, using: lists)
    }
}
