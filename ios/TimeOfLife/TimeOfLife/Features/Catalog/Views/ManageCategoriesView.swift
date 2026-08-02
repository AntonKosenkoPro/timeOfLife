import SwiftUI

struct ManageCategoriesView: View {
    @ObservedObject var vm: ManageCategoriesViewModel
    @EnvironmentObject private var container: AppContainer

    var body: some View {
        contentWithToolbar
            .background(Theme.backgroundPrimary.ignoresSafeArea())
            .background(ShakeMotionBridge())
            .task { await vm.loadCategories() }
            .sheet(item: $vm.editorSheet) { state in
                CategoryEditorSheet(
                    viewModel: CategoryEditorViewModel(
                        mode: state.mode,
                        store: container.catalogStore,
                        repository: container.catalogRepository,
                        service: container.catalogService,
                        connectivity: container.connectivity
                    )
                ) { vm.editorDidFinish($0) }
            }
            .onShake { vm.onShake() }
    }

    private var contentWithToolbar: some View {
        VStack(spacing: 0) {
            if let message = vm.conflictMessage {
                ErrorBanner(message: message, accessibilityId: "ManageCategoriesConflictBanner")
                    .padding(.horizontal, Theme.screenHorizontalPadding)
                    .padding(.vertical, Theme.spacingSmall)
            }
            if let message = vm.errorMessage {
                ErrorBanner(message: message, accessibilityId: "ManageCategoriesErrorBanner")
                    .padding(.horizontal, Theme.screenHorizontalPadding)
                    .padding(.vertical, Theme.spacingSmall)
            }

            if vm.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if vm.categories.isEmpty {
                EmptyState(
                    icon: "tag",
                    title: L10n.manageCategoriesEmptyTitle.text,
                    subtitle: L10n.manageCategoriesEmptySubtitle.text
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                categoryList
            }
        }
        .navigationTitle(L10n.manageCategoriesTitle.text)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { vm.openCreate() } label: {
                    Image(systemName: "plus")
                }
                .accessibilityIdentifier("ManageCategoriesAddButton")
            }
        }
        .confirmationDialog(
            L10n.deleteCategoryTitle.text,
            isPresented: $vm.showDeleteConfirm
        ) {
            Button(L10n.deleteCategoryConfirm.text, role: .destructive) {
                guard let category = vm.pendingDelete else { return }
                Task { await vm.confirmDeletePending(category) }
            }
            Button(L10n.deleteCategoryCancel.text, role: .cancel) {}
        } message: {
            Text(String(format: L10n.deleteCategoryMessage.text, vm.pendingDelete?.name ?? ""))
        }
        .onChange(of: vm.showDeleteConfirm) { isPresented in
            if !isPresented { vm.dialogDismissed() }
        }
        .safeAreaInset(edge: .bottom) {
            if let toast = vm.undoToast {
                UndoToast(
                    message: toast.message,
                    onUndo: { vm.onShake() },
                    onDismiss: { vm.dismissUndo() }
                )
                .padding(.bottom, Theme.spacingSmall)
                .background(Theme.backgroundPrimary)
            }
        }
    }

    private var categoryList: some View {
        List {
            ForEach(vm.categories) { category in
                CategoryRow(category: category) {
                    vm.openEdit(category)
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        vm.confirmDelete(category)
                    } label: {
                        Label(L10n.deleteCategoryConfirm.text, systemImage: "trash")
                    }
                    .tint(Theme.danger)
                    .accessibilityIdentifier("CategoryRowDelete(\(category.id))")
                }
            }
        }
        .listStyle(.plain)
        .background(Theme.backgroundPrimary)
        .accessibilityIdentifier("ManageCategoriesList")
    }

}

private struct CategoryEditorSheet: View {
    @ObservedObject var viewModel: CategoryEditorViewModel
    let onResult: (CategorySaveResult) -> Void

    var body: some View {
        CategoryEditorView(vm: viewModel)
            .onChange(of: viewModel.onSaveResult) { result in
                guard let result else { return }
                onResult(result)
            }
    }
}

private extension CategoryEditorSheetState {
    var mode: CategoryEditorMode {
        switch self {
        case .create:
            return .create
        case let .edit(category):
            return .edit(category)
        }
    }
}

#if DEBUG

#Preview("Manage Categories — EN Light") {
    let container = AppContainer.production()
    let viewModel = ManageCategoriesViewModel(
        store: container.catalogStore,
        service: container.catalogService,
        repository: container.catalogRepository,
        undoBuffer: container.undoBuffer,
        connectivity: container.connectivity,
        initialCategories: [.sampleBlue, .sampleGreen, .sampleOrange]
    )
    return ManageCategoriesView(vm: viewModel)
        .environmentObject(container)
}

#Preview("Manage Categories — Empty RU Dark") {
    let container = AppContainer.production()
    let viewModel = ManageCategoriesViewModel(
        store: container.catalogStore,
        service: container.catalogService,
        repository: container.catalogRepository,
        undoBuffer: container.undoBuffer,
        connectivity: container.connectivity
    )
    return ManageCategoriesView(vm: viewModel)
        .environmentObject(container)
        .preferredColorScheme(.dark)
        .environment(\.locale, .init(identifier: "ru"))
}

#Preview("Manage Categories — Undo") {
    let container = AppContainer.production()
    let viewModel = ManageCategoriesViewModel(
        store: container.catalogStore,
        service: container.catalogService,
        repository: container.catalogRepository,
        undoBuffer: container.undoBuffer,
        connectivity: container.connectivity,
        initialCategories: [.sampleBlue]
    )
    viewModel.undoToast = UndoToastState(message: L10n.undoCategoryDeleted.text, startedAt: Date())
    return ManageCategoriesView(vm: viewModel)
        .environmentObject(container)
}

#endif
