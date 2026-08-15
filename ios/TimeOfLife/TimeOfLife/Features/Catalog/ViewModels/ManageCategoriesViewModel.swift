import Foundation
import Combine

/// View model for Manage Categories (Design/SCREENS/ManageCategories.md,
/// category-management D4): alphabetized local loading, editor presentation,
/// delete confirmation, conflict messaging, refresh after mutation, and
/// category-scoped undo state with a wall-clock 30-second window. All
/// mutations go through `LocalStore`.
@MainActor
final class ManageCategoriesViewModel: ObservableObject {
    @Published private(set) var categories: [Category] = []
    @Published var editorCategory: Category?
    @Published var isShowingEditor = false
    @Published var pendingDeletion: Category?
    @Published var isShowingDeleteConfirm = false
    @Published var conflictMessage: String?
    @Published private(set) var loadError: String?
    @Published private(set) var undoToast: UndoToastState?
    @Published private(set) var undoClock = Date()
    @Published private(set) var isLoading = false

    /// Undo affordance state: the deleted category, the durable buffer row
    /// that can restore it, and the wall-clock expiry.
    struct UndoToastState: Equatable {
        let category: Category
        let bufferID: String
        let expiresAt: Date

        func timeRemaining(now: Date) -> TimeInterval {
            max(0, expiresAt.timeIntervalSince(now))
        }

        func isExpired(now: Date) -> Bool {
            now >= expiresAt
        }
    }

    private let store: LocalStore
    private let undoBuffer: UndoBufferStore
    private let nowProvider: () -> Date
    private var ticker: AnyCancellable?

    init(
        store: LocalStore,
        undoBuffer: UndoBufferStore,
        now: @escaping () -> Date = Date.init
    ) {
        self.store = store
        self.undoBuffer = undoBuffer
        self.nowProvider = now
    }

    /// Loads the local catalog (alphabetized by the store) and checks whether
    /// a category deletion is still restorable after a cold launch within the
    /// window (INTERACTIONS.md: no unsolicited toast, but undo stays
    /// available on the screen).
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
        await adoptPendingUndoIfAny()
    }

    /// Opens the editor for a new category (default `tag` icon).
    func addCategory() {
        editorCategory = nil
        isShowingEditor = true
    }

    /// Opens the editor prefilled with the category's current values.
    func edit(_ category: Category) {
        editorCategory = category
        isShowingEditor = true
    }

    /// Presents the destructive confirmation for a category deletion.
    func confirmDelete(_ category: Category) {
        pendingDeletion = category
        isShowingDeleteConfirm = true
    }

    /// Confirms the deletion: enters the durable undo buffer and removes the
    /// category/joins in one transaction (no outbox row), then shows the
    /// wall-clock UndoToast for the newest eligible deletion (D7/U7).
    func deleteConfirmed() async {
        guard let category = pendingDeletion else { return }
        pendingDeletion = nil
        do {
            let deletedAt = nowProvider()
            let outcome = try await store.deleteCategoryUndoable(
                id: category.id,
                deletedAt: deletedAt
            )
            guard case let .deleted(snapshot) = outcome else { return }
            let buffer = try await store.undoBufferMostRecent()
            guard let buffer,
                  let bufferSnapshot = try await store.categoryDeletionSnapshot(bufferID: buffer.id),
                  bufferSnapshot.category.id == category.id else { return }
            undoToast = UndoToastState(
                category: snapshot.category,
                bufferID: buffer.id,
                expiresAt: deletedAt.addingTimeInterval(UndoBufferStore.window)
            )
            undoClock = deletedAt
            categories.removeAll { $0.id == category.id }
            startTicker()
        } catch {
            conflictMessage = L10n.errorLocalPersistence.text
        }
    }

    /// Undoes the most recent category deletion within the window: restores
    /// the same category identity and assignments, removes the buffer row,
    /// and refreshes the list. Nothing is synced.
    func performUndo() async {
        guard let toast = await currentUndoState() else {
            await expireUndo()
            return
        }
        guard !toast.isExpired(now: nowProvider()) else {
            await expireUndo()
            return
        }
        do {
            if let restored = try await store.undoCategoryDeletion(bufferID: toast.bufferID) {
                categories.insert(restored, at: insertionIndex(for: restored))
                undoToast = nil
                stopTicker()
                conflictMessage = nil
            }
        } catch {
            conflictMessage = L10n.errorLocalPersistence.text
        }
    }

    /// Dismisses the toast (the buffer row stays until its window elapses —
    /// the system Undo gesture remains able to restore it).
    func dismissUndo() {
        undoToast = nil
        stopTicker()
    }

    /// Registers the newest category deletion with the system Undo manager.
    /// The handler resolves the durable buffer again, so dismissing the toast
    /// does not make the deletion impossible to undo.
    func registerSystemUndo(with undoManager: UndoManager?) {
        guard undoToast != nil, let undoManager else { return }
        undoManager.removeAllActions(withTarget: self)
        undoManager.registerUndo(withTarget: self) { target in
            Task { @MainActor in
                await target.performUndo()
            }
        }
    }

    /// Commits expired deletions on foreground: the generic machinery
    /// finalizes one Category DELETE outbox row per expired buffer.
    func commitExpiredUndo() async {
        let now = nowProvider()
        undoClock = now
        try? await undoBuffer.commitExpired(now: now)
        if let toast = undoToast, toast.isExpired(now: now) {
            undoToast = nil
            stopTicker()
        }
    }

    /// Refreshes the list after the editor saved a category: replace the
    /// edited row or insert the new one, keeping the list alphabetized.
    func editorDidSave(_ category: Category) async {
        categories.removeAll { $0.id == category.id }
        categories.insert(category, at: insertionIndex(for: category))
        conflictMessage = nil
    }

    // MARK: - Private

    private func startTicker() {
        ticker?.cancel()
        ticker = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                Task { @MainActor in
                    guard let self else { return }
                    let now = self.nowProvider()
                    self.undoClock = now
                    if let toast = self.undoToast, toast.isExpired(now: now) {
                        await self.expireUndo()
                    }
                }
            }
    }

    private func stopTicker() {
        ticker?.cancel()
        ticker = nil
    }

    private func expireUndo() async {
        try? await undoBuffer.commitExpired(now: nowProvider())
        undoToast = nil
        stopTicker()
    }

    /// Restores the newest category deletion from durable storage when the
    /// visible toast was dismissed or the app was relaunched.
    private func currentUndoState() async -> UndoToastState? {
        if let undoToast {
            return undoToast
        }
        guard let buffer = try? await store.undoBufferMostRecent(),
              let snapshot = try? await store.categoryDeletionSnapshot(bufferID: buffer.id) else {
            return nil
        }
        let expiresAt = buffer.deletedAt.addingTimeInterval(UndoBufferStore.window)
        guard expiresAt > nowProvider() else { return nil }
        let state = UndoToastState(
            category: snapshot.category,
            bufferID: buffer.id,
            expiresAt: expiresAt
        )
        undoToast = state
        undoClock = nowProvider()
        startTicker()
        return state
    }

    /// After a cold launch within the window, adopt the newest eligible
    /// category deletion as the undoable one without showing a toast.
    private func adoptPendingUndoIfAny() async {
        guard let buffer = try? await store.undoBufferMostRecent(),
              let snapshot = try? await store.categoryDeletionSnapshot(bufferID: buffer.id) else { return }
        let expiresAt = buffer.deletedAt.addingTimeInterval(UndoBufferStore.window)
        guard expiresAt > nowProvider() else { return }
        undoToast = UndoToastState(
            category: snapshot.category,
            bufferID: buffer.id,
            expiresAt: expiresAt
        )
        undoClock = nowProvider()
        startTicker()
    }

    /// The insertion index that keeps the list alphabetized by name.
    private func insertionIndex(for category: Category) -> Int {
        let normalized = category.name.lowercased()
        return categories.firstIndex { $0.name.lowercased() > normalized } ?? categories.endIndex
    }
}
