import SwiftUI

/// One planner row: completion toggle, task name (tapping opens the task
/// editor sheet), and the Start affordance slot (always mounted — see
/// `PlannerStartSlot`). While the task carries the active linked run the
/// slot shows the localized `In progress` label over the preserved slot
/// footprint instead of the Start button. Completed rows stay in position
/// through their completion day. Task categories render as ordered icons
/// and non-empty notes as an indicator, both inline after the name; both
/// stay inside the single-line layout, so no state changes the row height.
/// VoiceOver reads the name plus its category names and notes presence.
/// Reorder runs through the list's `onMove` (edit mode + rotor, never
/// drag-only). A fresh row expands in at the top (see `PlannerRowInsertion`;
/// opacity-only under Reduce Motion).
struct PlannerTaskRow: View {
    let task: PlannerTask
    /// Ordered categories resolved by the view model (icons render in
    /// task order; unknown ids already dropped).
    let categories: [Category]
    let timerActive: Bool
    /// Whether this task carries the active linked run.
    let isRunning: Bool
    let onToggle: () -> Void
    let onEdit: () -> Void
    let onStart: () async -> Void
    /// Under Reduce Motion the top-row insertion is opacity-only instead
    /// of expanding (day-planner 8.1).
    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion

    /// The notes-indicator rule: whitespace-only counts as empty
    /// (history-entry-list).
    static func hasNotes(_ task: PlannerTask) -> Bool {
        !task.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// VoiceOver label for the name control: the task name plus its ordered
    /// category names and the notes presence (the icons and the indicator
    /// are decorative). EntryRow.accessibilityLabel precedent.
    static func accessibilityLabel(task: PlannerTask, categories: [Category]) -> String {
        var parts = [task.name]
        let names = categories.map(\.name).joined(separator: ", ")
        if !names.isEmpty { parts.append(names) }
        if hasNotes(task) { parts.append(L10n.historyHasNotes.text) }
        return parts.joined(separator: ", ")
    }

    /// The resolved Start-affordance slot (computed once per body pass).
    private var slot: PlannerStartSlot {
        PlannerStartSlot.slot(for: task, isRunning: isRunning)
    }

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

            Button(action: onEdit) {
                HStack(spacing: Theme.spacingExtraSmall) {
                    Text(task.name)
                        .foregroundStyle(task.completedOn == nil ? Theme.textPrimary : Theme.textSecondary)
                        .strikethrough(task.completedOn != nil)
                    ForEach(categories) { category in
                        Image(systemName: CatalogIcon(validated: category.icon).displaySymbol)
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                            .accessibilityHidden(true)
                    }
                    if Self.hasNotes(task) {
                        Image(systemName: "note.text")
                            .font(.caption)
                            .foregroundStyle(Theme.accentPrimary)
                            .accessibilityHidden(true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Self.accessibilityLabel(task: task, categories: categories))
            .accessibilityIdentifier("PlannerName-\(task.id)")

            // The Start affordance slot stays mounted in every state
            // (day-planner spec: toggle keeps the list still): completed
            // rows and the running row hide the control visually and from
            // assistive tech while preserving its exact layout footprint
            // (the `ZStack` sizes to the hidden button — the label is
            // shorter — so open, completed, and running rows share one
            // height and no sibling moves). See `PlannerStartSlot`.
            ZStack {
                Button(L10n.timerStart.text) {
                    Task { await onStart() }
                }
                .buttonStyle(.bordered)
                .disabled(timerActive || task.completedOn != nil)
                .opacity(slot.showsButton ? 1 : 0)
                .accessibilityHidden(!slot.showsButton)
                .accessibilityIdentifier("PlannerStart-\(task.id)")
                if slot.showsLabel {
                    Text(L10n.plannerInProgress.text)
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                        .accessibilityIdentifier("PlannerInProgress-\(task.id)")
                }
            }
        }
        .listRowBackground(Theme.backgroundPrimary)
        // Fresh rows expand in at the top (the submit round-trip wraps the
        // snapshot publish in `withAnimation`); only inserted rows carry a
        // transition, so toggles, moves, and reloads stay still.
        .transition(PlannerRowInsertion.transition(reduceMotion: reduceMotion))
    }
}

/// Start-affordance slot for a planner row (day-planner spec 5.3/15.4):
/// every state mounts the slot, so open, completed, and running rows share
/// one exact height and toggling completion moves no sibling row. The
/// completed state hides the control visually (`.opacity(0)` preserves
/// layout) and from assistive tech, and disables it so the invisible
/// button never fires. The running state layers the localized `In
/// progress` label over the same preserved footprint instead of Start.
/// Pinned by `PlannerRowLayoutTests` (the `ClearButtonVisibility`
/// precedent — SwiftUI layout is not unit-testable, so the tests pin this
/// helper and the row consumes it).
enum PlannerStartSlot: Equatable {
    /// Open task: the Start button shows and fires (unless a run is active).
    case visible
    /// Completed task: the slot stays mounted but hidden and inert.
    case hiddenPreservingLayout
    /// Running task: the slot stays mounted showing `In progress`.
    case inProgress

    /// Whether the Start button control shows (completed and running rows
    /// hide it while keeping its layout footprint).
    var showsButton: Bool {
        self == .visible
    }

    /// Whether the control hides while keeping its layout footprint.
    var isHidden: Bool {
        !showsButton
    }

    /// Whether the `In progress` label shows over the preserved slot.
    var showsLabel: Bool {
        self == .inProgress
    }

    /// The running run wins over completion: a task completed mid-run
    /// still carries the live timer, so it reads `In progress`.
    static func slot(for task: PlannerTask, isRunning: Bool) -> PlannerStartSlot {
        if isRunning { return .inProgress }
        return task.completedOn == nil ? .visible : .hiddenPreservingLayout
    }
}

/// Top insertion transition (day-planner 8.1, top placement 12.2): a fresh
/// task expands from zero to full height at the top of the list (scale
/// from the top edge plus fade); under Reduce Motion the insertion is
/// opacity-only (no expansion). Pinned by `PlannerRowLayoutTests` —
/// SwiftUI transitions are not unit-testable, so the tests pin this
/// helper (the `PlannerStartSlot` precedent).
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
