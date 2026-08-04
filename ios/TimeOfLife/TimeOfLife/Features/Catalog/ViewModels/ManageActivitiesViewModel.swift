import Foundation
import SwiftUI

/// View model for the Manage Activities screen (F8/F10/U8).
@MainActor
final class ManageActivitiesViewModel: ObservableObject {

    @Published var activities: [Activity] = []
    @Published var isLoading = false
    @Published var conflictMessage: String?
    @Published var undoToast: UndoToastInfo?

    /// The activity pending deletion (for scope confirmation).
    @Published var pendingDelete: Activity?
    @Published var showDeleteScope = false

    /// The entry count for the pending-delete activity (for the scope dialog).
    @Published var pendingEntryCount: Int = 0

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

    /// Loads activities from the local store, ordered by `last_used_at` DESC.
    func loadActivities() async {
        do {
            activities = try await localStore.activitiesSortedByLastUsedAt()
        } catch {
            activities = []
        }
    }

    /// Returns the categories for the given activity (resolved from
    /// `categoryIds`).
    func categories(for activity: Activity) async -> [Category] {
        var result: [Category] = []
        for id in activity.categoryIds {
            if let category = try? await localStore.category(id: id) {
                result.append(category)
            }
        }
        return result
    }

    /// Initiates the delete flow for an activity. If the activity has entries,
    /// presents `ScopeConfirmation`; otherwise deletes immediately.
    func delete(_ activity: Activity) async {
        do {
            let count = try await localStore.entryCount(forActivityId: activity.id)
            if count > 0 {
                pendingDelete = activity
                pendingEntryCount = count
                showDeleteScope = true
            } else {
                await performWholeActivityDeletion(activity)
            }
        } catch {
            // Best-effort: ignore.
        }
    }

    /// Deletes the entire activity + all its entries (undoable as a unit).
    func deleteActivityAndEntries() async {
        guard let activity = pendingDelete else { return }
        await performWholeActivityDeletion(activity)
        pendingDelete = nil
        showDeleteScope = false
    }

    /// Deletes only the latest entry for the activity (undoable).
    func deleteEntryOnly() async {
        guard let activity = pendingDelete else { return }
        do {
            guard let entryId = try await localStore.latestEntryId(forActivityId: activity.id) else {
                pendingDelete = nil
                showDeleteScope = false
                return
            }
            let now = Date()
            let hold = UndoHold(
                type: .latestEntry,
                targetId: entryId,
                entryIds: [],
                categoryJoins: [],
                createdAt: now,
                expiresAt: now.addingTimeInterval(30))
            await undoService.start(hold: hold)
            await loadActivities()
            undoToast = UndoToastInfo(
                message: L10n.undoEntriesDeleted.text,
                itemName: activity.name)
            await syncCoordinator?.sync()
        } catch {
            // Best-effort: ignore.
        }
        pendingDelete = nil
        showDeleteScope = false
    }

    /// Cancels the pending delete (clears state when the dialog is dismissed).
    func cancelDelete() {
        pendingDelete = nil
        showDeleteScope = false
    }

    /// Performs the undo action for the current toast.
    func performUndo() async {
        await undoService.performUndo()
        undoToast = nil
        await loadActivities()
    }

    /// Dismisses the undo toast (the 30 s window continues unless the timer
    /// already fired).
    func dismissUndo() {
        undoToast = nil
    }

    // MARK: - Private

    private func performWholeActivityDeletion(_ activity: Activity) async {
        do {
            let entryIds = try await localStore.entryIds(forActivityId: activity.id)
            let now = Date()
            let hold = UndoHold(
                type: .activityWithEntries,
                targetId: activity.id,
                entryIds: entryIds,
                categoryJoins: [],
                createdAt: now,
                expiresAt: now.addingTimeInterval(30))
            await undoService.start(hold: hold)
            await loadActivities()
            let messageText = entryIds.isEmpty
                ? L10n.undoActivityDeleted.text
                : String(format: L10n.undoEntriesDeleted.text, entryIds.count)
            undoToast = UndoToastInfo(message: messageText, itemName: activity.name)
            await syncCoordinator?.sync()
        } catch {
            // Best-effort: ignore.
        }
    }
}

/// Information for the undo toast shown after a delete.
struct UndoToastInfo: Equatable {
    let message: String
    let itemName: String
}
