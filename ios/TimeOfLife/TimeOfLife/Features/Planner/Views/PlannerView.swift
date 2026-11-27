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
/// moves; a fresh row expands in at the top (opacity-only under Reduce
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
    /// Whether the software keyboard is open: the chips line mounts only
    /// then (day-planner 8.2), pinned just above it as the last slot.
    @State private var keyboardVisible = false
    /// Reorder mode (day-planner 18.2): the dedicated reorder control owns
    /// this — there is no Edit button and no edit-mode deletion UI. While
    /// active the list's `onMove` handles show drag handles (and the rotor
    /// reorder path stays live); delete affordances never appear.
    @State private var isReordering = false
    /// Blocked-Start error shake attempts (day-planner 19.1): a disabled
    /// Start tap shows the row's inline red error and plays the reject
    /// haptic instead of starting (NotesEditorPage overcount grammar —
    /// suppressed under Reduce Motion, the haptic still fires).
    @State private var blockedStartShakeAttempts = 0
    /// Under Reduce Motion the reject shake is suppressed (the reject
    /// haptic is the non-motion channel).
    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion
    /// UIKit editing state of the composer (day-planner 11.1): drives the
    /// trailing clear button — the `composerFocused` flag only issues
    /// focus requests and never observes UIKit-side focus back.
    @State private var composerEditing = false
    var body: some View {
        content
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // The running indicator lives on the row (day-planner
                // spec): a planner-linked run reads the accent `In
                // progress` label on its row; a blocked Start under any
                // active run shows the row's inline red error instead
                // (day-planner 19.1) — the nav bar carries the title only.
                ToolbarItem(placement: .principal) {
                    Text(L10n.plannerTitle.text)
                        .font(.headline)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        isReordering.toggle()
                    } label: {
                        Label(
                            L10n.plannerReorder.text,
                            systemImage: isReordering ? "checkmark" : "arrow.up.arrow.down"
                        )
                    }
                    .accessibilityIdentifier("PlannerReorderButton")
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

    /// The persistent inline field (see `PlannerComposerRow`): Return
    /// prepends one task at the top, clears the draft, and focus never
    /// leaves; no visible Add button; a leading plus, a trailing clear
    /// button, and — on an empty draft — Return dismisses the keyboard
    /// (the sole dismiss path).
    private var composer: some View {
        PlannerComposerRow(
            vm: vm,
            focused: $composerFocused,
            editing: $composerEditing
        )
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
            // The task rows carry no section header (day-planner 10.2):
            // a fresh row expands in at the top (see `PlannerRowInsertion`;
            // opacity-only under Reduce Motion). Row taps open the task
            // editor sheet (day-planner 14.1) — the row never renames
            // inline, and completed taps are a no-op (day-planner 17.2,
            // gated in `beginEdit`). Row swipes carry labeled pills with
            // icon + text (day-planner 11.2): trailing-side delete into
            // the durable undo buffer (never for the running linked
            // task), leading-side complete/reopen with the toggle
            // semantics — no behavior change. There is no Edit button and
            // no edit-mode deletion UI (day-planner 18.2): reordering runs
            // through the dedicated reorder control, which only surfaces
            // the list's `onMove` handles — no delete affordances appear in
            // reorder mode. A disabled Start tap (a run is active) shows
            // the row's inline red error and plays the reject haptic
            // instead of starting (day-planner 19.1).
            ForEach(Array(vm.snapshot.tasks.enumerated()), id: \.element.id) { index, task in
                PlannerTaskRow(
                    task: task,
                    categories: vm.rowCategories(for: task),
                    timerActive: vm.timerActive,
                    isRunning: vm.linkedTaskID == task.id,
                    onToggle: { Task { await vm.toggleComplete(task) } },
                    onEdit: { vm.beginEdit(task) },
                    onStart: {
                        if vm.startShouldReject(task) {
                            vm.rejectDisabledStart(for: task)
                            if !reduceMotion {
                                blockedStartShakeAttempts += 1
                            }
                        } else if await vm.startTask(task) {
                            onStartActive()
                        }
                    },
                    blockedError: vm.blockedStartTaskID == task.id ? L10n.plannerBlockedStart.text : nil,
                    shakeAttempts: blockedStartShakeAttempts
                )
                .swipeActions(edge: .trailing) {
                    if vm.linkedTaskID != task.id {
                        Button(role: .destructive) {
                            Task { await vm.delete(at: IndexSet(integer: index)) }
                        } label: {
                            Label(L10n.entryDeleteConfirm.text, systemImage: "trash")
                        }
                        .tint(Theme.danger)
                    }
                }
                .swipeActions(edge: .leading) {
                    Button {
                        Task { await vm.toggleComplete(task) }
                    } label: {
                        if task.completedOn == nil {
                            Label(L10n.plannerMarkDone.text, systemImage: "checkmark")
                        } else {
                            Label(L10n.plannerReopen.text, systemImage: "arrow.uturn.backward")
                        }
                    }
                    .tint(Theme.accentPrimary)
                }
            }
            .onMove { source, destination in Task { await vm.move(from: source, to: destination) } }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .accessibilityIdentifier("PlannerTaskList")
        // Reorder mode surfaces drag handles with no delete affordances:
        // without an on-delete handler the framework shows handles only.
        .environment(\.editMode, .constant(isReordering ? .active : .inactive))
        // The task editor sheet (day-planner 14.1/15.1, unified 16.3): the
        // manual entry form minus Start/End — Name entry, ordered
        // Categories, Notes in the same order/cards/validation/save gate.
        // Tapping a row is the only entry point — the row itself never
        // renames inline.
        .sheet(item: $vm.editingTask) { _ in
            PlannerTaskEditorSheet(vm: vm)
        }
    }

    /// The chips line (day-planner 9.1, gap 10.2, placeholder 11.3, icons
    /// + staging 16.2): one horizontally scrollable row of recent-activity
    /// chips pinned between the composer and the keyboard — the last VStack
    /// slot, so the keyboard's safe-area inset lands under it with a
    /// `spacingSmall` breathing gap, and the chips never sit flush on the
    /// keyboard. Visible only while the keyboard is open; an empty draft
    /// shows the full capped strip, typing prefix-filters it, and tapping a
    /// chip fills the composer with its exact text (no task created, no
    /// timer started) while staging the Recent's full category set for the
    /// next submit — the line then shows only the selected chip until
    /// typing resumes. Each chip shows its Recent's first category icon. A
    /// draft that matches nothing shows the localized no-match placeholder
    /// instead of an empty strip. The slot stays mounted at one chip row
    /// while the keyboard is open even when the filter matches nothing (the
    /// placeholder — or a hidden prototype for a blank filter — holds the
    /// row height), so filter changes only swap chips inside the line and
    /// never move the composer or the list above.
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
                        if vm.showsChipsNoMatch {
                            // A non-blank draft with zero matches: the
                            // localized placeholder holds the row (same
                            // text metrics as a chip, no capsule — it is
                            // not tappable).
                            Text(L10n.plannerNoMatch.text)
                                .font(.subheadline)
                                .foregroundStyle(Theme.textSecondary)
                                .lineLimit(1)
                                .padding(.horizontal, Theme.spacingMedium)
                                .padding(.vertical, 12)
                                .frame(minHeight: Theme.minTapArea)
                                .accessibilityIdentifier("PlannerChipsNoMatch")
                        } else {
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
                }
                .padding(.horizontal, Theme.screenHorizontalPadding)
                .frame(minHeight: Theme.minTapArea)
            }
            .frame(minHeight: Theme.minTapArea)
            // Breathing gap above the keyboard (day-planner 10.2): a
            // spacing token, never a magic number. Constant while the line
            // is mounted, so it never moves the composer or the list.
            .padding(.bottom, Theme.spacingSmall)
            .accessibilityIdentifier("PlannerChips")
        }
    }

    /// One chip: the Recent's first category icon plus its exact text
    /// (day-planner 16.2; text-only when the Recent carries no resolvable
    /// first category). Tapping fills the composer with the exact text and
    /// stages the Recent's full set for the created task, playing the
    /// selection haptic (day-planner 17.3). The isolated staged chip
    /// renders in the filled-accent selected presentation (day-planner
    /// 17.1, Track Recents parity: accent fill, on-accent content, the
    /// `.isSelected` trait) instead of the plain capsule.
    private func chip(_ recent: RecentEntry) -> some View {
        let selected = vm.isSelectedChip(recent)
        return Button {
            vm.fillFromChip(recent)
            composerFocused = true
        } label: {
            HStack(spacing: Theme.spacingExtraSmall) {
                if let symbol = vm.chipIconSymbol(for: recent) {
                    Image(systemName: symbol)
                        .font(.caption)
                        .foregroundStyle(selected ? Theme.textOnAccent : Theme.textSecondary)
                        .accessibilityHidden(true)
                }
                Text(recent.activityText)
                    .font(.subheadline)
                    .lineLimit(1)
                    .foregroundStyle(selected ? Theme.textOnAccent : Theme.textPrimary)
            }
            .padding(.horizontal, Theme.spacingMedium)
            .padding(.vertical, 12)
            .frame(minHeight: Theme.minTapArea)
            .background(selected ? Theme.accentPrimary : Theme.backgroundSecondary)
            .clipShape(Capsule())
            .overlay {
                Capsule().stroke(
                    selected ? Theme.accentPrimary : Theme.hairline,
                    lineWidth: 0.7
                )
            }
        }
        .buttonStyle(.plain)
        .accessibilityValue(selected ? L10n.undoSelected.text : "")
        .accessibilityAddTraits(selected ? .isSelected : [])
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
