//
//  DiaryView.swift
//  SilverScreen
//
//  Every logged watch, grouped by month, newest first. Tapping a row edits it; swipe
//  or the context menu deletes it or opens the title. The column is centered at a
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
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .empty:
                    EmptyStateView(
                        title: "No Diary Entries",
                        message: "Log a watch from any movie and it shows up here, by the day you watched it.",
                        systemImage: "book.closed"
                    )
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
        .navigationTitle("Diary")
        .toolbarTitleDisplayMode(.inlineLarge)
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
                    ForEach(month.rows) { row in
                        Button {
                            viewModel.edit(row)
                        } label: {
                            DiaryEntryRow(row: row, layout: layout, imageLoader: imageLoader)
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Edits this entry")
                        .accessibilityAction(named: "Open title") {
                            router.push(viewModel.route(for: row))
                        }
                        .accessibilityAction(named: "Delete") {
                            Task { await viewModel.delete(row) }
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
                            Button(
                                row.entry.subject.kind == .tv ? "Go to Show" : "Go to Movie",
                                systemImage: row.entry.subject.kind == .tv ? "tv" : "film"
                            ) {
                                router.push(viewModel.route(for: row))
                            }
                            Button("Delete", systemImage: "trash", role: .destructive) {
                                Task { await viewModel.delete(row) }
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
