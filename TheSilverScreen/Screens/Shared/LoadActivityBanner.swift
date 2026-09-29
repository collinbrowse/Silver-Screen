//
//  LoadActivityBanner.swift
//  TheSilverScreen
//
//  Inline failure while a list that already has content stays on screen.
//

import SwiftUI

struct LoadActivityBanner: View {
    let activity: LoadActivity

    var body: some View {
        if case .failed(let error) = activity {
            Text("\(error.title): \(error.message)")
                .font(DesignTypography.chip)
                .foregroundStyle(.white)
                .padding(DesignSpacing.sm)
                .frame(maxWidth: .infinity)
                .background(Color.red)
                .accessibilityLabel("\(error.title). \(error.message)")
        }
    }
}
