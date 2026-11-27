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
    /// UIKit editing state of the composer (day-planner 11.1): drives the
    /// trailing clear button — the `composerFocused` flag only issues
    /// focus requests and never observes UIKit-side focus back.
    @State private var composerEditing = false
    var body: some View {
        content
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // Mail-style section subtitle (day-planner 11.1): the
                // running-timer notice lives under the Today title in the
                // nav bar — never as an inline caption in the list.
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 0) {
                        Text(L10n.plannerTitle.text)
                            .font(.headline)
                        if vm.timerActive {
                            Text(L10n.plannerTimerActive.text)
                                .font(.caption)
                                .foregroundStyle(Theme.textSecondary)
                                .accessibilityIdentifier("PlannerTimerSubtitle")
                        }
                    }
                }
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

    /// The persistent inline field: Return prepends one task at the top,
    /// clears the draft, and focus never leaves — the UIKit-backed field
    /// declines the Return default resign at dispatch (day-planner 7.1),
    /// so the keyboard never animates away no matter how slow the
    /// store/reload round-trip is. There is no visible Add button
    /// (day-planner 11.1): submission runs through Return or the
    /// composer's Add accessibility action, so VoiceOver retains a
    /// submit path. A trailing clear button (the Track × grammar — small
    /// dim trailing × while editing) empties the draft without
    /// dismissing the keyboard or losing focus; its visibility follows
    /// the UIKit editing state mirrored from the field delegate (ground
    /// truth), not the `composerFocused` flag (which only issues focus
    /// requests). The composer never
    /// unmounts and no layout jumps. The field sits in the shared
    /// `FieldCard` chrome (secondary background against the primary
    /// page, `minTapArea` minimum height), so it reads as a card apart
    /// from the list; the representable keeps its stable identity
    /// inside the card, so first-responder survival is unchanged.
    private var composer: some View {
        FieldCard {
            HStack(spacing: Theme.spacingSmall) {
                PlannerComposerField(
                    text: $vm.draft,
                    placeholder: L10n.plannerComposerPlaceholder.text,
                    focused: $composerFocused,
                    accessibilityIdentifier: "PlannerComposerField",
                    onReturn: { Task { await vm.submit() } },
                    onEditingChanged: { composerEditing = $0 }
                )
                .accessibilityAction(named: Text(L10n.plannerAdd.text)) {
                    Task { await vm.submit() }
                }
                if ClearButtonVisibility.shouldShow(isFocused: composerEditing, text: vm.draft) {
                    ClearTextButton(
                        action: {
                            vm.draft = ""
                            composerFocused = true
                        },
                        accessibilityId: "PlannerComposerClear"
                    )
                }
            }
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
            // The task rows carry no section header (day-planner 10.2):
            // a fresh row expands in at the top (see `PlannerRowInsertion`;
            // opacity-only under Reduce Motion). Row taps open the task
            // editor sheet (day-planner 14.1) — the row never renames
            // inline. Row swipes carry labeled pills with icon + text
            // (day-planner 11.2): trailing-side delete into the durable
            // undo buffer, leading-side complete/reopen with the toggle
            // semantics — no behavior change.
            ForEach(Array(vm.snapshot.tasks.enumerated()), id: \.element.id) { index, task in
                PlannerTaskRow(
                    task: task,
                    categories: vm.rowCategories(for: task),
                    timerActive: vm.timerActive,
                    isRunning: vm.linkedTaskID == task.id,
                    onToggle: { Task { await vm.toggleComplete(task) } },
                    onEdit: { vm.beginEdit(task) },
                    onStart: {
                        if await vm.startTask(task) { onStartActive() }
                    }
                )
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        Task { await vm.delete(at: IndexSet(integer: index)) }
                    } label: {
                        Label(L10n.entryDeleteConfirm.text, systemImage: "trash")
                    }
                    .tint(Theme.danger)
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
            .onDelete { offsets in Task { await vm.delete(at: offsets) } }
            .onMove { source, destination in Task { await vm.move(from: source, to: destination) } }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .accessibilityIdentifier("PlannerTaskList")
        // The task editor sheet (day-planner 14.1/15.1): Name + ordered
        // Categories + Notes in Log Time sheet grammar. Tapping a row is
        // the only entry point — the row itself never renames inline.
        .sheet(item: $vm.editingTask) { _ in
            PlannerTaskEditorSheet(vm: vm)
        }
    }

    /// The chips line (day-planner 9.1, gap 10.2, placeholder 11.3): one
    /// horizontally scrollable row of recent-activity chips pinned between
    /// the composer and the keyboard — the last VStack slot, so the
    /// keyboard's safe-area inset lands under it with a `spacingSmall`
    /// breathing gap, and the chips never sit flush on the keyboard.
    /// Visible only while the keyboard is open; an empty draft shows the
    /// full capped strip, typing prefix-filters it, and tapping a chip
    /// fills the composer with its exact text (no task created, no timer
    /// started). A draft that matches nothing shows the localized
    /// no-match placeholder instead of an empty strip. The slot stays
    /// mounted at one chip row while the keyboard is open even when the
    /// filter matches nothing (the placeholder — or a hidden prototype
    /// for a blank filter — holds the row height), so filter changes
    /// only swap chips inside the line and never move the composer or
    /// the list above.
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
