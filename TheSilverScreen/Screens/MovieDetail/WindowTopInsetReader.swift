//
//  WindowTopInsetReader.swift
//  TheSilverScreen
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

        override func didMoveToWindow() {
            super.didMoveToWindow()
            report()
        }

        override func safeAreaInsetsDidChange() {
            super.safeAreaInsetsDidChange()
            report()
        }

        func report() {
            let top = window?.safeAreaInsets.top ?? 0
            guard top > 0 else { return }
            onChange?(top)
        }
    }
}
