import SwiftUI

/// The Today planner page (day-planner spec): one inline composer over the
/// visible checklist. Today is the only planner view — unfinished tasks
/// plus completions on the current local civil date, in the shared order,
/// with done/total counts from the same snapshot.
///
/// Layout contract: the composer sits ABOVE the list in a fixed slot, so
/// submitting never moves it and the keyboard stays open across repeated
/// Returns; the suggestions region has a fixed height and never resizes on
/// keystrokes; row changes apply without list-level motion (Reduce Motion
/// safe by construction — no explicit animations).
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
            suggestionsRegion
            if vm.timerActive {
                Text(L10n.plannerTimerActive.text)
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Theme.screenHorizontalPadding)
                    .padding(.vertical, Theme.spacingSmall)
                    .accessibilityIdentifier("PlannerTimerActiveCaption")
            }
            if vm.snapshot.tasks.isEmpty {
                emptyHint
            } else {
                taskList
            }
        }
        .background(Theme.backgroundPrimary.ignoresSafeArea())
    }

    // MARK: - Composer (stable keyboard, capped suggestions)

    /// The persistent inline field: Return appends one task, clears the
    /// draft, and keeps the input focused with the keyboard open — the
    /// composer never moves and no layout jumps.
    private var composer: some View {
        HStack(spacing: Theme.spacingSmall) {
            TextField(L10n.plannerComposerPlaceholder.text, text: $vm.draft)
                .focused($composerFocused)
                .textInputAutocapitalization(.sentences)
                .autocorrectionDisabled(false)
                .submitLabel(.done)
                .onSubmit { Task { await vm.submit() } }
                .accessibilityIdentifier("PlannerComposerField")
            Button(L10n.plannerAdd.text) {
                Task { await vm.submit() }
            }
            .disabled(ActivityName.normalized(vm.draft).isEmpty)
            .accessibilityIdentifier("PlannerAddButton")
        }
        .padding(.horizontal, Theme.screenHorizontalPadding)
        .padding(.vertical, Theme.spacingSmall)
    }

    /// Bounded matching suggestions: newest-first Recents filtered by the
    /// draft prefix, at most `suggestionDisplayCap`, in a fixed-height
    /// region that never resizes on keystrokes. Tapping one fills the
    /// composer with its exact text — no task is created, no timer starts.
    /// The region mounts once the draft is non-empty (one appearance, then
    /// a constant height) so an empty composer costs no space.
    private var suggestionsRegion: some View {
        Group {
            if !vm.draft.isEmpty {
                VStack(spacing: 0) {
                    ForEach(vm.suggestions) { recent in
                        Button {
                            vm.fillFromSuggestion(recent)
                            composerFocused = true
                        } label: {
                            Text(recent.activityText)
                                .foregroundStyle(Theme.textPrimary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("PlannerSuggestion-\(recent.activityText)")
                    }
                }
                .frame(maxWidth: .infinity, minHeight: Self.suggestionRowHeight * CGFloat(PlannerViewModel.suggestionDisplayCap), alignment: .top)
                .padding(.horizontal, Theme.screenHorizontalPadding)
                .accessibilityIdentifier("PlannerSuggestions")
            }
        }
    }

    private static let suggestionRowHeight: CGFloat = 28

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

    // MARK: - Checklist

    private var taskList: some View {
        List {
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

    private func reloadAndRegister() async {
        await vm.loadIfNeeded()
        await vm.registerSystemUndo(with: undoManager)
    }

    private func invalidateReloadAndRegister() async {
        vm.invalidate()
        await reloadAndRegister()
    }
}

/// One planner row: completion toggle, inline-renameable name, and a
/// one-tap Start for open tasks. Completed rows stay in position through
/// their completion day. VoiceOver reads the name plus its state; reorder
/// runs through the list's `onMove` (edit mode + rotor, never drag-only).
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

            if task.completedOn == nil {
                Button(L10n.timerStart.text) {
                    Task { await onStart() }
                }
                .buttonStyle(.bordered)
                .disabled(timerActive)
                .accessibilityIdentifier("PlannerStart-\(task.id)")
            }
        }
        .listRowBackground(Theme.backgroundPrimary)
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
                Image(systemName: "list.bullet")
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
