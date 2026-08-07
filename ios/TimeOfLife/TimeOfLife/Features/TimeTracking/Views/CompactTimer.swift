import SwiftUI

/// The persistent running-timer surface shown above the tab bar on History
/// and Insights (Design/COMPONENTS.md, `CompactTimer`). Track does not render
/// it — the full numeric readout is already visible there.
struct CompactTimer: View {
    let activityName: String
    let startedAt: Date
    let openTrack: () -> Void
    let stop: () -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            HStack(spacing: Theme.spacingSmall) {
                Button(action: openTrack) {
                    HStack(spacing: Theme.spacingSmall) {
                        Image(systemName: "timer")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Theme.accentPrimary)
                            .frame(width: 38, height: 38)
                            .background(Theme.color(Theme.accentPrimary, alpha: 0.13))
                            .clipShape(Circle())

                        VStack(alignment: .leading, spacing: 2) {
                            Text(activityName)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Theme.textPrimary)
                                .lineLimit(1)
                            Text(TimeFormatter.formattedDuration(context.date.timeIntervalSince(startedAt)))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(Theme.textSecondary)
                        }
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .accessibilityLabel(String(format: L10n.timerCompactRunning.text, activityName))
                .accessibilityHint(L10n.timerCompactReturnHint.text)

                Button(action: stop) {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: Theme.minTapArea, height: Theme.minTapArea)
                        .background(Theme.danger)
                        .clipShape(Circle())
                }
                .accessibilityLabel(L10n.timerCompactStop.text)
                .accessibilityIdentifier("CompactTimerStopButton")
            }
            .padding(.leading, Theme.spacingSmall)
            .padding(.trailing, Theme.spacingExtraSmall)
            .frame(height: 62)
            .background(Theme.backgroundSecondary)
            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                    .stroke(Theme.hairline, lineWidth: 0.7)
            }
            .padding(.horizontal, Theme.spacingSmall)
            .padding(.top, Theme.spacingExtraSmall)
        }
        .background(Theme.backgroundPrimary)
        .accessibilityIdentifier("CompactTimer")
    }
}

#if DEBUG
#Preview("Compact Timer") {
    CompactTimer(
        activityName: "Deep work",
        startedAt: Date().addingTimeInterval(-125),
        openTrack: {},
        stop: {}
    )
    .background(Theme.backgroundPrimary)
}
#endif
