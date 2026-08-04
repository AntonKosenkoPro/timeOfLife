import Foundation
import SwiftUI

/// View model for the Activity Editor sheet (F1/F3/F7/U1/U2).
@MainActor
final class ActivityEditorViewModel: ObservableObject {

    @Published var name: String = ""
    @Published var notes: String = ""
    @Published var selectedCategoryIds: Set<String> = []
    @Published var availableCategories: [Category] = []
    @Published var isLoading = false
    @Published var fieldError: String?
    @Published var errorMessage: String?

    /// The activity being edited (nil for create mode).
    private(set) var editingActivity: Activity?

    private let localStore: LocalStore
    private let syncCoordinator: SyncCoordinator?

    init(
        localStore: LocalStore,
        syncCoordinator: SyncCoordinator? = nil,
        editingActivity: Activity? = nil
    ) {
        self.localStore = localStore
        self.syncCoordinator = syncCoordinator
        self.editingActivity = editingActivity
        if let activity = editingActivity {
            name = activity.name
            notes = activity.notes ?? ""
            selectedCategoryIds = Set(activity.categoryIds)
        }
    }

    /// Loads available categories for the tag selector.
    func loadCategories() async {
        do {
            availableCategories = try await localStore.categoriesSortedByName()
            // Prune stale category ids that no longer exist.
            let validIds = Set(availableCategories.map(\.id))
            selectedCategoryIds = selectedCategoryIds.intersection(validIds)
        } catch {
            availableCategories = []
        }
    }

    /// Validates and saves the activity. Returns `true` on success.
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
        if notes.count > 280 {
            fieldError = L10n.validationNotesTooLong.text
            Haptics.error()
            return false
        }

        isLoading = true
        defer { isLoading = false }

        let now = Date()
        let categoryIds = Array(selectedCategoryIds)

        if let activity = editingActivity {
            return await updateExisting(activity: activity, trimmedName: trimmedName, categoryIds: categoryIds, now: now)
        } else {
            return await createNew(trimmedName: trimmedName, categoryIds: categoryIds, now: now)
        }
    }

    private func updateExisting(activity: Activity, trimmedName: String, categoryIds: [String], now: Date) async -> Bool {
        var updated = activity
        updated.name = trimmedName
        updated.notes = notes.isEmpty ? nil : notes
        updated.categoryIds = categoryIds
        updated.updatedAt = now
        updated.sync.syncStatus = .pending
        updated.sync.localRevision += 1
        do {
            try await localStore.upsertActivity(updated)
            await syncCoordinator?.sync()
            return true
        } catch {
            errorMessage = L10n.text(in: .default, code: "unknown")
            return false
        }
    }

    private func createNew(trimmedName: String, categoryIds: [String], now: Date) async -> Bool {
        let id = UUIDv7.generate()
        let activity = Activity(
            id: id,
            name: trimmedName,
            notes: notes.isEmpty ? nil : notes,
            lastUsedAt: nil,
            createdAt: now,
            updatedAt: now,
            categoryIds: categoryIds,
            sync: .newPending())
        do {
            try await localStore.upsertActivity(activity)
            await syncCoordinator?.sync()
            return true
        } catch {
            errorMessage = L10n.text(in: .default, code: "unknown")
            return false
        }
    }

    /// Clears the field error when the user edits the name.
    func clearFieldError() {
        fieldError = nil
    }
}
