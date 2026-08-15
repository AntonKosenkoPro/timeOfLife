import SwiftUI

/// Manage Categories (Design/SCREENS/ManageCategories.md, category-
/// management D4): alphabetized list, empty state, Add/edit/swipe-delete
/// controls, destructive copy explaining tag-only deletion, the UndoToast
/// with a wall-clock countdown, system Undo registration for the newest
/// eligible deletion, and the documented accessibility identifiers. All
/// mutations go through `LocalStore`.
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
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                vm.confirmDelete(category)
                            } label: {
                                Label(L10n.deleteCategoryConfirm.text, systemImage: "trash")
                            }
                            .accessibilityIdentifier("CategoryRowDelete(\(category.id))")
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
            VStack(spacing: 0) {
                if let conflict = vm.conflictMessage {
                    ErrorBanner(
                        message: conflict,
                        accessibilityId: "ManageCategoriesConflictBanner"
                    )
                    .padding(.horizontal, Theme.screenHorizontalPadding)
                    .padding(.vertical, Theme.spacingSmall)
                    .background(Theme.backgroundPrimary)
                }
                if let toast = vm.undoToast {
                    UndoToast(
                        message: L10n.undoCategoryDeleted.text,
                        remainingSeconds: Int(toast.timeRemaining(now: vm.undoClock).rounded(.up)),
                        onUndo: {
                            Task { await vm.performUndo() }
                        },
                        onDismiss: {
                            vm.dismissUndo()
                        }
                    )
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
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
                }
            )
            .environmentObject(container)
        }
        .confirmationDialog(
            L10n.deleteCategoryTitle.text,
            isPresented: $vm.isShowingDeleteConfirm,
            titleVisibility: .visible,
            presenting: vm.pendingDeletion
        ) { _ in
            Button(L10n.deleteCategoryConfirm.text, role: .destructive) {
                Task { await vm.deleteConfirmed() }
            }
            Button(L10n.deleteCategoryCancel.text, role: .cancel) {
                vm.pendingDeletion = nil
            }
        } message: { category in
            Text(String(format: L10n.deleteCategoryMessage.text, category.name))
        }
        .task {
            await vm.load()
        }
        .onChange(of: vm.undoToast?.bufferID) { _ in
            vm.registerSystemUndo(with: undoManager)
        }
        .onChange(of: container.syncController.status) { status in
            if case .idle = status {
                Task { await vm.load() }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            Task { await vm.commitExpiredUndo() }
        }
        // System Undo gesture (shake-to-undo, U7): restores the newest
        // eligible category deletion while this surface is active.
        .onShake {
            Task { await vm.performUndo() }
        }
    }
}

/// iOS 15/16-compatible shake detection via the responder chain
/// (Design/INTERACTIONS.md Undo flow); on iOS 17+ `.onShake` on View would
/// duplicate the gesture, so this stays the single path.
extension View {
    func onShake(_ perform: @escaping () -> Void) -> some View {
        self.modifier(ShakeDetector(action: perform))
    }
}

private struct ShakeDetector: ViewModifier {
    let action: () -> Void

    func body(content: Content) -> some View {
        content
            .background(ShakeCatcher(action: action))
    }
}

/// UIKit-based shake catcher that works on iOS 15+.
private final class ShakeCatcherController: UIViewController {
    var onShake: (() -> Void)?

    override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        if motion == .motionShake {
            onShake?()
        }
        super.motionEnded(motion, with: event)
    }
}

private struct ShakeCatcher: UIViewControllerRepresentable {
    let action: () -> Void

    func makeUIViewController(context: Context) -> ShakeCatcherController {
        let controller = ShakeCatcherController()
        controller.onShake = action
        return controller
    }

    func updateUIViewController(_ uiViewController: ShakeCatcherController, context: Context) {
        uiViewController.onShake = action
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
