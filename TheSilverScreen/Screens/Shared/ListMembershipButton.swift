//
//  ListMembershipButton.swift
//  TheSilverScreen
//
//  Adds or removes the title on screen. Plus when it is on no list, a check
//  when it is on any list in its segment. The menu closes when a row is chosen.
//

import SwiftUI

struct ListMembershipButton: View {
    let draft: ListItemDraft
    let lists: ListsRepository
    let index: ListsIndex
    var onFailure: () -> Void = {}

    @Environment(ListChangeNotice.self) private var notice
    @State private var showingNewList = false
    @State private var newListName = ""
    @State private var nameError: String?

    private var segmentLists: [LibraryList] {
        index.lists(in: draft.kind.segment)
    }

    private var isListed: Bool {
        index.contains(draft.itemKey)
    }

    var body: some View {
        Menu {
            ForEach(segmentLists) { list in
                let saved = index.contains(draft.itemKey, listID: list.id)
                Button {
                    Task { await toggle(list) }
                } label: {
                    if saved {
                        Label(list.name, systemImage: "checkmark")
                    } else {
                        Text(list.name)
                    }
                }
                .accessibilityLabel(saved ? "Remove from \(list.name)" : "Add to \(list.name)")
            }
            Divider()
            Button("New list") {
                nameError = nil
                newListName = ""
                showingNewList = true
            }
        } label: {
            glyph
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(isListed ? "\(draft.title), on a list" : "Add \(draft.title) to a list")
        .accessibilityValue(isListed ? "On a list" : "Not on a list")
        .listNamePrompt(
            confirmTitle: "Add to List",
            name: $newListName,
            errorMessage: nameError,
            isPresented: $showingNewList
        ) { submitted in
            Task { await create(named: submitted) }
        }
    }

    private var glyph: some View {
        ZStack {
            Circle()
                .fill(Color.black.opacity(0.45))
                .frame(width: 36, height: 36)
            Image(systemName: isListed ? "checkmark" : "plus")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(isListed ? DesignTheme.accent : Color.white)
        }
        .frame(width: 44, height: 44)
        .contentShape(Rectangle())
        .accessibilityHidden(true)
    }

    private func toggle(_ list: LibraryList) async {
        do {
            let change = try await lists.toggle(draft: draft, listID: list.id)
            notice.show(change, using: lists)
        } catch is CancellationError {
            return
        } catch {
            onFailure()
        }
    }

    private func create(named raw: String) async {
        do {
            let created = try await lists.createList(
                name: raw,
                segment: draft.kind.segment,
                adding: draft
            )
            newListName = ""
            nameError = nil
            if let change = created.change {
                notice.show(change, using: lists)
            }
        } catch let error as ListEditError where error.isNameRejection {
            nameError = error.message
            newListName = raw
            await reopenPrompt()
        } catch is CancellationError {
            return
        } catch {
            onFailure()
        }
    }

    /// The alert dismisses itself before the name check finishes, so a rejection presents it again.
    private func reopenPrompt() async {
        showingNewList = false
        try? await Task.sleep(for: .milliseconds(350))
        showingNewList = true
    }
}

extension View {
    /// Centered name alert. `confirmTitle` is "Add to List" from a title and "Create" from the library.
    func listNamePrompt(
        title: String = "New List",
        confirmTitle: String,
        name: Binding<String>,
        errorMessage: String?,
        isPresented: Binding<Bool>,
        onConfirm: @escaping (String) -> Void
    ) -> some View {
        alert(title, isPresented: isPresented) {
            TextField("Name", text: name)
            Button("Cancel", role: .cancel) {}
            Button(confirmTitle) {
                onConfirm(name.wrappedValue)
            }
        } message: {
            Text(errorMessage ?? "Name this list.")
        }
    }
}
