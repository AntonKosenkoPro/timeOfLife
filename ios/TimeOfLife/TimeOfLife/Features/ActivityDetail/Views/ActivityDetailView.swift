import SwiftUI

/// The activity detail sheet presented from a History entry tap
/// (activity-detail-sheet spec): toolbar with the activity name and the
/// "Edit activity" route stacking the existing `ActivityEditorView`; a body
/// header showing each activity field exactly once (icon, categories with
/// icons, notes); a divider-separated Entries section whose header carries
/// the all-time total; and the activity's complete day-grouped committed
/// entry list on inert entry-only rows. Presented at medium detent,
/// draggable to large. The running session never appears (its entry is
/// uncommitted). If the activity vanishes (cascade delete) the sheet
/// dismisses itself (design D6). The "Log time" action opens the Log Time
/// sheet pre-filled with the activity (manual-entry spec); a saved entry
/// appears in the Entries list after the sheet dismisses.
struct ActivityDetailView: View {
    @EnvironmentObject var container: AppContainer
    @StateObject private var vm: ActivityDetailViewModel
    @Environment(\.dismiss)
    private var dismiss
    @State private var editorActivity: Activity?
    /// Set after a stacked sheet dismisses so the next appear reloads
    /// identity, categories, entries, and total.
    @State private var needsReloadAfterSheet = false
    /// Presents the Log Time sheet pre-filled with this activity.
    @State private var isLogTimeActive = false

    init(store: LocalStore, activityID: String) {
        _vm = StateObject(wrappedValue: ActivityDetailViewModel(
            store: store,
            activityID: activityID
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
        .task { await vm.load() }
        .onChange(of: needsReloadAfterSheet) { changed in
            guard changed else { return }
            needsReloadAfterSheet = false
            Task { await vm.load() }
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
                    ActivityEntryRow(
                        timeRangeText: vm.timeRangeText(for: entry),
                        provenanceName: vm.provenanceName(for: entry),
                        durationText: vm.durationText(for: entry)
                    )
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
