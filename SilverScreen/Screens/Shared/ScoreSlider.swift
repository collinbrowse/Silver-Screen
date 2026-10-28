//
//  ScoreSlider.swift
//  SilverScreen
//
//  The 0.5–10 rating slider with its "Rate out of 10" header, shared by the title
//  rating sheet and the diary's log-a-watch sheet so both pick a score the same way.
//

import SwiftUI

/// Half-step rating slider. `score` stays nil until the person moves the thumb, so an
/// untouched slider never reads as a chosen rating.
struct ScoreSlider: View {
    @Binding var score: Double?
    var isDisabled = false
    /// Runs on every drag step, e.g. to drop keyboard focus from a note field.
    var onAdjust: () -> Void = {}

    /// Thumb position. It starts mid-scale when there is no score yet.
    @State private var sliderValue: Double

    init(score: Binding<Double?>, isDisabled: Bool = false, onAdjust: @escaping () -> Void = {}) {
        _score = score
        self.isDisabled = isDisabled
        self.onAdjust = onAdjust
        _sliderValue = State(initialValue: score.wrappedValue.map(UserScore.snapped) ?? 5.5)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSpacing.sm) {
            HStack(alignment: .firstTextBaseline) {
                Text("Rate out of 10")
                    .font(DesignTypography.metadata)
                    .foregroundStyle(DesignTheme.textSecondary)
                Spacer(minLength: DesignSpacing.sm)
                if let score {
                    Text(UserScore.formatted(score))
                        .font(DesignTypography.ratingValue)
                        .foregroundStyle(DesignTheme.accent)
                        .accessibilityLabel(UserScore.accessibilityLabel(score))
                } else {
                    Text("-")
                        .font(DesignTypography.ratingValue)
                        .foregroundStyle(DesignTheme.accent)
                        .accessibilityLabel("Choose a rating")
                }
            }

            Slider(
                value: Binding(
                    get: { sliderValue },
                    set: { newValue in
                        sliderValue = newValue
                        score = UserScore.snapped(newValue)
                        onAdjust()
                    }
                ),
                in: 0.5...10,
                step: 0.5
            )
            .tint(DesignTheme.accent)
            .disabled(isDisabled)
            .accessibilityLabel("Your rating")
            .accessibilityValue(score.map(UserScore.formatted) ?? "No rating chosen")
        }
        .onChange(of: score) { _, newValue in
            // Keep the thumb in step when the owner clears or replaces the score.
            if let newValue {
                sliderValue = newValue
            }
        }
    }
}
