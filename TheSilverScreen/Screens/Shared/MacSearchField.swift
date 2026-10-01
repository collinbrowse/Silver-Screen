//
//  MacSearchField.swift
//  TheSilverScreen
//
//  Search field for this iOS app when it runs on Mac. The system search bar
//  lays out through UIScreen focus, which UIKit rejects and terminates the
//  process ("Accessing the focus system through UIScreen is no longer supported").
//

import SwiftUI

/// Text field that stands in for `.searchable` on Mac.
struct MacSearchField: View {
    @Binding var text: String
    var prompt: String
    /// Mirrors keyboard focus when the screen needs to dismiss the field itself.
    var isFocused: Binding<Bool>?

    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: DesignSpacing.sm) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(DesignTheme.textSecondary)
                .accessibilityHidden(true)
            TextField(prompt, text: $text)
                .focused($focused)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .font(DesignTypography.body)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(DesignTheme.textSecondary)
                }
                .buttonStyle(.plain)
                .frame(minWidth: 44, minHeight: 44)
                .accessibilityLabel("Clear search")
            }
        }
        // The clear control is 44pt and only appears with text. Reserve that
        // height up front so the bar does not grow on the first character.
        .frame(minHeight: 44)
        .padding(.leading, DesignSpacing.md)
        .padding(.trailing, text.isEmpty ? DesignSpacing.md : 0)
        .background(DesignTheme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.horizontal, DesignSpacing.lg)
        .padding(.vertical, DesignSpacing.sm)
        .background(DesignTheme.canvas)
        .onAppear {
            if let isFocused {
                focused = isFocused.wrappedValue
            }
        }
        .onChange(of: focused) { _, newValue in
            guard let isFocused, isFocused.wrappedValue != newValue else { return }
            isFocused.wrappedValue = newValue
        }
        .onChange(of: isFocused?.wrappedValue) { _, newValue in
            guard let newValue, focused != newValue else { return }
            focused = newValue
        }
    }
}

extension View {
    /// Search field under the navigation title.
    ///
    /// On Mac this is a text field. The system search bar asks `UIScreen` for
    /// focus bounds, which UIKit rejects and terminates the process.
    @ViewBuilder
    func navigationSearch(text: Binding<String>, prompt: String) -> some View {
        navigationSearch(text: text, prompt: prompt, isFocused: nil)
    }

    @ViewBuilder
    func navigationSearch(
        text: Binding<String>,
        prompt: String,
        isFocused: Binding<Bool>?
    ) -> some View {
        if ProcessInfo.processInfo.isiOSAppOnMac {
            safeAreaInset(edge: .top, spacing: 0) {
                MacSearchField(text: text, prompt: prompt, isFocused: isFocused)
            }
        } else {
            searchable(
                text: text,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: prompt
            )
        }
    }
}
