import SwiftUI

/// The Today planner page (day-planner spec): one inline composer fixed
/// at the bottom with the visible checklist above it. Today is the only
/// planner view — unfinished tasks plus completions on the current local
/// civil date, in the shared order, with done/total counts from the same
/// snapshot.
///
/// Layout contract: the composer sits in a bottom-fixed slot below the
/// list and never unmounts, so submitting never moves it and the keyboard
/// stays open across repeated Returns; a single horizontally scrollable
/// chips line sits fixed between the composer and the keyboard (visible
/// only while the keyboard is open), so each keystroke only swaps chips
/// inside that fixed-height line and neither the composer nor the list
/// moves; a fresh row expands in at the end (opacity-only under Reduce
/// Motion).
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
    /// Whether the software keyboard is open: the chips line mounts only
    /// then (day-planner 8.2), pinned just above it as the last slot.
    @State private var keyboardVisible = false
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
            if vm.snapshot.tasks.isEmpty {
                emptyHint
            } else {
                taskList
            }
            if vm.timerActive {
                Text(L10n.plannerTimerActive.text)
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Theme.screenHorizontalPadding)
                    .padding(.vertical, Theme.spacingSmall)
                    .accessibilityIdentifier("PlannerTimerActiveCaption")
            }
            composer
            chipsLine
        }
        .background(Theme.backgroundPrimary.ignoresSafeArea())
        .onReceive(NotificationCenter.default.publisher(
            for: UIResponder.keyboardWillShowNotification
        )) { _ in
            keyboardVisible = true
        }
        .onReceive(NotificationCenter.default.publisher(
            for: UIResponder.keyboardWillHideNotification
        )) { _ in
            keyboardVisible = false
        }
    }

    // MARK: - Composer (bottom-fixed, chips between it and the keyboard)

    /// The persistent inline field: Return appends one task at the end,
    /// clears the draft, and focus never leaves — the UIKit-backed field
    /// declines the Return default resign at dispatch (day-planner 7.1),
    /// so the keyboard never animates away no matter how slow the
    /// store/reload round-trip is. The composer never unmounts and no
    /// layout jumps.
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

    // MARK: - Checklist (chips live between composer and keyboard)

    private var taskList: some View {
        List {
            // The task rows sit under their own header: it renders whenever
            // this list shows, so the group always reads as one section.
            // A fresh row expands in at the end (see `PlannerRowInsertion`;
            // opacity-only under Reduce Motion).
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

    /// The chips line (day-planner 9.1): one horizontally scrollable row
    /// of recent-activity chips pinned between the composer and the
    /// keyboard — the last VStack slot, so the keyboard's safe-area inset
    /// lands directly under it. Visible only while the keyboard is open;
    /// an empty draft shows the full capped strip, typing prefix-filters
    /// it, and tapping a chip fills the composer with its exact text (no
    /// task created, no timer started). The slot stays mounted at one chip
    /// row while the keyboard is open even when the filter matches nothing
    /// (a hidden prototype holds the row height), so filter changes only
    /// swap chips inside the line and never move the composer or the list
    /// above.
    ///
    /// VoiceOver follows the visual order — list, then the composer, then
    /// the chips line next to the keyboard — so swipe order always matches
    /// the layout.
    @ViewBuilder private var chipsLine: some View {
        if keyboardVisible {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.spacingSmall) {
                    ForEach(vm.chips) { recent in
                        chip(recent)
                    }
                    if vm.chips.isEmpty {
                        // Holds one chip row so the line never collapses:
                        // identical text metrics, hidden from sight and
                        // assistive tech.
                        Text(" ")
                            .font(.subheadline)
                            .padding(.horizontal, Theme.spacingMedium)
                            .padding(.vertical, 12)
                            .frame(minHeight: Theme.minTapArea)
                            .hidden()
                            .accessibilityHidden(true)
                    }
                }
                .padding(.horizontal, Theme.screenHorizontalPadding)
                .frame(minHeight: Theme.minTapArea)
            }
            .frame(minHeight: Theme.minTapArea)
            .accessibilityIdentifier("PlannerChips")
        }
    }

    /// One chip: tapping fills the composer with the exact text.
    private func chip(_ recent: RecentEntry) -> some View {
        Button {
            vm.fillFromChip(recent)
            composerFocused = true
        } label: {
            Text(recent.activityText)
                .font(.subheadline)
                .lineLimit(1)
                .foregroundStyle(Theme.textPrimary)
                .padding(.horizontal, Theme.spacingMedium)
                .padding(.vertical, 12)
                .frame(minHeight: Theme.minTapArea)
                .background(Theme.backgroundSecondary)
                .clipShape(Capsule())
                .overlay {
                    Capsule().stroke(Theme.hairline, lineWidth: 0.7)
                }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("PlannerChip-\(recent.activityText)")
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
