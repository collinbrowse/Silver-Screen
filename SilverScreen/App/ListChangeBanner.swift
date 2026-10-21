//
//  ListChangeBanner.swift
//  SilverScreen
//

import SwiftUI

/// Confirmation after adding or removing a title. Undo sits just above the bottom
/// chrome; see `ListChangeBannerHost`.
/// Watched / In Progress adds without a score also offer Add rating, which opens
/// the combined rating and note sheet.
struct ListChangeBanner: View {
    @Bindable var notice: ListChangeNotice

    var body: some View {
        if let message = notice.message {
            HStack(spacing: DesignSpacing.md) {
                Text(message)
                    .font(DesignTypography.metadata)
                    .foregroundStyle(DesignTheme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: DesignSpacing.sm)
                if notice.ratingKey != nil, notice.annotationEditor == nil {
                    Button {
                        Task { await notice.openRatingEditor() }
                    } label: {
                        Text("Add rating")
                            .font(DesignTypography.metadata.weight(.semibold))
                            .foregroundStyle(DesignTheme.accent)
                            .frame(minHeight: 44)
                    }
                    .accessibilityLabel("Add rating")
                }
                if notice.canUndo {
                    Button("Undo") {
                        Task { await notice.undo() }
                    }
                    .font(DesignTypography.metadata.weight(.semibold))
                    .frame(minHeight: 44)
                }
            }
            .padding(.horizontal, DesignSpacing.lg)
            .padding(.vertical, DesignSpacing.sm)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: DesignRadius.card, style: .continuous))
            .readableColumn()
            .padding(.horizontal, DesignSpacing.lg)
            .padding(.bottom, DesignSpacing.sm)
            .accessibilityElement(children: .contain)
        }
    }
}

/// Shows the banner at the bottom of one tab's content. That content's safe area
/// already ends above the tab bar when the bar is at the bottom (iPhone), and at the
/// home indicator when the tabs are a sidebar or side bar (iPad, iPhone Duo), so the
/// banner sits just above whichever is there instead of a fixed tab-bar height.
struct ListChangeBannerHost: ViewModifier {
    let notice: ListChangeNotice
    /// Read by the caller's `body`, so the host updates when only the notice changes.
    let isShowing: Bool

    func body(content: Content) -> some View {
        content.overlay(alignment: .bottom) {
            if isShowing {
                ListChangeBanner(notice: notice)
                    .id(notice.presentationID)
            }
        }
    }
}
