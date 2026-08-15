import SwiftUI

/// The centered numeric timer readout on Track (Design/COMPONENTS.md,
/// `NumericTimerReadout`). Its only purpose is displaying the exact elapsed
/// duration; it has no dial, ring, sweep, goal, daily-total, or decorative
/// progress visualization. The saved-state checkmark lives in TrackContent's
/// reserved completion region above the readout (refine-track-recents D1),
/// not as an overlay here.
///
/// D10: the state caption region reserves the height of the tallest caption
/// presentation — the idle prompt wraps at larger accessibility sizes while
/// Ready/Running/Saving/Saved stay one line — so the top flow height is
/// state-invariant and the main action below never moves.
struct NumericTimerReadout: View {
    let state: TrackState
    let elapsed: TimeInterval

    @State private var slotWidth: CGFloat = 0
    @State private var naturalCaptionSlotHeight: CGFloat = 0

    var body: some View {
        VStack(spacing: Theme.spacingSmall) {
            Text(TimeFormatter.formattedDuration(elapsed))
                .font(Theme.timerFont())
                .foregroundStyle(Theme.textPrimary)
                .monospacedDigit()
                .frame(minWidth: 220, idealWidth: 260, maxWidth: .infinity)

            Text(caption)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.textSecondary)
                .frame(minHeight: captionSlotHeight, alignment: .top)
        }
        .background(
            GeometryReader { geometry in
                Color.clear.preference(
                    key: TimerReadoutWidthKey.self,
                    value: geometry.size.width
                )
            }
        )
        .overlay(captionHeightProbe, alignment: .topLeading)
        .onPreferenceChange(TimerReadoutWidthKey.self) { slotWidth = $0 }
        .onPreferenceChange(TimerCaptionNaturalHeightKey.self) { naturalCaptionSlotHeight = $0 }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(state.readoutAccessibilityLabel)
        .accessibilityValue(TimeFormatter.formattedDuration(elapsed))
        .accessibilityIdentifier("TimerDisplay")
        .accessibilityAddTraits(state.isRunning ? .updatesFrequently : [])
    }

    /// D10: the state caption region reserves the height of the tallest
    /// caption presentation. The probe renders every caption at the
    /// readout's measured width with the real SwiftUI Text metrics and
    /// reports the tallest natural height, so the reservation matches the
    /// rendered line height exactly at any Dynamic Type size or locale.
    private var captionHeightProbe: some View {
        let probeWidth = slotWidth > 0
            ? slotWidth
            : Theme.maxContentWidth - Theme.screenHorizontalPadding * 2
        return ZStack(alignment: .topLeading) {
            ForEach(Self.captionTexts, id: \.self) { title in
                Text(title)
                    .font(.caption.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(width: probeWidth, alignment: .topLeading)
        .hidden()
        .background(
            GeometryReader { geometry in
                Color.clear.preference(
                    key: TimerCaptionNaturalHeightKey.self,
                    value: geometry.size.height
                )
            }
        )
    }

    private var captionSlotHeight: CGFloat {
        max(0, naturalCaptionSlotHeight)
    }

    private static var captionTexts: [String] {
        [
            L10n.timerChooseActivityPrompt.text,
            L10n.timerReady.text,
            L10n.timerRunning.text,
            L10n.timerSaving.text,
            L10n.timerSaved.text
        ]
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

private struct TimerReadoutWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct TimerCaptionNaturalHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
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
