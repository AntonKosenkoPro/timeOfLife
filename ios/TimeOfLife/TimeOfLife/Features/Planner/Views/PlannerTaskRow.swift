import SwiftUI

/// One planner row: completion toggle, inline-renameable name, and the
/// Start affordance slot (always mounted — see `PlannerStartSlot`).
/// Completed rows stay in position through their completion day. VoiceOver
/// reads the name plus its state; reorder runs through the list's `onMove`
/// (edit mode + rotor, never drag-only). A fresh row expands in at the top
/// (see `PlannerRowInsertion`; opacity-only under Reduce Motion).
struct PlannerTaskRow: View {
    let task: PlannerTask
    let timerActive: Bool
    let isRenaming: Bool
    @Binding var editText: String
    var focusedRowID: FocusState<String?>.Binding
    let onToggle: () -> Void
    let onRenameTap: () -> Void
    let onRenameCommit: () -> Void
    let onRenameCancel: () -> Void
    let onStart: () async -> Void
    /// Under Reduce Motion the top-row insertion is opacity-only instead
    /// of expanding (day-planner 8.1).
    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion

    var body: some View {
        HStack(spacing: Theme.spacingSmall) {
            Button(action: onToggle) {
                Image(systemName: task.completedOn == nil ? "circle" : "checkmark.circle.fill")
                    .foregroundStyle(task.completedOn == nil ? Theme.textSecondary : Theme.accentPrimary)
                    .font(.system(size: 22))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(task.completedOn == nil ? L10n.plannerMarkDone.text : L10n.plannerReopen.text)
            .accessibilityIdentifier("PlannerToggle-\(task.id)")

            if isRenaming {
                HStack(spacing: Theme.spacingSmall) {
                    TextField("", text: $editText)
                        .focused(focusedRowID, equals: task.id)
                        .onSubmit(onRenameCommit)
                        .submitLabel(.done)
                        .foregroundStyle(Theme.textPrimary)
                        .accessibilityLabel(L10n.plannerRename.text)
                        .accessibilityIdentifier("PlannerRenameField-\(task.id)")
                    // Cancels the rename (the Track clear-button grammar:
                    // small dim trailing × while editing).
                    Button(action: onRenameCancel) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(Theme.textSecondary)
                            .opacity(0.6)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L10n.nameClear.text)
                    .accessibilityIdentifier("PlannerRenameCancel-\(task.id)")
                }
            } else {
                Button(action: onRenameTap) {
                    Text(task.name)
                        .foregroundStyle(task.completedOn == nil ? Theme.textPrimary : Theme.textSecondary)
                        .strikethrough(task.completedOn != nil)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("PlannerName-\(task.id)")
            }

            // The Start affordance slot stays mounted in both states
            // (day-planner spec: toggle keeps the list still): completed
            // rows hide it visually and from assistive tech while preserving
            // its exact layout footprint, so open and completed rows share
            // one height and no sibling moves. See `PlannerStartSlot`.
            Button(L10n.timerStart.text) {
                Task { await onStart() }
            }
            .buttonStyle(.bordered)
            .disabled(timerActive || task.completedOn != nil)
            .opacity(PlannerStartSlot.slot(for: task).isHidden ? 0 : 1)
            .accessibilityHidden(task.completedOn != nil)
            .accessibilityIdentifier("PlannerStart-\(task.id)")
        }
        .listRowBackground(Theme.backgroundPrimary)
        // Fresh rows expand in at the top (the submit round-trip wraps the
        // snapshot publish in `withAnimation`); only inserted rows carry a
        // transition, so toggles, moves, and reloads stay still.
        .transition(PlannerRowInsertion.transition(reduceMotion: reduceMotion))
    }
}

/// Start-affordance slot for a planner row (day-planner spec 5.3): both
/// states mount the slot, so open and completed rows share one exact
/// height and toggling completion moves no sibling row. The completed
/// state hides the control visually (`.opacity(0)` preserves layout) and
/// from assistive tech (`.accessibilityHidden`), and disables it so the
/// invisible button never fires. Pinned by `PlannerRowLayoutTests` (the
/// `ClearButtonVisibility` precedent — SwiftUI layout is not unit-testable,
/// so the tests pin this helper and the row consumes it).
enum PlannerStartSlot: Equatable {
    /// Open task: the Start button shows and fires (unless a run is active).
    case visible
    /// Completed task: the slot stays mounted but hidden and inert.
    case hiddenPreservingLayout

    /// Whether the control hides while keeping its layout footprint.
    var isHidden: Bool {
        self == .hiddenPreservingLayout
    }

    static func slot(for task: PlannerTask) -> PlannerStartSlot {
        task.completedOn == nil ? .visible : .hiddenPreservingLayout
    }
}

/// Top-row insertion transition (day-planner 8.1): a fresh task expands
/// from zero to full height at the top of the list (scale from the top
/// edge plus fade); under Reduce Motion the insertion is opacity-only (no
/// expansion). Pinned by `PlannerRowLayoutTests` — SwiftUI transitions are
/// not unit-testable, so the tests pin this helper (the `PlannerStartSlot`
/// precedent).
enum PlannerRowInsertion {
    /// Whether a fresh row expands in (false under Reduce Motion).
    static func expands(reduceMotion: Bool) -> Bool { !reduceMotion }

    /// The row transition for the current motion setting.
    static func transition(reduceMotion: Bool) -> AnyTransition {
        expands(reduceMotion: reduceMotion)
            ? .scale(scale: 0, anchor: .top).combined(with: .opacity)
            : .opacity
    }
}
