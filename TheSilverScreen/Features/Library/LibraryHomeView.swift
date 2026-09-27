//
//  LibraryHomeView.swift
//  TheSilverScreen
//
//  Movies & TV and People are separate libraries. Watched and Watchlist stay
//  pinned. Custom lists can be reordered, renamed, and deleted.
//

import SwiftUI

struct LibraryHomeView: View {
    @Bindable var viewModel: LibraryHomeViewModel
    @State private var editMode: EditMode = .inactive
    @State private var showingNameDialog = false
    @State private var nameDialogIsRename = false
    @State private var dialogName = ""
    @State private var renameTarget: LibraryList?

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
        .searchable(
            text: $viewModel.searchText,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Find list"
        )
        .navigationTitle("Library")
        .toolbarTitleDisplayMode(.inlineLarge)
        .toolbar {
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
                List {
                    if !system.isEmpty {
                        Section {
                            ForEach(system) { list in
                                listLink(list)
                            }
                        }
                    }
                    if !custom.isEmpty {
                        Section {
                            ForEach(custom) { list in
                                listLink(list)
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
                                        Button("Rename") { beginRename(list) }
                                        Button("Delete", role: .destructive) {
                                            Task { await viewModel.delete(list) }
                                        }
                                    }
                            }
                            .onMove(perform: viewModel.canReorderLists ? { source, destination in
                                Task { await viewModel.moveLists(from: source, to: destination) }
                            } : nil)
                        }
                    }
                }
                .listStyle(.plain)
                .environment(\.editMode, viewModel.canReorderLists ? $editMode : .constant(.inactive))
            }
        }
    }

    private func listLink(_ list: LibraryList) -> some View {
        NavigationLink(value: Route.libraryList(id: list.id)) {
            VStack(alignment: .leading, spacing: DesignSpacing.xs) {
                Text(list.name)
                    .font(DesignTypography.section)
                    .foregroundStyle(DesignTheme.textPrimary)
                Text(countText(for: list))
                    .font(DesignTypography.metadata)
                    .foregroundStyle(DesignTheme.textSecondary)
            }
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
