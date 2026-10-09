//
//  ListChangeBanner.swift
//  TheSilverScreen
//

import SwiftUI

/// Confirmation after adding or removing a title. Undo sits above the tab bar.
/// Watched / In Progress adds without a score also offer Add rating.
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
                if notice.ratingKey != nil {
                    Menu {
                        ForEach(UserScore.options, id: \.self) { value in
                            Button(UserScore.formatted(value)) {
                                Task { await notice.saveRating(value) }
                            }
                            .accessibilityLabel(UserScore.accessibilityLabel(value))
                        }
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
            .padding(.horizontal, DesignSpacing.lg)
            .padding(.bottom, 56)
            .accessibilityElement(children: .contain)
        }
    }
}
