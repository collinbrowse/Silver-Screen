//
//  LibraryHomeView.swift
//  SilverScreen
//
//  Movies & TV and People are separate libraries. Watched and Watchlist stay
//  pinned. Custom lists can be reordered, renamed, and deleted.
//

import SwiftUI

struct LibraryHomeView: View {
    @Bindable var viewModel: LibraryHomeViewModel
    let imageLoader: ImageLoader
    let settings: SettingsContext
    @State private var showingSettings = false
    @State private var editMode: EditMode = .inactive
    @State private var showingNameDialog = false
    @State private var nameDialogIsRename = false
    @State private var dialogName = ""
    @State private var renameTarget: LibraryList?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            switch viewModel.state {
                case .idle, .loading:
                    ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .empty:
                    EmptyStateView(
                        title: "No Lists",
                        message: emptyMessage,
                        systemImage: "books.vertical"
                    )
                case .loaded(_, let activity):
                    list
                    .overlay(alignment: .top) {
                        LoadActivityBanner(activity: activity)
                    }
                case .failed(let error):
                    ErrorStateView(error: error) {
                    await viewModel.load()
                    }
            }
        }
        .background(DesignTheme.canvas)
        .safeAreaInset(edge: .top, spacing: 0) {
            if case .loaded = viewModel.state {
                segmentPicker
                    .background(DesignTheme.canvas)
            }
        }
        .navigationSearch(text: $viewModel.searchText, prompt: "Find list")
        .navigationTitle("Library")
        .toolbarTitleDisplayMode(.inlineLarge)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    showingSettings = true
                } label: {
                    Image(systemName: "gearshape")
                }
                .accessibilityLabel("Settings")
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                if viewModel.canReorderLists {
                    EditButton()
                        .accessibilityLabel(editMode == .active ? "Done reordering" : "Reorder lists")
                }
                Button {
                    viewModel.nameError = nil
                    dialogName = ""
                    nameDialogIsRename = false
                    renameTarget = nil
                    showingNameDialog = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("New list")
            }
        }
        .environment(\.editMode, $editMode)
        .sheet(isPresented: $showingSettings) {
            SettingsView(context: settings)
        }
        .onChange(of: viewModel.canReorderLists) { _, canReorder in
            if !canReorder {
                editMode = .inactive
            }
        }
        .onChange(of: viewModel.segment) { _, _ in
            editMode = .inactive
        }
        .listNamePrompt(
            title: nameDialogIsRename ? "Rename List" : "New List",
            confirmTitle: nameDialogIsRename ? "Save" : "Create",
            name: $dialogName,
            errorMessage: viewModel.nameError,
            isPresented: $showingNameDialog
        ) { submitted in
            let target = renameTarget
            let renaming = nameDialogIsRename
            Task {
                if renaming, let target {
                    await finishRename(target, to: submitted)
                } else {
                    await finishCreate(named: submitted)
                }
            }
        }
        .onAppear {
            Task { await viewModel.load() }
        }
    }

    private var segmentPicker: some View {
        Picker("Library", selection: $viewModel.segment) {
            ForEach(LibrarySegment.allCases, id: \.self) { segment in
                Text(segment.title).tag(segment)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, DesignSpacing.lg)
        .padding(.vertical, DesignSpacing.sm)
        .readableColumn()
        .foldPane()
        .accessibilityLabel("Library")
    }

    private var list: some View {
        let displayed = viewModel.displayedLists
        let system = displayed.filter { $0.isSystem }
        let custom = displayed.filter { !$0.isSystem }
        return Group {
            if displayed.isEmpty {
                EmptyStateView(
                    title: noMatchesTitle,
                    message: noMatchesMessage,
                    systemImage: "magnifyingglass"
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ContentWidthReader { width in
                    // Reordering drags whole rows, so edit mode is always one column.
                    let columns = editMode.isEditing
                        ? 1
                        : CatalogGridMetrics.columnCount(
                            forWidth: width,
                            isAccessibilitySize: dynamicTypeSize.isAccessibilitySize
                        )
                    List {
                        if !system.isEmpty {
                            Section {
                                if columns == 1 {
                                    ForEach(Array(system.enumerated()), id: \.element.id) { index, list in
                                        listLink(list)
                                            .listRowSeparatorBetweenCells(
                                                isFirst: index == 0,
                                                isLast: custom.isEmpty && index == system.count - 1
                                            )
                                    }
                                } else {
                                    columnRows(system, columns: columns, isFirstSection: true, isLastSection: custom.isEmpty)
                                }
                            }
                            .listSectionSeparatorBetweenCells(isFirstSection: true, isLastSection: custom.isEmpty)
                        }
                        if !custom.isEmpty {
                            Section {
                                if columns == 1 {
                                    customRows(custom, isFirstSection: system.isEmpty)
                                } else {
                                    columnRows(custom, columns: columns, isFirstSection: system.isEmpty, isLastSection: true)
                                }
                            }
                            .listSectionSeparatorBetweenCells(isFirstSection: system.isEmpty, isLastSection: true)
                        }
                    }
                    .listStyle(.plain)
                    .environment(\.editMode, viewModel.canReorderLists ? $editMode : .constant(.inactive))
                }
            }
        }
    }

    /// Custom lists one per row, with swipe to rename or delete and drag to reorder.
    private func customRows(_ custom: [LibraryList], isFirstSection: Bool) -> some View {
        ForEach(Array(custom.enumerated()), id: \.element.id) { index, list in
            listLink(list)
                .listRowSeparatorBetweenCells(
                    isFirst: isFirstSection && index == 0,
                    isLast: index == custom.count - 1
                )
                .swipeActions(edge: .leading, allowsFullSwipe: false) {
                    Button("Rename") {
                        beginRename(list)
                    }
                    .accessibilityLabel("Rename \(list.name)")
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button("Delete", role: .destructive) {
                        Task { await viewModel.delete(list) }
                    }
                    .accessibilityLabel("Delete \(list.name)")
                }
                .contextMenu {
                    customListActions(list)
                }
        }
        .onMove(perform: viewModel.canReorderLists ? { source, destination in
            Task { await viewModel.moveLists(from: source, to: destination) }
            } : nil)
    }

    /// Two or three lists per row on a wide screen. A swipe would act on the whole
    /// row, so custom lists offer Rename and Delete from their context menu and as
    /// VoiceOver actions. A plain button style keeps each link's tap to its own cell.
    private func columnRows(
        _ lists: [LibraryList],
        columns: Int,
        isFirstSection: Bool,
        isLastSection: Bool
    ) -> some View {
        ForEach(CatalogGrid.rows(lists, columns: columns, id: \.id)) { row in
            CatalogColumnsRow(row: row, columns: columns, id: \.id) { list in
                listLink(list)
                    .buttonStyle(.plain)
                    .contextMenu {
                        if !list.isSystem {
                            customListActions(list)
                        }
                    }
                    .accessibilityActions {
                        if !list.isSystem {
                            customListActions(list)
                        }
                    }
            }
            .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
            .listRowSeparatorBetweenCells(
                isFirst: isFirstSection && row.isFirst,
                isLast: isLastSection && row.isLast
            )
        }
    }

    @ViewBuilder
    private func customListActions(_ list: LibraryList) -> some View {
        Button("Rename") { beginRename(list) }
        Button("Delete", role: .destructive) {
            Task { await viewModel.delete(list) }
        }
    }

    private func listLink(_ list: LibraryList) -> some View {
        NavigationLink(value: Route.libraryList(id: list.id)) {
            HStack(alignment: .center, spacing: DesignSpacing.md) {
                LibraryListCoverView(
                    artwork: viewModel.artwork(for: list),
                    segment: list.segment,
                    imageLoader: imageLoader
                )
                VStack(alignment: .leading, spacing: DesignSpacing.xs) {
                    Text(list.name)
                        .font(DesignTypography.section)
                        .foregroundStyle(DesignTheme.textPrimary)
                    Text(countText(for: list))
                        .font(DesignTypography.metadata)
                        .foregroundStyle(DesignTheme.textSecondary)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
            .accessibilityElement(children: .combine)
        }
        .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
    }

    private func countText(for list: LibraryList) -> String {
        let count = viewModel.membershipCount(for: list.id)
        let noun: String
        if list.segment == .people {
            noun = count == 1 ? "person" : "people"
        } else {
            noun = count == 1 ? "title" : "titles"
        }
        if count == 0 {
            return list.segment == .people ? "No people" : "No titles"
        }
        return "\(count) \(noun)"
    }

    private var emptyMessage: String {
        viewModel.segment == .people
            ? "Create a list to save people."
            : "Your lists will show up here."
    }

    private var noMatchesTitle: String {
        let query = viewModel.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if query.isEmpty, viewModel.segment == .people {
            return "No Lists"
        }
        return "No Matches"
    }

    private var noMatchesMessage: String {
        let query = viewModel.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if query.isEmpty, viewModel.segment == .people {
            return "Create a list to save people."
        }
        if query.isEmpty {
            return "No lists match."
        }
        return "No lists match \"\(query)\"."
    }

    private func beginRename(_ list: LibraryList) {
        viewModel.nameError = nil
        dialogName = list.name
        renameTarget = list
        nameDialogIsRename = true
        showingNameDialog = true
    }

    private func finishCreate(named submitted: String) async {
        let saved = await viewModel.createList(named: submitted)
        guard !saved, viewModel.nameError != nil else {
            if saved { dialogName = "" }
            return
        }
        nameDialogIsRename = false
        try? await Task.sleep(for: .milliseconds(350))
        showingNameDialog = true
    }

    private func finishRename(_ list: LibraryList, to submitted: String) async {
        let saved = await viewModel.rename(list, to: submitted)
        guard !saved, viewModel.nameError != nil else {
            if saved {
                renameTarget = nil
                nameDialogIsRename = false
            }
            return
        }
        renameTarget = list
        nameDialogIsRename = true
        try? await Task.sleep(for: .milliseconds(350))
        showingNameDialog = true
    }
}
