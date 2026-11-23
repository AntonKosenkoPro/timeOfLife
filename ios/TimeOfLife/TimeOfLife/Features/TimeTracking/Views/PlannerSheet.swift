import SwiftUI

/// The Stage 1 day-planner sheet (day-planner spec): a separate resizable
/// bottom sheet opened from the Track toolbar, never inline in the Track
/// layout. Browsing never touches Track state; only an explicit task-name
/// tap prepares the Track name (with empty categories/notes), and Start
/// stays a separate explicit action.
///
/// Lifecycle: the sheet owns a lazily created `PlannerViewModel` (no planner
/// reads ride the launch-gate `TrackSnapshot`). Reconciliation runs on open,
/// on active-account foreground/resume, and at local-day or time-context
/// changes while the sheet is open and active — never via a background task
/// or a hidden-sheet midnight timer. Sign-out unmounts the shell (and with
/// it this sheet); stale cross-account completions are fenced at the
/// store/VM generation level.
struct PlannerSheet: View {
    @ObservedObject var trackVM: TrackViewModel
    @StateObject private var plannerVM: PlannerViewModel
    @Environment(\.dismiss)
    private var dismiss
    /// The add field's keyboard focus (day-planner Enter rule): browsing
    /// opens WITHOUT focus; submitting via Enter/Add restores focus to the
    /// field for the next task, on success and on failure alike. Only
    /// explicit Done or system dismissal resigns it.
    @FocusState private var addFieldFocused: Bool

    init(store: LocalStore, trackVM: TrackViewModel, calendar: Calendar = .current) {
        _plannerVM = StateObject(wrappedValue: PlannerViewModel(store: store, calendar: calendar))
        self.trackVM = trackVM
    }

    var body: some View {
        NavigationStack {
            sheetContent
                .navigationTitle(L10n.plannerTitle.text)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(L10n.plannerDone.text) { dismiss() }
                            .accessibilityIdentifier("PlannerDoneButton")
                    }
                }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        // Reconciliation triggers (day-planner D4): open, active-account
        // foreground/resume, and local-day or time-context changes while the
        // sheet is open and active. The resume signal implies a foreground
        // return (AppShellView precedent); no background task or hidden-sheet
        // midnight timer is introduced.
        .task { await plannerVM.open() }
        .onReceive(NotificationCenter.default.publisher(for: DatabaseSuspension.didResumeNotification)) { _ in
            Task { await plannerVM.reconcileActive() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
            Task { await plannerVM.reconcileActive() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange)) { _ in
            Task { await plannerVM.reconcileActive() }
        }
        // One destructive confirmation naming the task; Cancel preserves it.
        .alert(
            L10n.plannerRemoveTitle.text,
            isPresented: removalBinding,
            presenting: plannerVM.pendingRemoval
        ) { task in
            Button(L10n.plannerRemoveConfirm.text, role: .destructive) {
                Task { await plannerVM.confirmRemoval(task) }
            }
            .accessibilityIdentifier("PlannerRemoveConfirmButton")
            Button(L10n.plannerRemoveCancel.text, role: .cancel) {
                plannerVM.cancelRemoval()
            }
            .accessibilityIdentifier("PlannerRemoveCancelButton")
        } message: { task in
            Text(String(format: L10n.plannerRemoveMessage.text, task.text))
        }
    }

    /// Presents the removal confirmation while a task awaits it. The setter
    /// only clears (Cancel / swipe dismissal preserves the task).
    private var removalBinding: Binding<Bool> {
        Binding(
            get: { plannerVM.pendingRemoval != nil },
            set: { isPresented in if !isPresented { plannerVM.cancelRemoval() } }
        )
    }

    private var sheetContent: some View {
        VStack(spacing: 0) {
            addRow
                .padding(.horizontal, Theme.screenHorizontalPadding)
                .padding(.vertical, Theme.spacingSmall)
            Divider().background(Theme.hairline)
            checklistBody
        }
        .background(Theme.backgroundPrimary.ignoresSafeArea())
    }

    // MARK: - Add row

    /// Plain-text input plus an explicit Add action. Successful Adds clear
    /// the field and failed Adds preserve the input with an accessible
    /// explanation; both restore keyboard focus to the field for the next
    /// task (only Done/swipe dismissal resigns it). Management stays
    /// usable while a run is active — only name selection locks during runs.
    private var addRow: some View {
        VStack(alignment: .leading, spacing: Theme.spacingExtraSmall) {
            HStack(spacing: Theme.spacingSmall) {
                TextField(L10n.plannerAddPlaceholder.text, text: $plannerVM.inputText)
                    .textInputAutocapitalization(.sentences)
                    .disableAutocorrection(false)
                    .focused($addFieldFocused)
                    .frame(minHeight: Theme.minTapArea)
                    .accessibilityIdentifier("PlannerAddField")
                    .accessibilityLabel(L10n.plannerAddPlaceholder.text)
                    .onSubmit { Task { await submitAdd() } }
                Button(L10n.plannerAddButton.text) {
                    Task { await submitAdd() }
                }
                .frame(minHeight: Theme.minTapArea)
                .disabled(!plannerVM.canInteract)
                .accessibilityIdentifier("PlannerAddButton")
            }
            if let error = plannerVM.errorMessage, plannerVM.phase == .loaded {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(Theme.danger)
                    .accessibilityIdentifier("PlannerErrorMessage")
            }
        }
    }

    // MARK: - Checklist

    @ViewBuilder private var checklistBody: some View {
        switch plannerVM.phase {
        case .loading where plannerVM.tasks.isEmpty:
            VStack(spacing: Theme.spacingSmall) {
                Spacer()
                ProgressView()
                    .accessibilityLabel(L10n.plannerLoading.text)
                    .accessibilityIdentifier("PlannerLoadingIndicator")
                Text(L10n.plannerLoading.text)
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
            }
        case .failed where plannerVM.tasks.isEmpty:
            VStack(spacing: Theme.spacingSmall) {
                Spacer()
                Text(plannerVM.errorMessage ?? L10n.plannerLoadError.text)
                    .font(.body)
                    .foregroundStyle(Theme.textPrimary)
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("PlannerLoadErrorMessage")
                Button(L10n.plannerRetry.text) {
                    Task { await plannerVM.retry() }
                }
                .frame(minHeight: Theme.minTapArea)
                .accessibilityIdentifier("PlannerRetryButton")
                Spacer()
            }
            .padding(.horizontal, Theme.screenHorizontalPadding)
        case .loaded where plannerVM.tasks.isEmpty:
            VStack(spacing: Theme.spacingSmall) {
                Spacer()
                Text(L10n.plannerEmptyTitle.text)
                    .font(.headline)
                    .foregroundStyle(Theme.textPrimary)
                    .accessibilityIdentifier("PlannerEmptyTitle")
                Text(L10n.plannerEmptySubtitle.text)
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("PlannerEmptySubtitle")
                Spacer()
            }
            .padding(.horizontal, Theme.screenHorizontalPadding)
        default:
            List {
                ForEach(plannerVM.tasks) { task in
                    PlannerTaskRow(
                        task: task,
                        selectionDisabled: trackVM.state.isRunning || trackVM.state.isSaving,
                        actionsDisabled: !plannerVM.canInteract,
                        onToggle: { Task { await plannerVM.toggle(task) } },
                        onSelect: { Task { await selectTask(task) } },
                        onRemove: { plannerVM.pendingRemoval = task }
                    )
                    .listRowBackground(Theme.backgroundPrimary)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .accessibilityIdentifier("PlannerTaskList")
        }
    }

    /// Submits the add field and keeps keyboard focus in it for the next
    /// task: a successful Add clears the field and a failed Add preserves
    /// the input (PlannerViewModel owns both), and either way the field
    /// stays focused until explicit Done or system dismissal.
    private func submitAdd() async {
        await plannerVM.add()
        addFieldFocused = true
    }

    /// Prepares the task's name on Track with empty categories/notes and
    /// dismisses on success. Rechecks running/saving AND the bound account
    /// at execution time (not just at presentation time): a stale sheet
    /// never overwrites another account's prepared name.
    private func selectTask(_ task: PlannerTask) async {
        guard !trackVM.state.isRunning, !trackVM.state.isSaving else { return }
        let bound = await trackVM.service.store.boundUserID
        guard let bound, bound == plannerVM.expectedAccountID else { return }
        if trackVM.selectPlannerTask(task.text) {
            dismiss()
        }
    }
}

/// One checklist row (day-planner spec D6): the checkbox and the name are
/// independent actions with independent VoiceOver labels — toggling
/// completion never selects the Track name, and selecting never toggles
/// completion. Rows keep creation order (including checked rows) so a
/// checkbox target never moves during interaction.
private struct PlannerTaskRow: View {
    let task: PlannerTask
    let selectionDisabled: Bool
    let actionsDisabled: Bool
    let onToggle: () -> Void
    let onSelect: () -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: Theme.spacingSmall) {
            Button(action: onToggle) {
                Image(systemName: task.isCompleted ? "checkmark.square.fill" : "square")
                    .font(.system(size: 22))
                    .foregroundStyle(task.isCompleted ? Theme.accentPrimary : Theme.textSecondary)
                    .frame(width: Theme.minTapArea, height: Theme.minTapArea)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(actionsDisabled)
            .accessibilityLabel("\(task.text), \(task.isCompleted ? L10n.plannerToggleCompleted.text : L10n.plannerToggleNotCompleted.text)")
            .accessibilityIdentifier("PlannerTaskToggle_\(task.id)")
            Button(action: onSelect) {
                Text(task.text)
                    .font(.body)
                    .foregroundStyle(Theme.textPrimary)
                    .strikethrough(task.isCompleted)
                    .multilineTextAlignment(.leading)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(minHeight: Theme.minTapArea)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(selectionDisabled || actionsDisabled)
            .accessibilityLabel(task.text)
            .accessibilityHint(String(format: L10n.plannerSelectHint.text, task.text))
            .accessibilityIdentifier("PlannerTaskSelect_\(task.id)")
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(L10n.plannerRemoveLabel.text, role: .destructive, action: onRemove)
                .accessibilityIdentifier("PlannerTaskRemove_\(task.id)")
        }
        .contextMenu {
            Button(L10n.plannerRemoveLabel.text, role: .destructive, action: onRemove)
                .accessibilityIdentifier("PlannerTaskRemoveMenu_\(task.id)")
        }
    }
}

#if DEBUG
#Preview("Planner — Loaded") {
    PlannerSheetPreviewHost()
}

private struct PlannerSheetPreviewHost: View {
    @StateObject private var trackVM: TrackViewModel = {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("preview.sqlite")
        let bound = try? LocalStore(url: url, userID: "preview-user")
        return TrackViewModel(
            service: TimerService(store: bound ?? LocalStore()),
            connectivity: MockConnectivity(connected: true)
        )
    }()

    var body: some View {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("preview.sqlite")
        let store = (try? LocalStore(url: url, userID: "preview-user")) ?? LocalStore()
        return PlannerSheet(store: store, trackVM: trackVM)
    }
}
#endif
