//
//  TourOverlay.swift
//  SilverScreen
//
//  The tour's dim layer over the whole app, with a rounded cutout around the
//  highlighted view and a tooltip card above or below it. Touches outside the
//  card are blocked, so the tour drives navigation and nothing changes under it.
//

import SwiftUI

struct TourOverlay: View {
    let tour: TourController

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AccessibilityFocusState private var cardFocused: Bool
    /// The card's measured height, so it can be kept clear of the screen edges.
    @State private var cardHeight: CGFloat = 0

    /// Breathing room between the highlighted view and the cutout's edge.
    private let cutoutPadding: CGFloat = 8
    private let cardGap: CGFloat = 16
    /// Smallest gap kept between the cutout ring and the screen edge.
    private let edgeInset: CGFloat = 4

    /// The outer reader keeps the safe area so its insets are real; the inner one
    /// ignores it to dim the whole screen, and reports zero insets.
    var body: some View {
        GeometryReader { safeArea in
            GeometryReader { proxy in
                layers(in: proxy, insets: safeArea.safeAreaInsets)
            }
            .ignoresSafeArea()
        }
        .animation(reduceMotion ? nil : .spring(duration: 0.4), value: tour.highlight)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: tour.index)
        .accessibilityAddTraits(.isModal)
        .onChange(of: tour.index, initial: true) {
            cardFocused = true
        }
    }

    /// The scrim, the ring, and the card, laid out in full-screen coordinates.
    @ViewBuilder
    private func layers(in proxy: GeometryProxy, insets: EdgeInsets) -> some View {
        let container = proxy.frame(in: .global)
        // Full-width targets would push the padded ring past the screen edge, so the
        // cutout is clamped just inside the container.
        let bounds = CGRect(origin: .zero, size: container.size).insetBy(dx: edgeInset, dy: edgeInset)
        let cutout = tour.highlight.map { frame in
            frame
                .offsetBy(dx: -container.minX, dy: -container.minY)
                .insetBy(dx: -cutoutPadding, dy: -cutoutPadding)
                .intersection(bounds)
        }
        ZStack {
            TourScrim(cutout: cutout ?? .zero)
                .fill(Color.black.opacity(0.72), style: FillStyle(eoFill: true))
                .contentShape(Rectangle())
                .onTapGesture {}
                .accessibilityHidden(true)

            if let cutout {
                RoundedRectangle(cornerRadius: TourScrim.cornerRadius, style: .continuous)
                    .strokeBorder(DesignTheme.accent, lineWidth: 2)
                    .frame(width: cutout.width, height: cutout.height)
                    .position(x: cutout.midX, y: cutout.midY)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }

            cardLayer(cutout: cutout, height: container.height, insets: insets)
        }
    }

    /// Puts the card under a highlight in the top half and over one in the bottom half.
    /// With nothing highlighted yet (still loading), the card sits in the middle. A
    /// highlight too tall to leave room pins the card inside the safe area instead, over
    /// the far end of the highlight, so it never runs into the home indicator or bar.
    @ViewBuilder
    private func cardLayer(cutout: CGRect?, height: CGFloat, insets: EdgeInsets) -> some View {
        VStack(spacing: 0) {
            switch Self.cardPlacement(cutout: cutout, height: height, cardHeight: cardHeight, insets: insets, gap: cardGap) {
                case .top(let space):
                    Color.clear.frame(height: space)
                    card
                    Spacer(minLength: 0)
                case .bottom(let space):
                    Spacer(minLength: 0)
                    card
                    Color.clear.frame(height: space)
                case .centered:
                    Spacer(minLength: 0)
                    card
                    Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, DesignSpacing.lg)
    }

    /// Where the card goes: the space above it (`top`) or below it (`bottom`).
    enum CardPlacement: Equatable {
        case top(CGFloat)
        case bottom(CGFloat)
        case centered
    }

    /// Picks the card's spot beside the cutout, falling back to the safe-area edge
    /// when the card would not fit. `cardHeight` is 0 until the card is measured.
    static func cardPlacement(
        cutout: CGRect?,
        height: CGFloat,
        cardHeight: CGFloat,
        insets: EdgeInsets,
        gap: CGFloat
    ) -> CardPlacement {
        guard let cutout else { return .centered }
        if cutout.midY < height / 2 {
            let below = max(cutout.maxY + gap, 0)
            let room = height - insets.bottom - gap - cardHeight
            return below <= room ? .top(below) : .bottom(insets.bottom + gap)
        }
        let above = max(height - cutout.minY + gap, 0)
        let room = height - insets.top - gap - cardHeight
        return above <= room ? .bottom(above) : .top(insets.top + gap)
    }

    @ViewBuilder
    private var card: some View {
        if let stop = tour.current {
            VStack(alignment: .leading, spacing: DesignSpacing.sm) {
                Text(tour.progressText)
                    .font(DesignTypography.chip)
                    .foregroundStyle(DesignTheme.textSecondary)
                    .accessibilityLabel("Tip \(tour.progressText)")
                Text(stop.title)
                    .font(DesignTypography.section)
                    .foregroundStyle(DesignTheme.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityFocused($cardFocused)
                Text(stop.message)
                    .font(DesignTypography.body)
                    .foregroundStyle(DesignTheme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button("Skip tour") {
                        tour.skip()
                    }
                    .frame(minHeight: 44)
                    .foregroundStyle(DesignTheme.textSecondary)
                    Spacer(minLength: DesignSpacing.md)
                    Button {
                        tour.next()
                    } label: {
                        Text(tour.isLastStop ? "Done" : "Next")
                            .font(.headline)
                            .frame(minWidth: 72, minHeight: 36)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(DesignTheme.accent)
                    .foregroundStyle(DesignTheme.accentOnFill)
                }
                .padding(.top, DesignSpacing.xs)
            }
            .padding(DesignSpacing.lg)
            .frame(maxWidth: 420, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: DesignRadius.card, style: .continuous)
                    .fill(DesignTheme.elevated)
            )
            .shadow(color: .black.opacity(0.25), radius: 16, y: 6)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { cardHeight = $0 }
            .accessibilityElement(children: .contain)
            .id(stop)
            .transition(.opacity)
        }
    }
}

/// A full-screen rectangle with a rounded hole. Even-odd fill leaves the hole clear,
/// and the hole's frame animates when the tour moves to the next view.
struct TourScrim: Shape {
    static let cornerRadius: CGFloat = 14

    var cutout: CGRect

    var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, AnimatablePair<CGFloat, CGFloat>> {
        get {
            AnimatablePair(
                AnimatablePair(cutout.origin.x, cutout.origin.y),
                AnimatablePair(cutout.size.width, cutout.size.height)
            )
        }
        set {
            cutout = CGRect(
                x: newValue.first.first,
                y: newValue.first.second,
                width: newValue.second.first,
                height: newValue.second.second
            )
        }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path(rect)
        if cutout.width > 0, cutout.height > 0 {
            path.addRoundedRect(
                in: cutout,
                cornerSize: CGSize(width: Self.cornerRadius, height: Self.cornerRadius),
                style: .continuous
            )
        }
        return path
    }
}
