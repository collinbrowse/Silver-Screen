//
//  WindowTopInsetReader.swift
//  SilverScreen
//
//  Reports the window top inset, which is the band behind the clock and status icons.
//

import SwiftUI
import UIKit

struct WindowTopInsetReader: UIViewRepresentable {
    let onChange: (CGFloat) -> Void

    func makeUIView(context: Context) -> ProbeView {
        let view = ProbeView()
        view.onChange = onChange
        return view
    }

    func updateUIView(_ uiView: ProbeView, context: Context) {
        uiView.onChange = onChange
        uiView.report()
    }

    final class ProbeView: UIView {
        var onChange: ((CGFloat) -> Void)?
        /// The last inset passed on, so a re-render with the same inset stays quiet.
        private var lastReported: CGFloat?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            report()
        }

        override func safeAreaInsetsDidChange() {
            super.safeAreaInsetsDidChange()
            report()
        }

        func report() {
            report(top: window?.safeAreaInsets.top ?? 0)
        }

        /// Delivers a changed inset after the current pass. `updateUIView` runs inside a
        /// SwiftUI view update, and the owner writes `@State` from `onChange`, so calling
        /// it directly is "Modifying state during view update".
        func report(top: CGFloat) {
            guard top > 0, top != lastReported else { return }
            lastReported = top
            Task { @MainActor [weak self] in
                self?.onChange?(top)
            }
        }
    }
}
