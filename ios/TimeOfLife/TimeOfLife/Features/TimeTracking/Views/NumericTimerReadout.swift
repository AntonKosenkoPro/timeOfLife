import SwiftUI

/// The centered numeric timer readout on Track (Design/COMPONENTS.md,
/// `NumericTimerReadout`). Its only purpose is displaying the exact elapsed
/// duration; it has no dial, ring, sweep, goal, daily-total, or decorative
/// progress visualization.
struct NumericTimerReadout: View {
    let state: TrackState
    let elapsed: TimeInterval

    var body: some View {
        VStack(spacing: Theme.spacingSmall) {
            if case .saved = state {
                Image(systemName: "checkmark")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(Theme.accentPrimary)
            }

            Text(TimeFormatter.formattedDuration(elapsed))
                .font(Theme.timerFont())
                .foregroundStyle(Theme.textPrimary)
                .monospacedDigit()
                .frame(minWidth: 220, idealWidth: 260, maxWidth: .infinity)

            Text(caption)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.textSecondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(state.readoutAccessibilityLabel)
        .accessibilityValue(TimeFormatter.formattedDuration(elapsed))
        .accessibilityIdentifier("TimerDisplay")
        .accessibilityAddTraits(state.isRunning ? .updatesFrequently : [])
    }

    private var caption: String {
        switch state {
        case .idle: L10n.timerChooseActivityPrompt.text
        case .ready: L10n.timerReady.text
        case .running: L10n.timerRunning.text
        case .saving: L10n.timerSaving.text
        case .saved: L10n.timerSaved.text
        case .error: L10n.timerRunning.text
        }
    }
}

#if DEBUG
#Preview("Numeric Timer — Ready") {
    NumericTimerReadout(state: .idle, elapsed: 0)
        .background(Theme.backgroundPrimary)
}

#Preview("Numeric Timer — Running") {
    NumericTimerReadout(state: .running(
        Activity(id: "a", name: "Deep work"),
        startedAt: Date().addingTimeInterval(-125)
    ), elapsed: 125)
    .background(Theme.backgroundPrimary)
}
#endif
