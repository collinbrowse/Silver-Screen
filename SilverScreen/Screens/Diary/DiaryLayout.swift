//
//  DiaryLayout.swift
//  SilverScreen
//
//  Diary sizing from the width the screen actually has, not the device model, so the
//  same views serve iPhone, a split iPad window, and full-screen iPad.
//

import CoreGraphics

/// Row and margin sizes for a given available width.
struct DiaryLayout: Equatable {
    /// Widest the text column gets; wider screens center it with side margins.
    static let readableWidth: CGFloat = 720
    /// At or above this width the rows get larger posters and longer review excerpts.
    static let regularThreshold: CGFloat = 600

    let horizontalMargin: CGFloat
    let posterWidth: CGFloat
    let reviewLineLimit: Int
    let isRegular: Bool

    init(width: CGFloat) {
        isRegular = width >= Self.regularThreshold
        horizontalMargin = max(0, (width - Self.readableWidth) / 2)
        posterWidth = isRegular ? 56 : 40
        reviewLineLimit = isRegular ? 3 : 2
    }
}
