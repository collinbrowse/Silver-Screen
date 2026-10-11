//
//  MediaDescriptionSection.swift
//  TheSilverScreen
//
//  TMDB overview and the viewer's review for one title. A saved note is the page
//  that shows first. Headers sit outside the surface card; the review body matches
//  the Reviews card (name, date, text, Show More). The card opens the editor.
//

import SwiftUI

struct MediaDescriptionSection: View {
    let overview: String
    let note: String?
    /// Day the note was first saved.
    var notedOn: String? = nil
    let onEdit: () -> Void
    /// Keeps the note card on screen when collapsing a long note that started above the fold.
    var scrollTo: (String) -> Void = { _ in }

    @State private var page: Page

    private static let noteCardID = "user-note"

    init(
        overview: String,
        note: String?,
        notedOn: String? = nil,
        onEdit: @escaping () -> Void,
        scrollTo: @escaping (String) -> Void = { _ in }
    ) {
        self.overview = overview
        self.note = note
        self.notedOn = notedOn
        self.onEdit = onEdit
        self.scrollTo = scrollTo
        _page = State(initialValue: note == nil ? .description : .notes)
    }

    private enum Page {
        case notes
        case description
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSpacing.sm) {
            header
            SurfaceCard {
                cardBody
            }
            .id(Self.noteCardID)
            .animation(.smooth(duration: 0.35), value: page)
        }
        .onAppear(perform: resetPage)
        .onChange(of: note) { _, _ in
            resetPage()
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: DesignSpacing.sm) {
            if note == nil {
                sectionTitle("Storyline")
                Spacer(minLength: 0)
            } else if page == .notes {
                sectionTitle("Your review")
                Spacer(minLength: 0)
                pageSwitch(title: "Storyline", arrow: "arrow.right", arrowFirst: false, label: "Show storyline") {
                    showStoryline()
                }
            } else {
                sectionTitle("Storyline")
                Spacer(minLength: 0)
                pageSwitch(title: "Your review", arrow: "arrow.left", arrowFirst: true, label: "Show your review") {
                    showNotes()
                }
            }
        }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(DesignTypography.section)
            .foregroundStyle(DesignTheme.textPrimary)
            .accessibilityAddTraits(.isHeader)
    }

    private func pageSwitch(
        title: String,
        arrow: String,
        arrowFirst: Bool,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: DesignSpacing.xs) {
                if arrowFirst {
                    Image(systemName: arrow)
                        .accessibilityHidden(true)
                }
                Text(title)
                if !arrowFirst {
                    Image(systemName: arrow)
                        .accessibilityHidden(true)
                }
            }
            .font(DesignTypography.metadata.weight(.semibold))
            .foregroundStyle(DesignTheme.accent)
            .frame(minHeight: 44)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    @ViewBuilder
    private var cardBody: some View {
        if page == .notes, let note {
            noteCard(note)
        } else {
            storylineCard
        }
    }

    private func noteCard(_ note: String) -> some View {
        VStack(alignment: .leading, spacing: DesignSpacing.sm) {
            Button(action: onEdit) {
                VStack(alignment: .leading, spacing: DesignSpacing.sm) {
                    HStack(alignment: .firstTextBaseline, spacing: DesignSpacing.sm) {
                        // No account yet — local reviews are attributed to the person using the device.
                        Text("You")
                            .font(DesignTypography.metadata.weight(.bold))
                            .foregroundStyle(DesignTheme.textPrimary)
                        Spacer(minLength: DesignSpacing.sm)
                        Image(systemName: "pencil")
                            .font(DesignTypography.metadata.weight(.semibold))
                            .foregroundStyle(DesignTheme.textSecondary)
                            .accessibilityHidden(true)
                    }
                    if let notedOn {
                        Text(notedOn)
                            .font(DesignTypography.chip)
                            .foregroundStyle(DesignTheme.textSecondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Edit rating and note. \(noteAccessibilityLabel(note))")

            // Outside the edit button so Show More does not open the editor.
            ExpandableTextToggle(
                text: note,
                scrollTo: scrollTo,
                scrollID: Self.noteCardID,
                onTextTap: onEdit
            )
        }
    }

    private var storylineCard: some View {
        Text(overview.isEmpty ? "No description available." : overview)
            .font(DesignTypography.body)
            .foregroundStyle(DesignTheme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .textSelection(.enabled)
            .accessibilityLabel(
                overview.isEmpty ? "Storyline. No description available." : "Storyline. \(overview)"
            )
    }

    private func noteAccessibilityLabel(_ note: String) -> String {
        var parts = ["You"]
        if let notedOn {
            parts.append(notedOn)
        }
        parts.append(note)
        return parts.joined(separator: ". ")
    }

    private func showStoryline() {
        withAnimation(.smooth(duration: 0.35)) {
            page = .description
        }
    }

    private func showNotes() {
        withAnimation(.smooth(duration: 0.35)) {
            page = .notes
        }
    }

    private func resetPage() {
        page = note == nil ? .description : .notes
    }
}
