import ActivityKit
import SwiftUI
import WidgetKit

import LifioLiveActivityCore

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
                    // Explicit width (proven on-device; the twin-overlay
                    // experiment does not constrain in the compact slot).
                    // The timer view has no intrinsic size — it fills any
                    // proposal (edge-to-edge pill) and collapses to zero
                    // under fixedSize. 52pt fits H:MM:SS in the ~52–62pt
                    // slot; monospaced digits keep shorter values stable.
                    .frame(width: 52, alignment: .trailing)
                    .widgetURL(trackURL)
            } minimal: {
                Image(systemName: context.attributes.iconSymbol)
                    .widgetURL(trackURL)
            }
        }
    }

    // MARK: - Lock Screen banner

    // Banner: icon + name + live ticking timer + Stop. No luminance
    // branch, no accent wrappers: the AoD blank was a device setting
    // (Face ID & Passcode → Allow Access When Locked → Live Activities),
    // not rendering — the system dims the live timer itself, like Apple's.
    private func runningBanner(text: String, iconSymbol: String, startedAt: Date) -> some View {
        HStack(spacing: 12) {
            // Deep-link zone scoped to the label: the root must NOT carry
            // widgetURL — a root URL also engages on Stop taps and demands
            // unlock on a locked phone (device finding), fighting the
            // alwaysAllowed intent. Body taps still go to Track.
            HStack(spacing: 12) {
                Image(systemName: iconSymbol)
                    .font(.title2)
                VStack(alignment: .leading, spacing: 2) {
                    Text(text)
                        .font(.headline)
                        .lineLimit(1)
                    Text(timerInterval: startedAt...Date.distantFuture, countsDown: false)
                        // Headline-bold: the banner timer must survive AoD
                        // dimming (device finding) — caption was too small.
                        .font(.headline.bold().monospacedDigit())
                        .lineLimit(1)
                }
            }
            .widgetURL(trackURL)
            Spacer()
            LiveActivityStopButton()
        }
        // Banner breathing room: the HStack otherwise sits flush against
        // the banner's top/bottom edges (device finding, verified 8pt).
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(LiveActivityStrings.runningAccessibilityLabel(text: text))
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

    /// Compact trailing timer: plain live view; the width contract lives
    /// at the call site (`.frame(width: 52)` — see there for why).
    private func islandElapsed(context: ActivityViewContext<TimerActivityAttributes>) -> some View {
        Group {
            if let saved = context.state.savedDurationSeconds {
                Text(TimerClock.formatted(saved))
            } else {
                Text(timerInterval: context.state.startedAt...Date.distantFuture, countsDown: false)
            }
        }
        .font(.caption.monospacedDigit())
        // View-level alignment comes from the call-site frame; this aligns
        // the glyph run inside the (filled) text box — without it the
        // digits sit leading despite the trailing frame.
        .multilineTextAlignment(.trailing)
        .accessibilityLabel(LiveActivityStrings.runningAccessibilityLabel(text: context.attributes.entryText))
    }
    
    /// Expanded leading timer with a dynamically hugging border: the
    /// capsule wraps the visible digits only and grows with them
    /// (`0:01` narrow → `1:23:45` wide). The live timer view has no
    /// intrinsic size (it fills any proposal and collapses to zero under
    /// fixedSize), so the size comes from a hidden static twin in the same
    /// format (`TimerClock.liveStyle`) that the live view fills exactly —
    /// no fixed points, so Dynamic Type stays safe. The twin freezes at
    /// render time: a phase crossing (59→1:00) without a re-render keeps
    /// the previous width until the next render.
    private func expandedTimer(context: ActivityViewContext<TimerActivityAttributes>) -> some View {
        let totalSeconds: Int = {
            if let saved = context.state.savedDurationSeconds {
                return saved
            }
            return max(0, Int(Date().timeIntervalSince(context.state.startedAt)))
        }()
        return Group {
            if context.state.savedDurationSeconds != nil {
                Text(TimerClock.liveStyle(totalSeconds))
            } else {
                // Overlay (not ZStack): overlay content takes no part in
                // layout, so the hidden twin alone sizes the capsule and
                // the live view fills exactly that rect. (A ZStack sizes
                // to every child including the stretchy live view, which
                // is why the border went full-width again.)
                Text(TimerClock.liveStyle(totalSeconds))
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
/// Always rendered, including dimmed faces: the button lives in the same
/// HStack row as the timer, so it cannot change the banner height, and
/// the postmortem showed the AoD blank was a device setting (Face ID &
/// Passcode → Allow Access When Locked → Live Activities), not rendering —
/// hiding the control would only remove a working lock-screen action.
struct LiveActivityStopButton: View {
    var body: some View {
        Button(intent: StopTimerIntent()) {
            Image(systemName: "stop.fill")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(LiveActivityTheme.stopForeground)
                .frame(width: 44, height: 44)
                .background(LiveActivityTheme.stopBackground)
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(LiveActivityStrings.stopAccessibilityLabel)
    }
}

/// Pill Stop control (experimental alternative to the circle, currently
/// live in the expanded card so both can be compared on-device).
/// Same always-render rule as `LiveActivityStopButton`.
struct LiveActivityStopPill: View {
    var body: some View {
        Button(intent: StopTimerIntent()) {
            Label(LiveActivityStrings.stopTitle, systemImage: "stop.fill")
                .font(.subheadline)
                .foregroundStyle(LiveActivityTheme.stopForeground)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(LiveActivityTheme.stopBackground)
                .clipShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(LiveActivityStrings.stopAccessibilityLabel)
    }
}
