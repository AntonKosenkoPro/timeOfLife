import Foundation

/// View model for Manage Categories (Design/SCREENS/ManageCategories.md,
/// category-management D4): alphabetized local loading, editor presentation,
/// conflict messaging, refresh after mutation, and category-deletion undo
/// through the DEFAULT system Undo confirmation (shake → prompt → confirm
/// restores the newest eligible deletion; buffered deletions stay restorable
/// until the app restarts). Deletion itself lives in the category editor; the
/// list offers no delete affordance. All mutations go through `LocalStore`.
@MainActor
final class ManageCategoriesViewModel: ObservableObject {
    @Published private(set) var categories: [Category] = []
    @Published var editorCategory: Category?
    @Published var isShowingEditor = false
    @Published var conflictMessage: String?
    @Published private(set) var loadError: String?
    @Published private(set) var isLoading = false

    private let store: LocalStore
    private let undoBuffer: UndoBufferStore
    private let nowProvider: () -> Date
    /// The UndoManager the current registration belongs to, held weakly so
    /// the re-registration after an undo targets the same manager without
    /// capturing a non-Sendable value in the undo handler closure.
    private weak var registeredUndoManager: UndoManager?

    init(
        store: LocalStore,
        undoBuffer: UndoBufferStore,
        now: @escaping () -> Date = Date.init
    ) {
        self.store = store
        self.undoBuffer = undoBuffer
        self.nowProvider = now
    }

    /// Loads the local catalog (alphabetized by the store). A deletion
    /// buffered by the editor stays restorable through the system Undo
    /// confirmation until the app restarts — the view registers it on appear.
    func load() async {
        isLoading = true
        loadError = nil
        defer { isLoading = false }
        do {
            categories = try await store.categories()
            conflictMessage = nil
        } catch {
            categories = []
            loadError = L10n.errorLocalPersistence.text
        }
    }

    /// Opens the editor for a new category (default `tag` icon).
    func addCategory() {
        editorCategory = nil
        isShowingEditor = true
    }

    /// Opens the editor prefilled with the category's current values.
    /// Deletion is reached from inside the editor.
    func edit(_ category: Category) {
        editorCategory = category
        isShowingEditor = true
    }

    /// Registers the newest restorable category deletion with the system Undo
    /// manager, so shaking surfaces the DEFAULT Undo confirmation and
    /// confirming restores exactly one category — the most recent buffered
    /// one. Previous registrations are cleared first, so one shake+confirm
    /// can never restore two deletions. Offers nothing when the buffer holds
    /// no category deletion — including when the newest row
    /// belongs to another surface (U7 supersession).
    func registerSystemUndo(with undoManager: UndoManager?) async {
        guard let undoManager else { return }
        registeredUndoManager = undoManager
        undoManager.removeAllActions(withTarget: self)
        guard let recent = try? await undoBuffer.mostRecent(),
              (try? await store.categoryDeletionSnapshot(bufferID: recent.id)) != nil else { return }
        undoManager.registerUndo(withTarget: self) { target in
            Task { @MainActor in
                await target.performUndo()
                await target.registerSystemUndo(with: target.registeredUndoManager)
            }
        }
        // Names the undoable action so the DEFAULT system confirmation
        // states what Confirm will restore. Reuses the existing localized
        // Delete string — no new strings (U4).
        undoManager.setActionName(L10n.deleteCategoryConfirm.text)
    }

    /// Undoes the most recent category deletion: restores
    /// the same category identity and assignments, removes the buffer row,
    /// and refreshes the list. Only category deletions are restored here —
    /// buffer rows owned by other surfaces are left for their owners.
    /// Nothing is synced.
    func performUndo() async {
        do {
            guard let recent = try await undoBuffer.mostRecent() else { return }
            guard try await store.categoryDeletionSnapshot(bufferID: recent.id) != nil else { return }
            if let restored = try await store.undoCategoryDeletion(bufferID: recent.id) {
                categories.insert(restored, at: insertionIndex(for: restored))
                conflictMessage = nil
            }
        } catch {
            conflictMessage = L10n.errorLocalPersistence.text
        }
    }

    /// Refreshes the list after the editor saved a category: replace the
    /// edited row or insert the new one, keeping the list alphabetized.
    func editorDidSave(_ category: Category) async {
        categories.removeAll { $0.id == category.id }
        categories.insert(category, at: insertionIndex(for: category))
        conflictMessage = nil
    }

    /// Refreshes the list after the editor deleted a category: the deleted
    /// row is gone and the buffer holds the restorable snapshot (offered
    /// through the system Undo confirmation).
    func editorDidDelete() async {
        await load()
    }

    // MARK: - Private

    /// The insertion index that keeps the list alphabetized by name.
    private func insertionIndex(for category: Category) -> Int {
        let normalized = category.name.lowercased()
        return categories.firstIndex { $0.name.lowercased() > normalized } ?? categories.endIndex
    }
}
