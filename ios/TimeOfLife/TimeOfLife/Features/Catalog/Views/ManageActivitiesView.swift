import SwiftUI

struct ManageActivitiesView: View {
    @ObservedObject var vm: ManageActivitiesViewModel
    @EnvironmentObject private var container: AppContainer

    var body: some View {
        // This screen is a destination of the signed-in AppStack. Keeping a
        // second navigation container here causes route state to fight the
        // parent container and can immediately pop the screen.
        contentWithToolbar
        .background(Theme.backgroundPrimary.ignoresSafeArea())
        .background(ShakeMotionBridge())
        .task { await vm.load() }
        .sheet(item: $vm.editorSheet) { state in
            let mode: ActivityEditorMode = {
                switch state {
                case .create: return .createFromManage
                case let .edit(activity): return .edit(activity)
                }
            }()
            let editor = ActivityEditorViewModel(
                mode: mode,
                store: container.catalogStore,
                repository: container.catalogRepository,
                service: container.catalogService,
                connectivity: container.connectivity,
                availableCategories: vm.categories
            )
            ActivityEditorView(vm: editor)
                .onDisappear { Task { await vm.load() } }
        }
        .overlay(alignment: .bottom) {
            if let undo = vm.undoToast {
                UndoToast(
                    message: undo.message,
                    onUndo: { Task { await vm.performUndo() } },
                    onDismiss: { vm.dismissUndo() }
                )
                .padding(.bottom, Theme.spacingSmall)
            }
        }
        .onShake { vm.onShake() }
    }

    private var contentWithToolbar: some View {
        Group {
            if vm.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Theme.backgroundPrimary)
            } else if vm.activities.isEmpty {
                EmptyState(
                    icon: "plus.circle.fill",
                    title: L10n.manageActivitiesEmptyTitle.text,
                    subtitle: L10n.manageActivitiesEmptySubtitle.text
                )
            } else {
                List {
                    ForEach(vm.activities) { activity in
                        ActivityRow(activity: activity, categories: vm.categories(for: activity)) {
                            vm.edit(activity)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                Task { await vm.requestDelete(activity) }
                            } label: {
                                Label(L10n.deleteButton.text, systemImage: "trash")
                            }
                            .tint(Theme.danger)
                            .accessibilityIdentifier("ActivityRowDelete(\(activity.id))")
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
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    container.navigation.push(.manageCategories)
                } label: {
                    Image(systemName: "tag.fill")
                }
                .accessibilityLabel(L10n.manageActivitiesCategories.text)
                .accessibilityIdentifier("ManageActivitiesCategoriesButton")
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { vm.create() } label: {
                    Image(systemName: "plus")
                }
                .accessibilityIdentifier("ManageActivitiesAddButton")
            }
        }
        .alert(
            L10n.deleteActivityTitle.text,
            isPresented: $vm.showDeleteConfirmation,
            presenting: vm.pendingDelete
        ) { activity in
            Button(L10n.deleteActivityTitle.text, role: .destructive) {
                Task { await vm.performDelete(activity, scope: .all) }
            }
            Button(L10n.deleteActivityCancel.text, role: .cancel) {}
        } message: { _ in
            Text(L10n.deleteActivityMessage.text(0))
        }
        .background(
            ScopeConfirmation(
                isPresented: $vm.showDeleteScope,
                entryCount: vm.entryCount(for: vm.pendingDelete),
                onDeleteAll: {
                    if let activity = vm.pendingDelete { Task { await vm.performDelete(activity, scope: .all) } }
                },
                onDeleteEntryOnly: {
                    if let activity = vm.pendingDelete { Task { await vm.performDelete(activity, scope: .entryOnly) } }
                },
                onCancel: { vm.pendingDelete = nil }
            )
        )
        .safeAreaInset(edge: .bottom) {
            if let error = vm.errorMessage {
                ErrorBanner(message: error, accessibilityId: "ManageActivitiesErrorBanner")
                    .padding(.vertical, Theme.spacingSmall)
                    .background(Theme.backgroundPrimary)
            }
        }
    }
}

#if DEBUG

private func previewActivity(_ name: String, lastUsedAt: Date?) -> Activity {
    Activity(
        id: UUID(), name: name, color: .blue, icon: .book, notes: nil,
        lastUsedAt: lastUsedAt, categoryIds: [], createdAt: Date(), updatedAt: Date()
    )
}

#Preview("Manage Activities — EN Light") {
    let container = AppContainer.production()
    let vm = ManageActivitiesViewModel(
        store: container.catalogStore,
        service: container.catalogService,
        repository: container.catalogRepository,
        undoBuffer: container.undoBuffer,
        entryCounter: container.activityEntryCounter
    )
    vm.activities = [previewActivity("Reading", lastUsedAt: Date())]
    return ManageActivitiesView(vm: vm).environmentObject(container)
}

#Preview("Manage Activities — Empty EN Light") {
    let container = AppContainer.production()
    let vm = ManageActivitiesViewModel(
        store: container.catalogStore,
        service: container.catalogService,
        repository: container.catalogRepository,
        undoBuffer: container.undoBuffer,
        entryCounter: container.activityEntryCounter
    )
    return ManageActivitiesView(vm: vm).environmentObject(container)
}

#Preview("Manage Activities — Populated RU Dark") {
    let container = AppContainer.production()
    let vm = ManageActivitiesViewModel(
        store: container.catalogStore,
        service: container.catalogService,
        repository: container.catalogRepository,
        undoBuffer: container.undoBuffer,
        entryCounter: container.activityEntryCounter
    )
    vm.activities = [previewActivity("Чтение", lastUsedAt: Date())]
    return ManageActivitiesView(vm: vm)
        .environmentObject(container)
        .preferredColorScheme(.dark)
        .environment(\.locale, .init(identifier: "ru"))
}

#Preview("Manage Activities — Empty RU Dark") {
    let container = AppContainer.production()
    let vm = ManageActivitiesViewModel(
        store: container.catalogStore,
        service: container.catalogService,
        repository: container.catalogRepository,
        undoBuffer: container.undoBuffer,
        entryCounter: container.activityEntryCounter
    )
    return ManageActivitiesView(vm: vm)
        .environmentObject(container)
        .preferredColorScheme(.dark)
        .environment(\.locale, .init(identifier: "ru"))
}

#endif
