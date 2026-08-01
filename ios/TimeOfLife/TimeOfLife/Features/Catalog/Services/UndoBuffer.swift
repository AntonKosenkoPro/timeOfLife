import Foundation

/// Observable undo state for the catalog. The UI (1-2/1-4/1-5) binds
/// `UndoBuffer.state` to render `UndoToast`. In-memory only: relaunch clears
/// it (R3/U7); the committed-after-window deletes live in the persisted
/// `SyncQueue`.
enum UndoState: Equatable, Sendable {
    case empty
    case holding(UndoableItem, expiresAt: Date)
}

/// The most recent undoable deletion. `activityWithEntries` holds the activity
/// + its entry ids as a unit (F10); the entries side is owned by 1-3 — this
/// story defines the case and the restore contract only.
enum UndoableItem: Equatable, Sendable {
    case category(Category)
    case activity(Activity)
    case activityWithEntries(Activity, entryIds: [UUID])
    case entryOnly(UUID)
}

/// Schedules the undo-window commit. Injected so tests drive expiry
/// deterministically instead of waiting on a real timer.
struct UndoScheduler: Sendable {
    let schedule: @Sendable (TimeInterval, @Sendable @escaping () -> Void) -> Cancellable

    struct Cancellable: Sendable {
        let cancel: @Sendable () -> Void
    }

    /// Production: a real `Timer` on the main run loop.
    static let timer = UndoScheduler { delay, block in
        let box = TimerBox()
        box.timer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { _ in
            block()
            box.timer = nil
        }
        return Cancellable { box.timer?.invalidate(); box.timer = nil }
    }

    /// Tests: never auto-fires; tests call `commit(now:)` directly.
    static let manual = UndoScheduler { _, _ in
        Cancellable {}
    }
}

/// `Timer` is not `Sendable`; this box lets the cancel closure capture it from a
/// `@Sendable` context. The timer only mutates on the main run loop.
final class TimerBox: @unchecked Sendable {
    var timer: Timer?
}

/// Holds the most recent undoable deletion for up to 30s (U6/R3). The deletion
/// is NOT committed to `CatalogStore` or `SyncQueue` while held; `undo()`
/// within the window re-inserts (caller) and nothing syncs. After the window,
/// `onCommit` fires so the caller commits the delete locally + enqueues a
/// server `DELETE`. Supersession: only the most recent undoable deletion is
/// restorable (U7). Shake-to-undo (U7) uses iOS system motion — NOT a custom
/// sensor — wired by the UI layer via `undo()`.
@MainActor
final class UndoBuffer: ObservableObject {
    @Published private(set) var state: UndoState = .empty

    /// Called after the 30s window with the held item. The caller commits the
    /// deletion to `CatalogStore` and enqueues a `DELETE` on `SyncQueue`.
    var onCommit: (UndoableItem) async -> Void = { _ in }

    /// The ids of activities/categories currently held in the undo buffer.
    /// Used by reuse lookups to skip soon-to-be-deleted records.
    var heldIds: Set<UUID> {
        guard case let .holding(item, _) = state else { return [] }
        switch item {
        case .activity(let a): return [a.id]
        case .category(let c): return [c.id]
        case .activityWithEntries(let a, _): return [a.id]
        case .entryOnly: return []
        }
    }

    private let scheduler: UndoScheduler
    private var cancellable: UndoScheduler.Cancellable?

    init(scheduler: UndoScheduler = .timer) {
        self.scheduler = scheduler
    }

    deinit {
        cancellable?.cancel()
    }

    /// Records an undoable deletion, starting the 30s window. Supersedes any
    /// previous hold (only the most recent undoable deletion is restorable, U7).
    /// The deletion is NOT committed while held. On supersession, the earlier
    /// hold is committed immediately so it is not silently lost.
    func record(_ item: UndoableItem, window: TimeInterval = 30, now: Date = Date()) {
        // If there is a previous unexpired hold, commit it immediately.
        if case let .holding(previousItem, expiresAt) = state, now < expiresAt {
            cancellable?.cancel()
            state = .empty
            Task { await onCommit(previousItem) }
        }
        let expiresAt = now.addingTimeInterval(window)
        state = .holding(item, expiresAt: expiresAt)
        cancellable?.cancel()
        let fire = window
        cancellable = scheduler.schedule(fire) { [weak self] in
            Task { @MainActor in await self?.commit(now: Date()) }
        }
    }

    /// Within the window, returns the held item (caller re-inserts into
    /// `CatalogStore`) and clears state. Expired or empty → `nil`. On a failed
    /// re-insert, the caller re-holds via `restore(_:)` (INTERACTIONS.md
    /// "Undo API failure") so the user can retry.
    func undo(now: Date = Date()) -> UndoableItem? {
        guard case let .holding(item, expiresAt) = state, now < expiresAt else {
            return nil
        }
        cancellable?.cancel()
        state = .empty
        return item
    }

    /// Re-holds an item after a failed undo re-insert (the caller's re-insert
    /// into `CatalogStore` threw), so the user can retry. Keeps the buffer
    /// holding per INTERACTIONS.md "Undo API failure".
    func restore(_ item: UndoableItem, window: TimeInterval = 30, now: Date = Date()) {
        record(item, window: window, now: now)
    }

    /// Commits the held deletion once the window has elapsed. Called by the
    /// scheduler in production and by tests directly.
    func commit(now: Date = Date()) async {
        guard case let .holding(item, expiresAt) = state, now >= expiresAt else { return }
        cancellable?.cancel()
        state = .empty
        await onCommit(item)
    }
}
