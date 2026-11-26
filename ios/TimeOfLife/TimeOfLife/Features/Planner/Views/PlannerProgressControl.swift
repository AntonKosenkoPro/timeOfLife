import SwiftUI

/// The compact Track progress control (timer-capture-experience spec): a
/// toolbar entry opening Today in the Track navigation stack. It reports
/// the same Today projection's done/total counts, offers an entry point
/// even when the list is empty, stays usable while timing, and never
/// moves the numeric readout or Start/Stop (it lives in the navigation
/// chrome, outside the timer's measured layout). The launch gate preloads
/// the projection, so it shows actual counts on first paint from warm
/// local data (no 0/0 flash). The icon follows completion: `unchecked` at
/// 0 done (including an empty list), `checklist` while partial, `checked`
/// at N/N with N > 0.
struct PlannerProgressControl: View {
    let snapshot: PlannerToday.Snapshot
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 4) {
                Image(systemName: PlannerProgressIcon.symbol(done: snapshot.done, total: snapshot.total))
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

/// The progress icon contract (timer-capture-experience 14.3): the SF
/// Symbol name for a done/total pair. Pure so the per-state mapping is
/// unit-testable; the test also resolves each symbol at runtime — a
/// missing symbol renders nothing, so the suite fails instead of shipping
/// a silent blank.
enum PlannerProgressIcon {
    /// The SF Symbol name for `done` of `total`.
    static func symbol(done: Int, total: Int) -> String {
        if done <= 0 {
            return "checklist.unchecked"
        }
        if done >= total {
            return "checklist.checked"
        }
        return "checklist"
    }
}
