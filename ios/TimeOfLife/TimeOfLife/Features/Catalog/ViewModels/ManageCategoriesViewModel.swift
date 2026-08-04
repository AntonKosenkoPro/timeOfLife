import Foundation
import SwiftUI

/// View model for the Manage Categories screen (F2/F6/U8).
@MainActor
final class ManageCategoriesViewModel: ObservableObject {

    @Published var categories: [Category] = []
    @Published var conflictMessage: String?
    @Published var undoToast: UndoToastInfo?

    /// The category pending deletion (for confirmation).
    @Published var pendingDelete: Category?
    @Published var showDeleteConfirm = false

    private let localStore: LocalStore
    private let undoService: UndoService
    private let syncCoordinator: SyncCoordinator?

    init(
        localStore: LocalStore,
        undoService: UndoService,
        syncCoordinator: SyncCoordinator? = nil
    ) {
        self.localStore = localStore
        self.undoService = undoService
        self.syncCoordinator = syncCoordinator
    }

    /// Loads categories from the local store, ordered by name ascending.
    func loadCategories() async {
        do {
            categories = try await localStore.categoriesSortedByName()
        } catch {
            categories = []
        }
    }

    /// Initiates the delete flow for a category.
    func delete(_ category: Category) {
        pendingDelete = category
        showDeleteConfirm = true
    }

    /// Confirms the category deletion — enters the undo flow.
    func confirmDelete() async {
        guard let category = pendingDelete else { return }
        do {
            let joins = try await localStore.categoryJoins(forCategoryId: category.id)
            let now = Date()
            let hold = UndoHold(
                type: .category,
                targetId: category.id,
                entryIds: [],
                categoryJoins: joins,
                createdAt: now,
                expiresAt: now.addingTimeInterval(30))
            await undoService.start(hold: hold)
            await loadCategories()
            undoToast = UndoToastInfo(
                message: L10n.undoCategoryDeleted.text,
                itemName: category.name)
            await syncCoordinator?.sync()
        } catch {
            // Best-effort: ignore.
        }
        pendingDelete = nil
        showDeleteConfirm = false
    }

    /// Cancels the pending delete.
    func cancelDelete() {
        pendingDelete = nil
        showDeleteConfirm = false
    }

    /// Performs the undo action for the current toast.
    func performUndo() async {
        await undoService.performUndo()
        undoToast = nil
        await loadCategories()
    }

    /// Dismisses the undo toast.
    func dismissUndo() {
        undoToast = nil
    }
}
