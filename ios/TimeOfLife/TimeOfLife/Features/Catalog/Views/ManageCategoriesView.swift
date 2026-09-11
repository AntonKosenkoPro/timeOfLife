import SwiftUI

/// Manage Categories (Design/SCREENS/ManageCategories.md, category-
/// management D4): alphabetized list, empty state, Add/edit controls, and
/// the system Undo confirmation for editor-confirmed deletions (shake shows
/// the default Undo prompt restoring the newest eligible deletion). The list
/// itself offers no delete affordance — deletion lives in the category
/// editor. All mutations go through `LocalStore`.
struct ManageCategoriesView: View {
    @EnvironmentObject var container: AppContainer
    @Environment(\.undoManager)
    private var undoManager
    @StateObject private var vm: ManageCategoriesViewModel

    init(store: LocalStore, undoBuffer: UndoBufferStore) {
        _vm = StateObject(wrappedValue: ManageCategoriesViewModel(
            store: store,
            undoBuffer: undoBuffer
        ))
    }

    var body: some View {
        Group {
            if vm.isLoading {
                VStack(spacing: Theme.spacingSmall) {
                    ProgressView()
                        .tint(Theme.accentPrimary)
                    Text(L10n.manageCategoriesLoading.text)
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityIdentifier("ManageCategoriesLoading")
            } else if let loadError = vm.loadError {
                ErrorBanner(
                    message: loadError,
                    accessibilityId: "ManageCategoriesLoadError"
                )
                .padding(.horizontal, Theme.screenHorizontalPadding)
            } else if vm.categories.isEmpty {
                EmptyState(
                    icon: "tag",
                    title: L10n.manageCategoriesEmptyTitle.text,
                    subtitle: L10n.manageCategoriesEmptySubtitle.text,
                    actionTitle: L10n.manageCategoriesAdd.text,
                    actionAccessibilityId: "ManageCategoriesEmptyAddButton"
                ) { vm.addCategory() }
            } else {
                List {
                    ForEach(vm.categories) { category in
                        CategoryRow(category: category) {
                            vm.edit(category)
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .accessibilityIdentifier("ManageCategoriesList")
            }
        }
        .navigationTitle(L10n.manageCategoriesTitle.text)
        .navigationBarTitleDisplayMode(.inline)
        .background(Theme.backgroundPrimary.ignoresSafeArea())
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    vm.addCategory()
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel(L10n.manageCategoriesAdd.text)
                .accessibilityIdentifier("ManageCategoriesAddButton")
            }
        }
        .safeAreaInset(edge: .bottom) {
            if let conflict = vm.conflictMessage {
                ErrorBanner(
                    message: conflict,
                    accessibilityId: "ManageCategoriesConflictBanner"
                )
                .padding(.horizontal, Theme.screenHorizontalPadding)
                .padding(.vertical, Theme.spacingSmall)
                .background(Theme.backgroundPrimary)
            }
        }
        .sheet(isPresented: $vm.isShowingEditor) {
            CategoryEditorView(
                store: container.localStore,
                category: vm.editorCategory,
                onSaved: { saved in
                    Task { await vm.editorDidSave(saved) }
                },
                onDuplicate: { _ in
                    vm.conflictMessage = L10n.errorCategoryExists.text
                },
                onDeleted: {
                    // The deletion entered the undo buffer behind the
                    // editor — reload the list and offer the system Undo
                    // confirmation for it.
                    Task {
                        await vm.editorDidDelete()
                        await vm.registerSystemUndo(with: undoManager)
                    }
                }
            )
            .environmentObject(container)
        }
        .task {
            await vm.load()
            await vm.registerSystemUndo(with: undoManager)
        }
        .background(ShakeFirstResponderHost(undoManager: undoManager))
        .onChange(of: container.syncController.status) { status in
            if case .idle = status {
                Task { await vm.load() }
            }
        }
    }
}

#if DEBUG
#Preview("Manage Categories") {
    let container = AppContainer.production()
    NavigationView {
        ManageCategoriesView(
            store: container.localStore,
            undoBuffer: container.undoBuffer
        )
        .environmentObject(container)
    }
    .navigationViewStyle(.stack)
}
#endif
