//
//  OnboardingStarRating.swift
//  SilverScreen
//
//  Inline stars under a picked poster. Five stars span the 0.5–10 scale, so
//  each half point is a tenth of a star's width. Tap or drag sideways to
//  choose; the score saves when the finger lifts.
//

import SwiftUI

struct OnboardingStarRating: View {
    let title: String
    let score: Double?
    let onChange: (Double?) -> Void

    /// The score under the finger while dragging, before it is saved.
    @State private var dragScore: Double?
    /// Width of the star row, which spans the cell so a touch maps straight to a score.
    @State private var width: CGFloat = 0

    private var shown: Double? { dragScore ?? score }

    var body: some View {
        VStack(spacing: 0) {
            stars
                .padding(.vertical, 11)
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
                .onTapGesture(coordinateSpace: .local) { location in
                    onChange(Self.score(at: location.x, width: width))
                }
                // Simultaneous so a vertical swipe still scrolls the grid.
                .simultaneousGesture(
                    DragGesture(minimumDistance: 10)
                        .onChanged { value in
                            guard abs(value.translation.width) > abs(value.translation.height) else { return }
                            dragScore = Self.score(at: value.location.x, width: width)
                        }
                        .onEnded { _ in
                            guard let chosen = dragScore else { return }
                            dragScore = nil
                            onChange(chosen)
                        }
                )

            HStack(spacing: DesignSpacing.xs) {
                Text(shown.map { String(format: "%.1f", $0) } ?? "Rate it")
                    .font(DesignTypography.chip)
                    .monospacedDigit()
                    .foregroundStyle(shown == nil ? DesignTheme.textSecondary : DesignTheme.textPrimary)
                if score != nil {
                    Button {
                        onChange(nil)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(DesignTheme.textMuted)
                            .frame(minWidth: 44, minHeight: 32)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.borderless)
                    .accessibilityHidden(true)
                }
            }
            .frame(minHeight: 32)
            .accessibilityHidden(true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Your rating for \(title)")
        .accessibilityValue(score.map { String(format: "%.1f out of 10", $0) } ?? "Not rated")
        .accessibilityHint("Swipe up or down to change by half a point.")
        .accessibilityAdjustableAction { direction in
            switch direction {
                case .increment:
                    onChange(min((score ?? 0) + 0.5, 10))
                case .decrement:
                    guard let score else { return }
                    onChange(score <= 0.5 ? nil : score - 0.5)
                @unknown default:
                    break
            }
        }
        .accessibilityAction(named: "Remove rating") {
            onChange(nil)
        }
    }

    private var stars: some View {
        let fraction = (shown ?? 0) / 10
        return HStack(spacing: 2) {
            ForEach(0..<5, id: \.self) { _ in
                Image(systemName: "star")
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity)
            }
        }
        .foregroundStyle(DesignTheme.textMuted)
        .overlay {
            HStack(spacing: 2) {
                ForEach(0..<5, id: \.self) { _ in
                    Image(systemName: "star.fill")
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity)
                }
            }
            .foregroundStyle(DesignTheme.accent)
            .mask(alignment: .leading) {
                GeometryReader { proxy in
                    Rectangle().frame(width: proxy.size.width * fraction)
                }
            }
        }
        .frame(height: 22)
    }

    /// Maps a touch to the half point under it, clamped to 0.5–10.
    static func score(at x: CGFloat, width: CGFloat) -> Double {
        guard width > 0 else { return 0.5 }
        let fraction = min(max(Double(x / width), 0), 1)
        let halfPoints = max((fraction * 20).rounded(.up), 1)
        return halfPoints / 2
    }
}
