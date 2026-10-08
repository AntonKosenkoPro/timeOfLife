import ActivityKit
import SwiftUI
import WidgetKit

/// Live Activity presentations for the running timer (live-activities
/// spec: "Island and banner presentations").
///
/// Content rule: exact name + first-category icon only — no category
/// names, provenance labels, notes, or started-at lines. Elapsed faces
/// tick on-system via `Text(timerInterval:)` (no `update()` calls); the
/// icon arrives pre-validated from the app (`CatalogIcon.displaySymbol`
/// at request time, `"timer"` fallback), so the extension never validates.
struct TimerLiveActivityWidget: Widget {
    /// Deep link to Track (D5): every face navigates here on tap.
    private var trackURL: URL? {
        URL(string: "lifio://track")
    }

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TimerActivityAttributes.self) { context in
            if let saved = context.state.savedDurationSeconds {
                savedBanner(duration: TimerClock.formatted(saved))
            } else {
                runningBanner(
                    text: context.attributes.entryText,
                    iconSymbol: context.attributes.iconSymbol,
                    startedAt: context.state.startedAt
                )
            }
        } dynamicIsland: { context in
            DynamicIsland {
                // Layout (device finding): timer top-left, Stop top-right,
                // name full-width along the bottom for longer texts. No
                // visible Go-to control — tapping anywhere outside Stop
                // navigates via widgetURL.
                DynamicIslandExpandedRegion(.leading) {
                    expandedTimer(context: context)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .overlay(Capsule().stroke(.blue, lineWidth: 1))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 4)
                        .widgetURL(trackURL)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    HStack {
                        if context.state.savedDurationSeconds == nil {
                            LiveActivityStopPill()
                        } else {
                            Image(systemName: "checkmark")
                                .font(.title2)
                        }
                    }
                    .padding(.horizontal, 4)
                    .padding(.vertical, 4)
                    .widgetURL(trackURL)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack(spacing: 8) {
                        Image(systemName: context.attributes.iconSymbol)
                        Text(context.attributes.entryText)
                            .font(.headline)
                            .lineLimit(2)
                    }
                    // Same trailing breathing room as the timer above —
                    // keeps long names clear of the island's curve.
                    .padding(.horizontal, 8)
                    .padding(.top, 8)
                    .accessibilityLabel(LiveActivityStrings.runningAccessibilityLabel(text: context.attributes.entryText))
                    .widgetURL(trackURL)
                }
            } compactLeading: {
                Image(systemName: context.attributes.iconSymbol)
                    .widgetURL(trackURL)
            } compactTrailing: {
                islandElapsed(context: context)
                    .widgetURL(trackURL)
            } minimal: {
                Image(systemName: context.attributes.iconSymbol)
                    .widgetURL(trackURL)
            }
        }
    }

    // MARK: - Lock Screen banner

    private func runningBanner(text: String, iconSymbol: String, startedAt: Date) -> some View {
        HStack(spacing: 12) {
            Image(systemName: iconSymbol)
                .font(.title2)
            VStack(alignment: .leading, spacing: 2) {
                Text(text)
                    .font(.headline)
                    .lineLimit(1)
                Text(timerInterval: startedAt...Date.distantFuture, countsDown: false)
                    .font(.caption.monospacedDigit())
            }
            Spacer()
            LiveActivityStopButton()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(LiveActivityStrings.runningAccessibilityLabel(text: text))
        .widgetURL(trackURL)
    }

    private func savedBanner(duration: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark")
                .font(.headline)
            Text(LiveActivityStrings.savedCardTitle(duration: duration))
                .font(.headline)
        }
        .widgetURL(trackURL)
    }

    // MARK: - Dynamic Island

    /// Compact trailing timer in a stable narrow pill: sized by a
    /// phase-independent full skeleton (`00:00:00`) — widget bodies do
    /// not re-render on their own (device-proven: a render-time twin
    /// froze while the live text kept ticking into `10:…` truncation),
    /// so anything sized at render time goes stale within minutes. The
    /// live view has no intrinsic size (fills any proposal — the
    /// edge-to-edge pill; collapses under `fixedSize`), so the hidden
    /// twin sizes it via `overlay`, which takes no part in layout.
    private func islandElapsed(context: ActivityViewContext<TimerActivityAttributes>) -> some View {
        Group {
            if let saved = context.state.savedDurationSeconds {
                Text(TimerClock.formatted(saved))
            } else {
                huggingTimer(startedAt: context.state.startedAt)
            }
        }
        .font(.caption.monospacedDigit())
        .accessibilityLabel(LiveActivityStrings.runningAccessibilityLabel(text: context.attributes.entryText))
    }

    /// Live timer that hugs its content (see `islandElapsed`): the
    /// phase-independent full-skeleton twin sizes, the live view fills
    /// exactly that rect.
    private func huggingTimer(startedAt: Date) -> some View {
        Text("00:00:00")
            .hidden()
            .overlay(alignment: .leading) {
                Text(timerInterval: startedAt...Date.distantFuture, countsDown: false)
            }
    }
    
    /// Expanded leading timer with a stable full-skeleton border: the
    /// capsule always fits `H:MM:SS`, narrow and truncation-free — widget
    /// bodies do not re-render on their own (device-proven: a render-time
    /// twin froze while the live text kept ticking into truncation), so
    /// anything sized at render time goes stale within minutes.
    private func expandedTimer(context: ActivityViewContext<TimerActivityAttributes>) -> some View {
        Group {
            if let saved = context.state.savedDurationSeconds {
                Text(TimerClock.liveStyle(saved))
            } else {
                // Overlay (not ZStack): overlay content takes no part in
                // layout, so the hidden twin alone sizes the capsule and
                // the live view fills exactly that rect. (A ZStack sizes
                // to every child including the stretchy live view, which
                // is why the border went full-width again.)
                Text("00:00:00")
                    .hidden()
                    .overlay(alignment: .leading) {
                        Text(timerInterval: context.state.startedAt...Date.distantFuture, countsDown: false)
                    }
            }
        }
        .font(.subheadline.monospacedDigit())
        .accessibilityLabel(LiveActivityStrings.runningAccessibilityLabel(text: context.attributes.entryText))
    }
}

/// Circular Stop control shared by the banner and the expanded card (the
/// `CompactTimer` language: white glyph on a danger-red circle).
///
/// Hidden outside full-color rendering: in dimmed/accent modes (Always-on
/// display, StandBy) the button is not interactive, and a lone red dot is
/// all that survives the dimming — the AoD finding.
struct LiveActivityStopButton: View {
    @Environment(\.widgetRenderingMode)
    private var renderingMode

    var body: some View {
        if renderingMode == .fullColor {
            Button(intent: StopTimerIntent()) {
                Image(systemName: "stop.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(.red)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(LiveActivityStrings.stopAccessibilityLabel)
        }
    }
}

/// Pill Stop control (experimental alternative to the circle, currently
/// live in the expanded card so both can be compared on-device).
/// Same full-color-only rule as `LiveActivityStopButton`.
struct LiveActivityStopPill: View {
    @Environment(\.widgetRenderingMode)
    private var renderingMode

    var body: some View {
        if renderingMode == .fullColor {
            Button(intent: StopTimerIntent()) {
                Label(LiveActivityStrings.stopTitle, systemImage: "stop.fill")
                    .font(.subheadline)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(.red)
                    .clipShape(Capsule(style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(LiveActivityStrings.stopAccessibilityLabel)
        }
    }
}
