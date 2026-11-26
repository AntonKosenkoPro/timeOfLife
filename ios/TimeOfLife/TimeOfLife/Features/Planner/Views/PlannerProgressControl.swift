import SwiftUI

/// The compact Track progress control (timer-capture-experience spec): a
/// toolbar entry opening Today in the Track navigation stack. It reports
/// the same Today projection's done/total counts, offers an entry point
/// even when the list is empty, stays usable while timing, and never
/// moves the numeric readout or Start/Stop (it lives in the navigation
/// chrome, outside the timer's measured layout). The launch gate preloads
/// the projection, so it shows actual counts on first paint from warm
/// local data (no 0/0 flash).
struct PlannerProgressControl: View {
    let snapshot: PlannerToday.Snapshot
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 4) {
                Image(systemName: "checklist")
                Text("\(snapshot.done)/\(snapshot.total)")
                    .monospacedDigit()
            }
        }
        .accessibilityLabel(String(
            format: L10n.plannerProgressLabel.text,
            snapshot.done,
            snapshot.total
        ))
        .accessibilityIdentifier("PlannerProgressControl")
    }
}
