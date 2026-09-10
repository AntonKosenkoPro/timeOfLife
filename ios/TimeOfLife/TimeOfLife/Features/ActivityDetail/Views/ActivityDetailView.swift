import SwiftUI

/// The activity detail sheet presented from a History entry tap
/// (activity-detail-sheet spec): toolbar with the activity name and the
/// "Edit activity" route stacking the existing `ActivityEditorView`; a body
/// header showing each activity field exactly once (icon, categories with
/// icons, notes); a divider-separated Entries section whose header carries
/// the all-time total; and the activity's complete day-grouped committed
/// entry list on tappable entry-only rows (each opens the unified entry
/// form: EDIT for manual entries, LOCKED for imported ones). Presented at medium detent,
/// draggable to large. The running session never appears (its entry is
/// uncommitted). If the activity vanishes (cascade delete) the sheet
/// dismisses itself (design D6). The "Log time" action opens the Log Time
/// sheet pre-filled with the activity (manual-entry spec); a saved entry
/// appears in the Entries list after the sheet dismisses.
struct ActivityDetailView: View {
    @EnvironmentObject var container: AppContainer
    @Environment(\.undoManager)
    private var undoManager
    @StateObject private var vm: ActivityDetailViewModel
    @Environment(\.dismiss)
    private var dismiss
    @State private var editorActivity: Activity?
    /// The entry opened in the unified entry form (nil = none). EDIT mode
    /// for `manual` entries, LOCKED mode for imported ones
    /// (entry-editor spec).
    @State private var editingEntry: TimeEntry?
    /// Set after a stacked sheet dismisses so the next appear reloads
    /// identity, categories, entries, and total.
    @State private var needsReloadAfterSheet = false
    /// Presents the Log Time sheet pre-filled with this activity.
    @State private var isLogTimeActive = false

    init(store: LocalStore, activityID: String, undoBuffer: UndoBufferStore? = nil) {
        _vm = StateObject(wrappedValue: ActivityDetailViewModel(
            store: store,
            activityID: activityID,
            undoBuffer: undoBuffer
        ))
    }

    var body: some View {
        NavigationView {
            ScrollView {
                LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                    header
                    entriesSectionHeader
                    entriesList
                }
                .padding(.horizontal, Theme.spacingMedium)
            }
            .background(Theme.backgroundPrimary.ignoresSafeArea())
            .navigationTitle(vm.activity?.name ?? "")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(L10n.activityDetailLogTime.text) {
                        isLogTimeActive = true
                    }
                    .disabled(vm.activity == nil)
                    .accessibilityIdentifier("ActivityDetailLogTimeButton")
                }
                ToolbarItem(placement: .primaryAction) {
                    Button(L10n.activityDetailEditActivity.text) {
                        editorActivity = vm.activity
                    }
                    .disabled(vm.activity == nil)
                    .accessibilityIdentifier("ActivityDetailEditButton")
                }
            }
        }
        .navigationViewStyle(.stack)
        .task {
            await vm.load()
            await vm.registerSystemUndo(with: undoManager)
        }
        // Shake-to-undo uses the DEFAULT system Undo confirmation (U7):
        // shaking surfaces the Undo prompt and confirming restores exactly
        // one entry — the most recent buffered deletion. Registration is
        // cleared-then-single, so one shake+confirm can never restore two.
        // The passive first-responder host below is what lets the shake
        // reach the undo manager at all on this sheet (no editable text
        // holds focus here); it deliberately handles NO motion itself, so
        // the system shows its Undo prompt instead of restoring immediately.
        .background(ShakeFirstResponderHost(undoManager: undoManager))
        .onChange(of: needsReloadAfterSheet) { changed in
            guard changed else { return }
            needsReloadAfterSheet = false
            Task {
                await vm.load()
                await vm.registerSystemUndo(with: undoManager)
            }
        }
        .onChange(of: vm.activityIsGone) { gone in
            if gone { dismiss() }
        }
        .sheet(isPresented: $isLogTimeActive, onDismiss: reloadAfterSheet) {
            LogTimeView(
                service: container.timerService,
                initialActivity: vm.activity
            )
        }
        // The unified entry form presents as a full-screen cover (not a
        // third stacked sheet): EDIT for manual entries, LOCKED for
        // imported ones. Dismissal reloads identity/entries/total.
        .fullScreenCover(item: $editingEntry, onDismiss: reloadAfterSheet) { entry in
            LogTimeView(
                service: container.timerService,
                editing: entry
            )
        }
        .sheet(item: $editorActivity, onDismiss: reloadAfterEditor) { activity in
            ActivityEditorView(
                store: vm.editorStore,
                activity: activity,
                onSaved: { _ in
                    // Save closes the editor (spec: Save closes the editor);
                    // onDismiss reloads the sheet with the saved values.
                    editorActivity = nil
                },
                onCollision: { _ in
                    // The editor stays open with the draft intact; the
                    // editor's own error message surfaces the collision.
                }
            )
            .environmentObject(container)
        }
    }

    // MARK: - Header (each activity field exactly once; no name)

    private func reloadAfterEditor() {
        needsReloadAfterSheet = true
    }

    private func reloadAfterSheet() {
        needsReloadAfterSheet = true
    }

    @ViewBuilder private var header: some View {
        if vm.activity != nil {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: EntryRow.columnSpacing) {
                    Image(systemName: vm.icon)
                        .font(.title2)
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: EntryRow.iconColumnWidth)
                    VStack(alignment: .leading, spacing: Theme.spacingExtraSmall) {
                        categoriesLine
                        if let notes = vm.activity?.notes, !notes.isEmpty {
                            Text(notes)
                                .font(.subheadline)
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                }
                .padding(.vertical, Theme.spacingMedium)
                Divider()
            }
        }
    }

    /// "Categories:" label followed by each category's icon and name, or
    /// a localized "none" value when the activity has no categories.
    @ViewBuilder private var categoriesLine: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.spacingExtraSmall) {
            Text(L10n.activityDetailCategories.text + ":")
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
            if vm.categories.isEmpty {
                Text(L10n.activityDetailNoCategories.text)
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
            ForEach(Array(vm.categories.enumerated()), id: \.element.id) { index, category in
                HStack(spacing: 2) {
                    Image(systemName: CatalogIcon(validated: category.icon).displaySymbol)
                    Text(category.name)
                    if index < vm.categories.count - 1 {
                        Text(",")
                    }
                }
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
            }
        }
    }

    // MARK: - Entries (day-grouped, inert entry-only rows)

    @ViewBuilder private var entriesSectionHeader: some View {
        SectionHeader(title: L10n.activityDetailEntries.text) {
            Text(String(
                format: L10n.activityDetailTotal.text,
                locale: .current,
                vm.totalText
            ))
            .font(.caption)
            .foregroundStyle(Theme.textSecondary)
            .monospacedDigit()
        }
        .padding(.horizontal, Theme.spacingMedium)
        .background(Theme.backgroundPrimary)
    }

    @ViewBuilder private var entriesList: some View {
        ForEach(vm.dayGroups) { group in
            Section {
                ForEach(group.entries) { entry in
                    Button {
                        editingEntry = entry
                    } label: {
                        ActivityEntryRow(
                            timeRangeText: vm.timeRangeText(for: entry),
                            provenanceName: vm.provenanceName(for: entry),
                            durationText: vm.durationText(for: entry)
                        )
                        // Full-row tap target: the row's Spacer gaps render
                        // nothing, so without an explicit shape only the
                        // texts hit-test. Stretch + Rectangle makes the
                        // whole item tappable (History rows do the same).
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("ActivityEntryRow(\(entry.id))")
                }
            } header: {
                SectionHeader(title: group.label)
                    .padding(.horizontal, Theme.spacingMedium)
                    .background(Theme.backgroundPrimary)
            }
        }
    }
}

/// Passive motion first-responder host for the system shake-to-undo (U7).
/// This sheet has no editable text to hold focus, so without this nothing
/// is first responder and shakes never reach the undo manager. The view is
/// transparent and background-placed (never intercepts touches), becomes
/// first responder when it enters the window (re-acquiring after
/// full-screen-cover dismissals via `updateUIView`), and deliberately
/// handles NO motion itself — the shake propagates so the SYSTEM shows its
/// default Undo prompt for the action `registerSystemUndo` registered.
///
/// It overrides `undoManager` to return the SAME instance the view
/// registers with (`@Environment(\.undoManager)`): without this the shake
/// resolves up the responder chain (typically the window's manager), which
/// holds no registrations, so the system prompt never appears even though
/// the environment manager `canUndo`.
private struct ShakeFirstResponderHost: UIViewRepresentable {
    var undoManager: UndoManager?

    func makeUIView(context: Context) -> HostView {
        let view = HostView()
        view.backgroundColor = .clear
        view.storedUndoManager = undoManager
        return view
    }

    func updateUIView(_ uiView: HostView, context: Context) {
        uiView.storedUndoManager = undoManager
        if uiView.window != nil, !uiView.isFirstResponder {
            DispatchQueue.main.async {
                _ = uiView.becomeFirstResponder()
            }
        }
    }

    final class HostView: UIView {
        var storedUndoManager: UndoManager?
        override var canBecomeFirstResponder: Bool { true }
        override var undoManager: UndoManager? {
            storedUndoManager ?? super.undoManager
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            if window != nil {
                DispatchQueue.main.async { [weak self] in
                    _ = self?.becomeFirstResponder()
                }
            }
        }
    }
}

#if DEBUG
#Preview("Activity detail") {
    let container = AppContainer.production()
    ActivityDetailView(store: container.localStore, activityID: "act-1")
        .environmentObject(container)
}

#Preview("Activity detail — RU locale") {
    let container = AppContainer.production()
    ActivityDetailView(store: container.localStore, activityID: "act-1")
        .environment(\.locale, .init(identifier: "ru"))
        .environmentObject(container)
}
#endif
