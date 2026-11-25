import SwiftUI

/// The Today planner page (day-planner spec): one inline composer over the
/// visible checklist. Today is the only planner view — unfinished tasks
/// plus completions on the current local civil date, in the shared order,
/// with done/total counts from the same snapshot.
///
/// Layout contract: the composer sits ABOVE the list in a fixed slot and
/// never unmounts, so submitting never moves it and the keyboard stays open
/// across repeated Returns; matching Recents render as rows in a suggestions
/// section at the top of that same list (never a separate mounting region),
/// so each keystroke only swaps rows inside the list surface; row changes
/// apply without list-level motion (Reduce Motion safe by construction —
/// no explicit animations).
struct PlannerView: View {
    @ObservedObject var vm: PlannerViewModel
    @EnvironmentObject var sync: SyncController
    @Environment(\.undoManager)
    private var undoManager
    /// Opens Track after a successful one-tap Start (the run lives there).
    /// Defaults to no-op for previews.
    var onStartActive: () -> Void = {}
    @FocusState private var composerFocused: Bool
    @FocusState private var renamingRowID: String?
    var body: some View {
        content
            .navigationTitle(L10n.plannerTitle.text)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    EditButton()
                        .accessibilityIdentifier("PlannerEditButton")
                }
            }
            .task { await reloadAndRegister() }
            .onAppear {
                Task { await reloadAndRegister() }
                // Fast repeated input: an empty composer takes focus on
                // entry so typing starts immediately.
                if vm.draft.isEmpty {
                    composerFocused = true
                }
            }
            .onDisappear {
                vm.invalidate()
            }
            // A sync cycle merges relay state behind this view: reload on
            // exit from `.syncing` (History precedent).
            .onChange(of: sync.status) { _, status in
                switch status {
                case .idle, .error:
                    Task { await invalidateReloadAndRegister() }
                case .inactive, .syncing:
                    break
                }
            }
            // Today follows the local calendar: re-derive when returning to
            // the foreground or when the clock/zone changes.
            .onReceive(NotificationCenter.default.publisher(
                for: UIApplication.willEnterForegroundNotification
            )) { _ in
                Task { await invalidateReloadAndRegister() }
            }
            .onReceive(NotificationCenter.default.publisher(
                for: .NSSystemClockDidChange
            )) { _ in
                Task { await invalidateReloadAndRegister() }
            }
            // System shake-to-undo for planner deletions (entry/category
            // precedent): shakes reach the registration `registerSystemUndo`
            // owns.
            .background(ShakeFirstResponderHost(undoManager: undoManager))
            .alert(
                L10n.text(in: .default, code: "error.unknown"),
                isPresented: Binding(
                    get: { vm.errorMessage != nil },
                    set: { if !$0 { vm.errorMessage = nil } }
                )
            ) {}
    }

    private var content: some View {
        VStack(spacing: 0) {
            composer
            if vm.timerActive {
                Text(L10n.plannerTimerActive.text)
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Theme.screenHorizontalPadding)
                    .padding(.vertical, Theme.spacingSmall)
                    .accessibilityIdentifier("PlannerTimerActiveCaption")
            }
            if vm.snapshot.tasks.isEmpty && vm.suggestions.isEmpty {
                emptyHint
            } else {
                taskList
            }
        }
        .background(Theme.backgroundPrimary.ignoresSafeArea())
    }

    // MARK: - Composer (stable keyboard, in-list suggestions)

    /// The persistent inline field: Return appends one task, clears the
    /// draft, and focus never leaves — the UIKit-backed field declines the
    /// Return default resign at dispatch (day-planner 7.1), so the keyboard
    /// never animates away no matter how slow the store/reload round-trip
    /// is. The composer never unmounts and no layout jumps.
    private var composer: some View {
        HStack(spacing: Theme.spacingSmall) {
            PlannerComposerField(
                text: $vm.draft,
                placeholder: L10n.plannerComposerPlaceholder.text,
                focused: $composerFocused,
                accessibilityIdentifier: "PlannerComposerField"
            ) {
                Task { await vm.submit() }
            }
            Button(L10n.plannerAdd.text) {
                Task { await vm.submit() }
            }
            .disabled(ActivityName.normalized(vm.draft).isEmpty)
            .accessibilityIdentifier("PlannerAddButton")
        }
        .padding(.horizontal, Theme.screenHorizontalPadding)
        .padding(.vertical, Theme.spacingSmall)
    }

    private var emptyHint: some View {
        Text(L10n.plannerEmptyHint.text)
            .font(.body)
            .foregroundStyle(Theme.textSecondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, Theme.screenHorizontalPadding)
            .padding(.top, Theme.spacingLarge)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .accessibilityIdentifier("PlannerEmptyHint")
    }

    // MARK: - Checklist (suggestions live in the same list)

    private var taskList: some View {
        List {
            if !vm.suggestions.isEmpty {
                // Suggestions are rows in a top section of this same list —
                // never a separate mounting region — so the composer above
                // keeps its exact frame whether they show or not. Tapping
                // one fills the composer with its exact text: no task is
                // created, no timer starts.
                Section {
                    ForEach(vm.suggestions) { recent in
                        suggestionRow(recent)
                    }
                } header: {
                    Text(L10n.plannerSuggestions.text)
                }
                .accessibilityIdentifier("PlannerSuggestions")
            }
            // The task rows sit under their own header (Mail's Top
            // Results/Suggestions split): it renders whenever this list
            // shows, with or without suggestions above, so the two groups
            // always read as distinct sections (VoiceOver document order).
            Section {
                ForEach(vm.snapshot.tasks) { task in
                    PlannerTaskRow(
                        task: task,
                        timerActive: vm.timerActive,
                        isRenaming: vm.editingTaskID == task.id,
                        editText: $vm.editText,
                        focusedRowID: $renamingRowID,
                        onToggle: { Task { await vm.toggleComplete(task) } },
                        onRenameTap: { vm.beginRename(task) },
                        onRenameCommit: { Task { await vm.commitRename(task) } },
                        onRenameCancel: {
                            vm.cancelRename()
                            renamingRowID = nil
                        },
                        onStart: {
                            if await vm.startTask(task) { onStartActive() }
                        }
                    )
                }
                .onDelete { offsets in Task { await vm.delete(at: offsets) } }
                .onMove { source, destination in Task { await vm.move(from: source, to: destination) } }
            } header: {
                Text(L10n.plannerTasks.text)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .onChange(of: vm.editingTaskID) { _, id in
            renamingRowID = id
        }
        // Focus left a rename field without committing (the user tapped
        // elsewhere): commit instead of stranding a half-typed rename.
        // Programmatic commits clear `editingTaskID` first, so this only
        // fires for genuine focus loss.
        .onChange(of: renamingRowID) { _, new in
            if new == nil,
               let id = vm.editingTaskID,
               let task = vm.snapshot.tasks.first(where: { $0.id == id }) {
                Task { await vm.commitRename(task) }
            }
        }
        .accessibilityIdentifier("PlannerTaskList")
    }

    /// One suggestion row: tapping fills the composer with the exact text.
    /// The matched prefix renders bold so the refinement is visible while
    /// typing; VoiceOver reads the full text in list order (suggestions
    /// first, then tasks — document order, no explicit sort needed).
    private func suggestionRow(_ recent: RecentEntry) -> some View {
        let parts = PlannerSuggestionHighlight.split(text: recent.activityText, draft: vm.draft)
        return Button {
            vm.fillFromSuggestion(recent)
            composerFocused = true
        } label: {
            (Text(parts.match).bold() + Text(parts.rest))
                .foregroundStyle(Theme.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("PlannerSuggestion-\(recent.activityText)")
    }

    private func reloadAndRegister() async {
        await vm.loadIfNeeded()
        await vm.registerSystemUndo(with: undoManager)
    }

    private func invalidateReloadAndRegister() async {
        vm.invalidate()
        await reloadAndRegister()
    }
}

/// One planner row: completion toggle, inline-renameable name, and the
/// Start affordance slot (always mounted — see `PlannerStartSlot`).
/// Completed rows stay in position through their completion day. VoiceOver
/// reads the name plus its state; reorder runs through the list's `onMove`
/// (edit mode + rotor, never drag-only).
private struct PlannerTaskRow: View {
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

/// Suggestion match highlight (day-planner spec 5.4): splits a suggestion's
/// exact text into the draft's matched prefix (rendered bold) and the
/// remainder. Matching mirrors the view model's prefix rule —
/// case-insensitive over the normalized draft — so the highlight always
/// covers exactly the filter match. Pinned by `PlannerRowLayoutTests`.
enum PlannerSuggestionHighlight {
    static func split(text: String, draft: String) -> (match: String, rest: String) {
        let trimmed = ActivityName.normalized(draft)
        guard !trimmed.isEmpty,
              text.lowercased().hasPrefix(trimmed.lowercased()),
              trimmed.count <= text.count
        else { return ("", text) }
        let end = text.index(text.startIndex, offsetBy: trimmed.count)
        return (String(text[..<end]), String(text[end...]))
    }
}

/// The compact Track progress control (timer-capture-experience spec): a
/// toolbar entry opening Today in the Track navigation stack. It reports
/// the same Today projection's done/total counts, offers an entry point
/// even when the list is empty, stays usable while timing, and never
/// moves the numeric readout or Start/Stop (it lives in the navigation
/// chrome, outside the timer's measured layout).
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
