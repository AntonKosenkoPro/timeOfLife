import SwiftUI

/// Manage Categories screen (F2/F6/U8).
struct ManageCategoriesView: View {
    @StateObject var vm: ManageCategoriesViewModel
    @EnvironmentObject var container: AppContainer
    private let embeddedInNavigation: Bool
    @State private var showAddSheet = false
    @State private var editingCategory: Category?

    init(vm: ManageCategoriesViewModel, embeddedInNavigation: Bool = false) {
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
        .task { await vm.loadCategories() }
    }

    private var content: some View {
        Group {
            if vm.categories.isEmpty {
                EmptyState(
                    icon: "tag",
                    title: L10n.manageCategoriesEmptyTitle.text,
                    subtitle: L10n.manageCategoriesEmptySubtitle.text)
            } else {
                List {
                    ForEach(vm.categories) { category in
                        CategoryRow(category: category) {
                            editingCategory = category
                        }
                        .swipeActions {
                            Button(role: .destructive) {
                                vm.delete(category)
                            } label: {
                                Label(L10n.undoButton.text, systemImage: "trash")
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .background(Theme.backgroundPrimary)
                .accessibilityIdentifier("ManageCategoriesList")
            }
        }
        .navigationTitle(L10n.manageCategoriesTitle.text)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showAddSheet = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityIdentifier("ManageCategoriesAddButton")
            }
        }
        .sheet(isPresented: $showAddSheet) {
            if let store = container.localStoreForCatalog {
                CategoryEditorView(
                    vm: CategoryEditorViewModel(
                        localStore: store,
                        syncCoordinator: container.syncCoordinator))
            }
        }
        .sheet(item: $editingCategory) { category in
            if let store = container.localStoreForCatalog {
                CategoryEditorView(
                    vm: CategoryEditorViewModel(
                        localStore: store,
                        syncCoordinator: container.syncCoordinator,
                        editingCategory: category))
            }
        }
        .onChange(of: vm.showDeleteConfirm) { _ in
            if !vm.showDeleteConfirm { vm.cancelDelete() }
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
        .confirmationDialog(
            L10n.deleteCategoryTitle.text,
            isPresented: $vm.showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button(L10n.deleteCategoryConfirm.text, role: .destructive) {
                Task { await vm.confirmDelete() }
            }
            Button(L10n.deleteCategoryCancel.text, role: .cancel) {
                vm.cancelDelete()
            }
        } message: {
            if let category = vm.pendingDelete {
                Text(String(format: L10n.deleteCategoryMessage.text, category.name))
            }
        }
    }
}
