import Foundation

/// Drives the 30-second undo window (AC7).
///
/// On a deletion, the caller builds an `UndoHold` snapshot and hands it to
/// `start(hold:)`. The `UndoService` starts a 30-second timer; if it fires
/// before the user undoes, the hold is expired (records converted to
/// durable pending deletion) and the `SyncCoordinator` is triggered. If the
/// user undoes (tap or shake) within the window, the hold is cleared and no
/// network request is sent.
///
/// Only the most recent undoable deletion is restorable (U7). Starting a new
/// hold supersedes any existing one (the old hold is expired immediately).
///
/// The timer uses an injectable scheduler so tests can drive it deterministically.
@MainActor
final class UndoService: ObservableObject {

    /// The active hold, if any. Drives the undo-toast visibility in views.
    @Published private(set) var activeHold: UndoHold?

    private let localStore: LocalStore
    private let syncCoordinator: SyncCoordinator?
    /// A closure that returns the current date. Injected so tests can control
    /// the 30-second window boundary.
    private let now: () -> Date
    /// The window duration (30 s per AC7).
    private let windowDuration: TimeInterval
    /// Schedules `work` to run on the main actor after `delay` seconds.
    /// Injected so tests can drive expiry synchronously.
    private let scheduler: (TimeInterval, @MainActor @Sendable @escaping () -> Void) -> Void

    init(
        localStore: LocalStore,
        syncCoordinator: SyncCoordinator? = nil,
        windowDuration: TimeInterval = 30,
        now: @escaping () -> Date = Date.init,
        scheduler: @escaping (TimeInterval, @MainActor @Sendable @escaping () -> Void) -> Void = { delay, work in
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                work()
            }
        }
    ) {
        self.localStore = localStore
        self.syncCoordinator = syncCoordinator
        self.windowDuration = windowDuration
        self.now = now
        self.scheduler = scheduler
    }

    /// Starts the undo window for the given hold. Supersedes any existing
    /// hold (expires it immediately — only the most recent undoable deletion
    /// is restorable, U7).
    func start(hold: UndoHold) async {
        if activeHold != nil {
            await expire()
        }
        do {
            try await localStore.holdForUndo(hold)
            activeHold = hold
            scheduler(windowDuration) { [weak self] in
                self?.expireIfStillCurrent(hold: hold)
            }
        } catch {
            // If the hold can't be written, the records were already hidden
            // but won't be restorable. Surface nothing — the caller's
            // deletion is already committed to pending state as a fallback.
        }
    }

    /// Undo the active hold: restore the hidden records, clear the hold.
    /// No network request is sent.
    func performUndo() async {
        guard activeHold != nil else { return }
        do {
            _ = try await localStore.performUndo()
            activeHold = nil
            Haptics.success()
        } catch {
            // Could not restore — leave the hold active so the user can retry.
        }
    }

    /// Expires the current hold (converts hidden records to pending deletion)
    /// and triggers the SyncCoordinator. Called by the timer or on
    /// supersession/relaunch.
    func expire() async {
        do {
            _ = try await localStore.expireUndoHold()
        } catch {
            // Best-effort: if expiry fails, the records remain hidden. They
            // will be reconciled on the next sync.
        }
        activeHold = nil
        await syncCoordinator?.sync()
    }

    /// Restores the active hold from the database on relaunch (AC7: relaunch
    /// converts held deletions into pending deletion state).
    ///
    /// If a persisted hold is past its expiry, it is expired immediately;
    /// otherwise the timer is re-armed for the remaining window.
    func restoreOnLaunch() async {
        do {
            guard let hold = try await localStore.currentHold() else { return }
            let remaining = hold.expiresAt.timeIntervalSince(now())
            if remaining <= 0 {
                await expire()
            } else {
                activeHold = hold
                scheduler(remaining) { [weak self] in
                    self?.expireIfStillCurrent(hold: hold)
                }
            }
        } catch {
            // No hold to restore.
        }
    }

    /// Clears the active hold and cancels any pending expiry (called on
    /// logout/account switch).
    func clear() {
        activeHold = nil
    }

    // MARK: - Private

    private func expireIfStillCurrent(hold: UndoHold) {
        // Only expire if this hold is still the active one (not superseded).
        guard activeHold == hold else { return }
        Task { await expire() }
    }
}
