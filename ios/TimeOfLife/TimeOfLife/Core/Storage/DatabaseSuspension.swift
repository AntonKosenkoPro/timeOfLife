import Foundation
import GRDB
import UIKit

/// Central lifecycle policy for account-bound database access
/// (fix-database-suspension-kill): coordinates GRDB queue suspension with
/// process execution availability so no file/SQLite lock survives suspension
/// (RUNNINGBOARD 0xdead10cc).
///
/// Design (see openspec design.md):
/// - Preemption bypasses the actor mailbox: suspension is delivered by
///   posting `Database.suspendNotification`, whose GRDB observers run
///   synchronously on the posting thread straight into `sqlite3_interrupt`.
///   This type holds no `LocalStore` reference and never awaits
///   actor-isolated work that could be blocked behind the synchronous
///   `queue.read` it must interrupt.
/// - One serial policy owner: every transition is synchronous and
///   generation-counted, so a stale asynchronous suspension (e.g. a losing
///   background-task expiration) cannot re-suspend queues after a newer
///   foreground resume.
/// - Resume happens before reads and never waits for loads: `noteResumed`
///   posts the GRDB resume synchronously, then clears the flag, then posts
///   the app-level did-resume signal that re-triggers deferred reloads.
/// - A temporary inactive state (system sheet, permission prompt) is NOT
///   suspension: transitions hook `didEnterBackground` /
///   `willEnterForeground` only, never `willResignActive`.
///
/// Lock-guarded (not main-actor-bound): transitions post from lifecycle
/// callbacks, background-task handlers, and tests alike.
final class DatabaseSuspension: @unchecked Sendable {
    static let shared = DatabaseSuspension()

    /// App-level signal posted synchronously at the tail of `noteResumed`,
    /// after the GRDB resume and after the suspended flag clears: every
    /// observer is guaranteed resumable database access (a foreground read
    /// that raced ahead of the resume fails fast with
    /// `LocalStoreError.suspended` and retries here instead of surfacing a
    /// failure banner).
    static let didResumeNotification = Notification.Name("DatabaseSuspensionDidResume")

    private let lock = NSLock()
    private var suspended = false
    private var generationValue: UInt64 = 0
    private var started = false

    /// Whether safe execution is currently unavailable. `LocalStore`
    /// consults this before touching a queue and fails fast with
    /// `LocalStoreError.suspended` instead of acquiring a lock.
    var isSuspended: Bool {
        lock.withLock { suspended }
    }

    /// Monotonic policy generation, bumped on every transition. Background
    /// execution owners capture it at entry and re-park queues only when it
    /// is unchanged, so a stale expiration cannot undo a newer resume.
    var generation: UInt64 {
        lock.withLock { generationValue }
    }

    /// Subscribes the shared policy to the lifecycle (idempotent). Called
    /// from `AppContainer.init`, which runs on foreground and background
    /// launches alike. Always the default center: GRDB observes the default
    /// center too, so a custom center would silently split the policy from
    /// the queues it governs.
    func start() {
        let shouldStart = lock.withLock { () -> Bool in
            guard !started else { return false }
            started = true
            return true
        }
        guard shouldStart else { return }
        // Tokens are intentionally retained for the process lifetime (the
        // policy is global); discarded_notification_center_observer is
        // satisfied by the stored tokens below.
        let center = NotificationCenter.default
        lifecycleObservers.append(center.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in self?.noteSuspended() })
        lifecycleObservers.append(center.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in self?.noteResumed() })
    }

    private var lifecycleObservers: [NSObjectProtocol] = []

    /// Parks every observing queue: releases locks as soon as possible and
    /// refuses new lock acquisition. Synchronous and idempotent (GRDB
    /// `suspend()` no-ops when already suspended). Safe from any thread.
    ///
    /// The flag mutation and the GRDB post execute under one lock hold:
    /// a concurrent resume cannot slip its resume post between this
    /// decision and this effect (or vice versa), so the last post on the
    /// wire always matches the final flag. The lock is an NSLock (never
    /// awaited, never reentered): GRDB's synchronous observers never call
    /// back into this policy, so holding it across the post cannot
    /// deadlock. App-level observers are never posted under this lock —
    /// see `noteResumed`.
    func noteSuspended() {
        lock.withLock {
            suspended = true
            generationValue &+= 1
            NotificationCenter.default.post(name: Database.suspendNotification, object: nil)
        }
    }

    /// Foreground resume: resumes every observing queue, clears the flag,
    /// then signals app-level observers (sync re-trigger, view reloads,
    /// bind retry). Synchronous and never awaits snapshot loads. The queue
    /// resume precedes the flag clear precedes the app signal, so no
    /// re-triggered read can observe a parked queue.
    func noteResumed() {
        lock.withLock {
            NotificationCenter.default.post(name: Database.resumeNotification, object: nil)
            suspended = false
            generationValue &+= 1
        }
        NotificationCenter.default.post(name: Self.didResumeNotification, object: nil)
    }

    /// Background-window entry (granted BG execution, not a foreground
    /// return): resumes the queues the suspension parked so the cleanup
    /// funnel can read, WITHOUT emitting the app-level foreground signal —
    /// reap entry must not fan out into sync triggers, binds, or UI
    /// reloads. Returns the generation the exit/expiry path re-parks with.
    func resumeForBackgroundTask() -> UInt64 {
        lock.withLock { () -> UInt64 in
            NotificationCenter.default.post(name: Database.resumeNotification, object: nil)
            suspended = false
            generationValue &+= 1
            return generationValue
        }
    }

    /// Re-applies suspension to queues created after the suspend post (a new
    /// queue misses prior notifications). Idempotent: already-suspended
    /// queues no-op. Called by `LocalStore` immediately after opening a
    /// queue so a bind racing the background transition cannot run
    /// migrations or reads with an unparked connection.
    func reapplyIfSuspended() {
        lock.withLock {
            guard suspended else { return }
            NotificationCenter.default.post(name: Database.suspendNotification, object: nil)
        }
    }

    /// Parks queues only when no policy transition happened since
    /// `expected` was captured. Returns whether the suspend was applied.
    /// Background-task owners use this on the expiration/exit path so a
    /// stale expiration cannot re-suspend queues after a foreground resume.
    /// Like every transition, the generation check, the flag mutation, and
    /// the GRDB post are one atomic unit under the policy lock.
    @discardableResult
    func suspendIfGeneration(_ expected: UInt64) -> Bool {
        lock.withLock { () -> Bool in
            guard generationValue == expected else { return false }
            suspended = true
            generationValue &+= 1
            NotificationCenter.default.post(name: Database.suspendNotification, object: nil)
            return true
        }
    }

    /// Whether an error is a suspension refusal rather than a data failure:
    /// the typed `LocalStoreError.suspended` pre-check, or a GRDB
    /// lock-refusal code. The codes are classified unconditionally — pinned
    /// GRDB 7.8.0 produces `SQLITE_ABORT` only for suspension-abort (no
    /// `ON CONFLICT ROLLBACK` clauses exist in the schema) and
    /// `SQLITE_INTERRUPT` only via `sqlite3_interrupt` (the sole caller is
    /// the suspension preemption; task cancellation surfaces as
    /// `CancellationError`, which GRDB prioritizes over suspension-abort).
    /// Evaluating liveness here would flip a genuine refusal into a
    /// permanent error whenever resume lands between the throw and this
    /// catch (they straddle an await hop). Callers map this to silent
    /// stale-retry (keep last snapshot, preserve `needsReload`, abort sync
    /// cycles without `.error`) — never to blanked screens, failure
    /// banners, ended Live Activities, or fabricated saved state.
    static func isSuspensionError(_ error: Error) -> Bool {
        if let storeError = error as? LocalStore.LocalStoreError {
            return storeError == .suspended
        }
        guard let dbError = error as? DatabaseError else { return false }
        return dbError.resultCode == .SQLITE_ABORT || dbError.resultCode == .SQLITE_INTERRUPT
    }
}
