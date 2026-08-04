import Foundation
import SwiftUI

/// View model for the Category Editor sheet (F2/U1/U2).
@MainActor
final class CategoryEditorViewModel: ObservableObject {

    @Published var name: String = ""
    @Published var icon: String = "tag"
    @Published var isLoading = false
    @Published var fieldError: String?
    @Published var errorMessage: String?

    /// The category being edited (nil for create mode).
    private(set) var editingCategory: Category?

    private let localStore: LocalStore
    private let syncCoordinator: SyncCoordinator?

    init(
        localStore: LocalStore,
        syncCoordinator: SyncCoordinator? = nil,
        editingCategory: Category? = nil
    ) {
        self.localStore = localStore
        self.syncCoordinator = syncCoordinator
        self.editingCategory = editingCategory
        if let category = editingCategory {
            name = category.name
            icon = category.icon
        }
    }

    /// Validates and saves the category. Returns `true` on success.
    @discardableResult
    func save() async -> Bool {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedName.isEmpty {
            fieldError = L10n.validationNameEmpty.text
            Haptics.error()
            return false
        }
        if trimmedName.count > 60 {
            fieldError = L10n.validationNameTooLong.text
            Haptics.error()
            return false
        }

        isLoading = true
        defer { isLoading = false }

        let now = Date()

        if let category = editingCategory {
            // Edit mode: update the existing category.
            var updated = category
            updated.name = trimmedName
            updated.icon = icon
            updated.updatedAt = now
            updated.sync.syncStatus = .pending
            updated.sync.localRevision += 1
            do {
                try await localStore.upsertCategory(updated)
                await syncCoordinator?.sync()
                return true
            } catch {
                errorMessage = L10n.text(in: .default, code: "unknown")
                return false
            }
        } else {
            // Create mode: insert a new category.
            let id = UUIDv7.generate()
            let category = Category(
                id: id,
                name: trimmedName,
                icon: icon,
                createdAt: now,
                updatedAt: now,
                sync: .newPending())
            do {
                try await localStore.upsertCategory(category)
                await syncCoordinator?.sync()
                return true
            } catch {
                errorMessage = L10n.text(in: .default, code: "unknown")
                return false
            }
        }
    }

    /// Clears the field error when the user edits the name.
    func clearFieldError() {
        fieldError = nil
    }
}
