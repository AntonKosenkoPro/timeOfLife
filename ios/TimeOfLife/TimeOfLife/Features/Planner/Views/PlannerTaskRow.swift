import SwiftUI

/// One planner row: completion toggle, task name with its ordered category
/// chips under it (small icon+name chips in Live Activity chip grammar, cap
/// 2 + `+n` overflow) and a notes indicator trailing the chips, and the
/// Start affordance slot (always mounted — see `PlannerStartSlot`). While
/// the task carries the active linked run the slot shows the localized `In
/// progress` label in the accent color over the preserved slot footprint
/// instead of the Start button. Completed rows stay in position through
/// their completion day. Toggling completion changes neither the chips nor
/// the slot, so the row keeps its exact height and no sibling moves.
/// VoiceOver reads the name, then its ordered category names, then notes
/// presence, then the actions — one combined element for the name control
/// (EntryRow precedent at the row is split here: the row keeps three
/// separate controls, so the merge lives on the name control).
/// Reorder runs through the list's `onMove` (the dedicated reorder control
/// surfaces the handles, VoiceOver rotor included — never an Edit button,
/// never drag-only). A fresh row expands in at the top (see `PlannerRowInsertion`;
/// opacity-only under Reduce Motion).
struct PlannerTaskRow: View {
    /// Maximum category chips rendered under the name (Live Activity chip
    /// grammar: cap 2 + `+n` overflow — the row never grows with the set).
    static let maxVisibleCategoryChips = 2

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
    /// The inline blocked-Start error (day-planner 19.1): non-nil only for
    /// the row whose dimmed Start was tapped while a run is active. Renders
    /// as a short red multi-line label under the name (wrapping, never
    /// truncated — the copy stays tight for the largest Dynamic Type).
    let blockedError: String?
    /// Blocked-Start shake attempts (day-planner 19.1): the view bumps this
    /// on every rejected tap and the error label shakes off it
    /// (NotesEditorPage overcount grammar — suppressed under Reduce
    /// Motion, the haptic still fires).
    let shakeAttempts: Int
    /// Under Reduce Motion the top-row insertion is opacity-only instead
    /// of expanding (day-planner 8.1).
    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion

    /// The notes-indicator rule: whitespace-only counts as empty
    /// (history-entry-list).
    static func hasNotes(_ task: PlannerTask) -> Bool {
        !task.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// The chips slice for a row's ordered set: the visible prefix plus the
    /// hidden overflow count (Live Activity cap grammar — the row shows at
    /// most `maxVisibleCategoryChips` chips and a `+n` overflow label).
    static func chipSlice(for categories: [Category]) -> (shown: [Category], overflow: Int) {
        let shown = Array(categories.prefix(maxVisibleCategoryChips))
        return (shown, max(0, categories.count - shown.count))
    }

    /// VoiceOver label for the name control: the task name, then its ordered
    /// category names, then the notes presence (the chips and the indicator
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

    /// The visible chips slice for this row's ordered set (computed once
    /// per body pass).
    private var slice: (shown: [Category], overflow: Int) {
        Self.chipSlice(for: categories)
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
                VStack(alignment: .leading, spacing: Theme.spacingExtraSmall) {
                    Text(task.name)
                        .foregroundStyle(task.completedOn == nil ? Theme.textPrimary : Theme.textSecondary)
                        .strikethrough(task.completedOn != nil)
                    // The ordered set as small icon+name chips (Live Activity
                    // chip grammar, `chipSlice` cap); the notes indicator
                    // trails them, so the visual order is name → chips →
                    // indicator — the same order VoiceOver announces. The
                    // slice depends only on the set (never on completion or
                    // the run), so toggling keeps the row's exact height.
                    if !slice.shown.isEmpty || Self.hasNotes(task) {
                        HStack(spacing: 4) {
                            ForEach(slice.shown) { category in
                                HStack(spacing: 2) {
                                    Image(systemName: CatalogIcon(validated: category.icon).displaySymbol)
                                        .font(.caption2)
                                    Text(category.name)
                                        .font(.caption)
                                        .lineLimit(1)
                                }
                                .foregroundStyle(Theme.textSecondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Theme.backgroundSecondary)
                                .clipShape(Capsule())
                                .overlay {
                                    Capsule().stroke(Theme.hairline, lineWidth: 0.5)
                                }
                                .accessibilityHidden(true)
                            }
                            if slice.overflow > 0 {
                                Text("+\(slice.overflow)")
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
                    }
                    // Blocked-Start error (day-planner 19.1, ungated 20.1):
                    // the short red message for a Start tapped while a run
                    // is active — wrapping lines, never a one-line
                    // truncation, shaking on every rejected tap. It renders
                    // for every row, including a bare task with no
                    // categories or notes (nested inside the chips gate it
                    // never mounted there — owner report 2026-11-27).
                    if let blockedError {
                        Text(blockedError)
                            .font(.footnote)
                            .foregroundStyle(Theme.danger)
                            .multilineTextAlignment(.leading)
                            .keyframeAnimator(initialValue: CGFloat.zero, trigger: shakeAttempts) { content, value in
                                content.offset(x: value)
                            } keyframes: { _ in
                                KeyframeTrack {
                                    CubicKeyframe(12, duration: 0.06)
                                    CubicKeyframe(-9, duration: 0.06)
                                    CubicKeyframe(6, duration: 0.06)
                                    CubicKeyframe(-3, duration: 0.06)
                                    CubicKeyframe(0, duration: 0.06)
                                }
                            }
                            .accessibilityIdentifier("PlannerBlockedStartError")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            // One VoiceOver element: the decorative icons and indicator
            // merge into the button's explicit label (EntryRow merges at
            // the row; this row keeps three separate controls, so the
            // merge lives on the name control, not the row).
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Self.accessibilityLabel(task: task, categories: categories))
            .accessibilityIdentifier("PlannerName-\(task.id)")

            // The Start affordance slot stays mounted in every state
            // (day-planner spec: toggle keeps the list still): completed
            // rows and the running row hide the control visually and from
            // assistive tech while preserving its exact layout footprint
            // (the `ZStack` sizes to the hidden button — the label is
            // shorter — so open, completed, and running rows share one
            // height and no sibling moves). A visible Start under an active
            // run renders dimmed (the PrimaryButton disabled-fill grammar)
            // but stays tappable: the tap shows the row's inline red error
            // and plays the reject haptic instead of starting (day-planner
            // 19.1) — a truly disabled control would swallow the tap. See
            // `PlannerStartSlot`.
            ZStack {
                Button(L10n.timerStart.text) {
                    Task { await onStart() }
                }
                .buttonStyle(.bordered)
                .disabled(task.completedOn != nil)
                .opacity(slot.showsButton ? (timerActive ? Theme.opacityDisabledFill : 1) : 0)
                .accessibilityHidden(!slot.showsButton)
                .accessibilityIdentifier("PlannerStart-\(task.id)")
                if slot.showsLabel {
                    Text(L10n.plannerInProgress.text)
                        .font(.subheadline)
                        .foregroundStyle(Theme.accentPrimary)
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
