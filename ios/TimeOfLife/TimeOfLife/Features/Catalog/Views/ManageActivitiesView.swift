import SwiftUI

/// Manage Activities screen (F8/F10/U8).
struct ManageActivitiesView: View {
    @StateObject var vm: ManageActivitiesViewModel
    @EnvironmentObject var container: AppContainer
    private let embeddedInNavigation: Bool
    @State private var showAddSheet = false
    @State private var editingActivity: Activity?

    init(vm: ManageActivitiesViewModel, embeddedInNavigation: Bool = false) {
        _vm = StateObject(wrappedValue: vm)
        self.embeddedInNavigation = embeddedInNavigation
    }

    var body: some View {
        Group {
            if embeddedInNavigation {
                content
            } else {
                if #available(iOS 16, *) {
                    NavigationStack {
                        content
                    }
                } else {
                    NavigationView {
                        content
                    }
                    .navigationViewStyle(.stack)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.backgroundPrimary.ignoresSafeArea())
        .task { await vm.loadActivities() }
    }

    private var content: some View {
        Group {
            if vm.activities.isEmpty {
                EmptyState(
                    icon: "plus.circle.fill",
                    title: L10n.manageActivitiesEmptyTitle.text,
                    subtitle: L10n.manageActivitiesEmptySubtitle.text)
            } else {
                List {
                    ForEach(vm.activities) { activity in
                        ActivityRow(activity: activity, categories: []) {
                            editingActivity = activity
                        }
                        .swipeActions {
                            Button(role: .destructive) {
                                Task { await vm.delete(activity) }
                            } label: {
                                Label(L10n.undoButton.text, systemImage: "trash")
                            }
                            .accessibilityIdentifier("ActivityDeleteButton(\(activity.id))")
                        }
                    }
                }
                .listStyle(.plain)
                .background(Theme.backgroundPrimary)
                .accessibilityIdentifier("ManageActivitiesList")
            }
        }
        .navigationTitle(L10n.manageActivitiesTitle.text)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showAddSheet = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityIdentifier("ManageActivitiesAddButton")
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    container.navigation.push(.manageCategories)
                } label: {
                    Image(systemName: "slider.horizontal.3")
                }
                .accessibilityIdentifier("ManageActivitiesCategoriesButton")
            }
        }
        .sheet(isPresented: $showAddSheet) {
            if let store = container.localStoreForCatalog {
                ActivityEditorView(
                    vm: ActivityEditorViewModel(
                        localStore: store,
                        syncCoordinator: container.syncCoordinator))
            }
        }
        .sheet(item: $editingActivity) { activity in
            if let store = container.localStoreForCatalog {
                ActivityEditorView(
                    vm: ActivityEditorViewModel(
                        localStore: store,
                        syncCoordinator: container.syncCoordinator,
                        editingActivity: activity))
            }
        }
        .onChange(of: showAddSheet) { isPresented in
            if !isPresented {
                Task { await vm.loadActivities() }
            }
        }
        .onChange(of: editingActivity) { activity in
            if activity == nil {
                Task { await vm.loadActivities() }
            }
        }
        .onChange(of: vm.showDeleteScope) { _ in
            if !vm.showDeleteScope { vm.cancelDelete() }
        }
        .safeAreaInset(edge: .bottom) {
            if let toast = vm.undoToast {
                UndoToast(
                    message: toast.message,
                    onUndo: { Task { await vm.performUndo() } },
                    onDismiss: { vm.dismissUndo() }
                )
                .padding(.horizontal, Theme.spacingMedium)
                .padding(.bottom, Theme.spacingSmall)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .background(
            ScopeConfirmation(
                isPresented: $vm.showDeleteScope,
                entryCount: vm.pendingEntryCount,
                onDeleteAll: { Task { await vm.deleteActivityAndEntries() } },
                onDeleteEntryOnly: { Task { await vm.deleteEntryOnly() } },
                onCancel: { vm.cancelDelete() })
        )
    }
}
