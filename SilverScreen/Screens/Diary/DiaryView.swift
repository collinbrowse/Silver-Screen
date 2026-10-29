//
//  DiaryView.swift
//  SilverScreen
//
//  Every logged watch and TV episode check-off, grouped by month, newest first. Tapping
//  a logged watch edits it; swipe or the context menu deletes it or opens the title.
//  An episodes row opens its show, where episodes are marked and unmarked. The column is centered at a
//  readable width when the screen is wide (see `DiaryLayout`).
//

import SwiftUI

struct DiaryView: View {
    @State var viewModel: DiaryViewModel
    let imageLoader: ImageLoader
    let router: NavigationRouter

    @State private var availableWidth: CGFloat = 0

    private var layout: DiaryLayout { DiaryLayout(width: availableWidth) }

    private var editorBinding: Binding<DiaryEditorSession?> {
        Binding(
            get: { viewModel.editor },
            set: { newValue in
                if newValue == nil {
                    viewModel.dismissEditor()
                }
            }
        )
    }

    var body: some View {
        Group {
            switch viewModel.state {
                case .idle, .loading:
                    LoadingStateView()
                case .empty:
                    if viewModel.scope == nil {
                        EmptyStateView(
                            title: "No Diary Entries",
                            message: "Log a watch from any movie or show, or check off an episode, and it shows up here by the day you watched it.",
                            systemImage: "book.closed"
                        )
                    } else {
                        EmptyStateView(
                            title: "No Watches Yet",
                            message: "Watches you log for this title show up here.",
                            systemImage: "book.closed"
                        )
                    }
                case .loaded(let months, let activity):
                    list(months)
                        .overlay(alignment: .top) {
                            LoadActivityBanner(activity: activity)
                        }
                case .failed(let error):
                    ErrorStateView(error: error) {
                        await viewModel.load()
                    }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DesignTheme.canvas)
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width
        } action: { width in
            availableWidth = width
        }
        .navigationTitle(viewModel.navigationTitle)
        // Inline when the column is centered on a wide screen: a large title stays at the
        // leading edge and no longer lines up with the rows.
        .toolbarTitleDisplayMode(
            viewModel.prefersInlineTitle || layout.horizontalMargin > 0 ? .inline : .inlineLarge
        )
        .sheet(item: editorBinding) { session in
            DiaryEntryEditorSheet(
                session: session,
                onSave: { await viewModel.save($0) },
                onDelete: { await viewModel.deleteEditorEntry() }
            )
        }
        .task {
            await viewModel.load()
        }
        .onChange(of: viewModel.contextRevision) { _, _ in
            Task { await viewModel.load() }
        }
    }

    private func list(_ months: [DiaryMonth]) -> some View {
        List {
            ForEach(months) { month in
                Section {
                    ForEach(month.items) { item in
                        switch item {
                            case .entry(let row):
                                Button {
                                    viewModel.edit(row)
                                } label: {
                                    DiaryEntryRow(
                                        row: row,
                                        layout: layout,
                                        imageLoader: imageLoader,
                                        showsTitle: viewModel.showsRowTitles
                                    )
                                }
                                .buttonStyle(.plain)
                                .accessibilityHint("Edits this entry")
                                .accessibilityAction(named: "Delete") {
                                    Task { await viewModel.delete(row) }
                                }
                                .accessibilityActions {
                                    if viewModel.showsTitleLinks {
                                        Button("Open title") {
                                            router.push(viewModel.route(for: row))
                                        }
                                    }
                                }
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button("Delete", role: .destructive) {
                                        Task { await viewModel.delete(row) }
                                    }
                                }
                                .contextMenu {
                                    Button("Edit Entry", systemImage: "pencil") {
                                        viewModel.edit(row)
                                    }
                                    if viewModel.showsTitleLinks {
                                        Button(
                                            row.entry.subject.kind == .tv ? "Go to Show" : "Go to Movie",
                                            systemImage: row.entry.subject.kind == .tv ? "tv" : "film"
                                        ) {
                                            router.push(viewModel.route(for: row))
                                        }
                                    }
                                    Button("Delete", systemImage: "trash", role: .destructive) {
                                        Task { await viewModel.delete(row) }
                                    }
                                }
                            case .episodes(let group):
                                if viewModel.showsTitleLinks {
                                    Button {
                                        router.push(viewModel.route(for: group))
                                    } label: {
                                        DiaryEpisodeGroupRow(group: group, layout: layout, imageLoader: imageLoader)
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityHint("Opens the show")
                                    .contextMenu {
                                        Button("Go to Show", systemImage: "tv") {
                                            router.push(viewModel.route(for: group))
                                        }
                                    }
                                } else {
                                    DiaryEpisodeGroupRow(
                                        group: group,
                                        layout: layout,
                                        imageLoader: imageLoader,
                                        showsTitle: viewModel.showsRowTitles
                                    )
                                }
                        }
                    }
                } header: {
                    Text(month.title)
                        .font(DesignTypography.section)
                        .foregroundStyle(DesignTheme.textPrimary)
                        .accessibilityAddTraits(.isHeader)
                }
            }
        }
        .listStyle(.plain)
        .contentMargins(.horizontal, layout.horizontalMargin, for: .scrollContent)
    }
}
