import BackgroundTasks
import Foundation
import OSLog

/// Schedules and registers the background reap check (live-activities):
/// a `BGAppRefreshTask` that wakes the app in the background so an
/// activity orphaned by a link Stop (entry saved through the normal in-app
/// path, activity endable only from the app process) clears without the
/// user opening the app.
///
/// Best-effort throughout: every scheduler call is `try?`/non-throwing,
/// so a background launch never crashes on scheduler errors. No unit
/// tests: `BGTaskScheduler` cannot be driven deterministically in-process
/// (fire timing is OS-determined and registration is process-global), so
/// the reap funnel it invokes (`TimerService.endOrphanedActivities`,
/// including the entry-recency heuristic) is what the suite covers.
enum BackgroundReapScheduler {
    /// The task identifier (also listed in
    /// `BGTaskSchedulerPermittedIdentifiers` in the app plists).
    static let taskIdentifier = "com.antonkosenko.timeoflifeapp.reap-check"

    private static let logger = Logger(
        subsystem: "com.antonkosenko.timeoflifeapp",
        category: "BackgroundReapScheduler"
    )

    /// How far out the reap check is requested — a hint only; the OS
    /// fires whenever it decides (typically minutes, never guaranteed).
    private static let rearmDelaySeconds = 60.0

    /// Cancel-then-submit: at most one reap check is ever pending.
    /// Never throws. Simulator/test processes must not schedule real OS
    /// wakes (a pending request outlives the test run and confuses the
    /// runner teardown) — scheduling is device-only behavior.
    static func scheduleReapCheck() {
        #if targetEnvironment(simulator)
        return
        #else
        let center = BGTaskScheduler.shared
        center.cancel(taskRequestWithIdentifier: taskIdentifier)
        let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: rearmDelaySeconds)
        do {
            try center.submit(request)
        } catch {
            // The submit is the only signal the chain died (e.g. a
            // permitted-identifiers mismatch): record it — a banner that
            // never clears without app contact starts here.
            Self.logger.error("BackgroundReapScheduler: submit failed: \(String(describing: error))")
        }
        #endif
    }

    /// Drops any pending reap check. Never throws.
    static func cancelReapCheck() {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: taskIdentifier)
    }

    /// Registers the launch handler. Call once (from `AppContainer.init` —
    /// it runs on background launches too). The `reap` closure runs the
    /// Part-A funnel and reports whether the run is still ongoing (draft
    /// present → re-arm the chain; otherwise the chain ends with no
    /// reschedule and the next Start re-arms it).
    ///
    /// Suspension bracketing (fix-database-suspension-kill): the handler
    /// resumes the database on entry (a resumed-process launch inherits
    /// parked queues), runs the funnel, then re-parks only while it still
    /// owns the window. Expiration preempts first — posting the suspension
    /// interrupts any in-flight store read, which then fails closed (an
    /// interrupted read is never treated as "no draft") — completes exactly
    /// once, and never re-arms. Both paths park only for their own
    /// generation, so a stale expiration cannot re-suspend queues after a
    /// newer foreground resume. No `UIApplication` time is asserted here:
    /// the task owns only its system-granted BG window.
    static func register(reap: @escaping @Sendable () async -> Bool) {
        #if targetEnvironment(simulator)
        // No real wakes exist here — and registering in a test runner
        // risks the same teardown confusion as scheduling (see above).
        _ = reap
        return
        #else
        BGTaskScheduler.shared.register(forTaskWithIdentifier: taskIdentifier, using: nil) { task in
            // Granted-window entry (not a foreground return): park the
            // generation first, then resume the queues WITHOUT the
            // app-level foreground signal — reap entry must not fan out
            // into sync triggers, binds, or UI reloads.
            let generation = DatabaseSuspension.shared.resumeForBackgroundTask()
            let completion = TaskCompletion(task)
            task.expirationHandler = {
                // Winning the completion race is what grants the park: a
                // stale expiration after the body finished (or after a
                // foreground resume bumped the generation) ends nothing,
                // re-arms nothing, and re-suspends nothing.
                if completion.complete(success: false) {
                    DatabaseSuspension.shared.suspendIfGeneration(generation)
                }
            }
            Task {
                let ongoing = await reap()
                // Losing the race to expiry means the expiration path above
                // already parked and completed: do not re-arm, do not park.
                if completion.complete(success: true) {
                    if ongoing { scheduleReapCheck() }
                    DatabaseSuspension.shared.suspendIfGeneration(generation)
                }
            }
        }
        #endif
    }
}

/// Once-only, thread-safe `BGTask` completion. The box crosses into the
/// `Task` above (so it must be `Sendable`), and the guard keeps the
/// expiration handler from double-completing a finished task. The task
/// reference is weak to break the task → expirationHandler → box → task
/// retain cycle (the system holds the task for the duration anyway).
/// `complete` reports whether the caller won the race, so only the winner
/// parks queues or re-arms the chain.
private final class TaskCompletion: @unchecked Sendable {
    private weak var task: BGTask?
    private let lock = NSLock()
    private var done = false

    init(_ task: BGTask) {
        self.task = task
    }

    @discardableResult
    func complete(success: Bool) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !done else { return false }
        done = true
        task?.setTaskCompleted(success: success)
        return true
    }
}
