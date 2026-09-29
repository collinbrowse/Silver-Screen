//
//  FittingSegmentedControl.swift
//  TheSilverScreen
//
//  Segmented control that keeps the words while they fit, and switches to icons when they do not.
//

import SwiftUI

struct FittingSegmentedControl<Option: Hashable>: View {
    let title: String
    let options: [Option]
    @Binding var selection: Option
    let label: (Option) -> String
    let symbol: (Option) -> String

    var body: some View {
        ViewThatFits(in: .horizontal) {
            picker(useIcons: false)
                .fixedSize(horizontal: true, vertical: false)
            picker(useIcons: true)
        }
        .frame(maxWidth: .infinity)
    }

    private func picker(useIcons: Bool) -> some View {
        Picker(title, selection: $selection) {
            ForEach(options, id: \.self) { option in
                if useIcons {
                    Image(systemName: symbol(option))
                        .accessibilityLabel(label(option))
                        .tag(option)
                } else {
                    Text(label(option))
                        .tag(option)
                }
            }
        }
        .pickerStyle(.segmented)
        .accessibilityLabel(title)
    }
}
