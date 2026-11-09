import Testing
import Foundation
import GRDB
@testable import TimeOfLife

/// The generation policy behind background-execution bracketing: stale
/// asynchronous suspensions must never undo a newer foreground resume.
/// Effect ordering across threads is covered structurally (see
/// `DatabaseSuspension`: one lock serializes each flag mutation together
/// with its GRDB post) plus the concurrency stress below; the generation
/// tests alone cannot prove post ordering.
@Suite("DatabaseSuspension policy", .serialized)
struct DatabaseSuspensionTests {

    @Test("stale generation cannot re-suspend after resume")
    func staleGenerationCannotResuspend() {
        let policy = DatabaseSuspension.shared
        policy.noteSuspended()
        let stale = policy.generation
        policy.noteResumed()
        #expect(policy.suspendIfGeneration(stale) == false)
        #expect(policy.isSuspended == false)
    }

    @Test("current generation still parks")
    func currentGenerationParks() {
        let policy = DatabaseSuspension.shared
        policy.noteResumed()
        let current = policy.generation
        #expect(policy.suspendIfGeneration(current) == true)
        #expect(policy.isSuspended == true)
        policy.noteResumed()
        #expect(policy.isSuspended == false)
    }

    @Test("suspension error classification")
    func suspensionErrorClassification() {
        let policy = DatabaseSuspension.shared
        #expect(DatabaseSuspension.isSuspensionError(LocalStore.LocalStoreError.suspended))
        #expect(!DatabaseSuspension.isSuspensionError(LocalStore.LocalStoreError.notBound))
        #expect(!DatabaseSuspension.isSuspensionError(CancellationError()))
        policy.noteSuspended()
        defer { policy.noteResumed() }
        let abort = DatabaseError(resultCode: .SQLITE_ABORT, message: "Database is suspended")
        let interrupt = DatabaseError(resultCode: .SQLITE_INTERRUPT, message: "interrupted")
        let busy = DatabaseError(resultCode: .SQLITE_BUSY, message: "busy")
        #expect(DatabaseSuspension.isSuspensionError(abort))
        #expect(DatabaseSuspension.isSuspensionError(interrupt))
        // A genuine non-lock error is never misclassified, even suspended.
        #expect(!DatabaseSuspension.isSuspensionError(busy))
    }

    @Test("abort and interrupt classify as suspension even after resume")
    func suspensionErrorsClassifyAfterResume() {
        // UI/sync review 2: the throw (while suspended) and the catch (after
        // an await hop, possibly post-resume) straddle a suspension
        // boundary. Evaluating liveness at catch time flips a genuine
        // refusal into a permanent error (blanked list / sync error /
        // distress) whenever resume lands between the two. Pinned GRDB
        // 7.8.0 produces SQLITE_ABORT only for suspension-abort (no
        // ON CONFLICT ROLLBACK clauses exist in the schema) and
        // SQLITE_INTERRUPT only via sqlite3_interrupt (task cancellation
        // surfaces as CancellationError, which GRDB prioritizes) — so the
        // codes alone identify suspension, no message matching.
        let policy = DatabaseSuspension.shared
        policy.noteSuspended()
        let abort = DatabaseError(resultCode: .SQLITE_ABORT, message: "Database is suspended")
        let interrupt = DatabaseError(resultCode: .SQLITE_INTERRUPT, message: "interrupted")
        policy.noteResumed()
        #expect(DatabaseSuspension.isSuspensionError(abort))
        #expect(DatabaseSuspension.isSuspensionError(interrupt))
    }

    @Test("concurrent expiry and resume agree on flag and queue state")
    func concurrentExpiryAndResumeAgree() async throws {
        // Concurrency review: generation CAS orders the DECISION, not the
        // EFFECTS — a stale suspend posted after a resume re-parks live
        // queues while the flag reads resumed. Regression through the
        // production signals with a real queue: hammer expiry-style
        // suspends against resumes and require flag/queue agreement at the
        // end of every round. Honest limit: this stresses the race instead
        // of scripting an exact preemption (preemption points are
        // OS-thread timing); the ordering guarantee itself is structural
        // (one lock holds each mutation together with its GRDB post).
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent(LocalStore.databaseFileName(userID: "race-u1"))
        // swiftlint:disable:next force_try
        let store = try! LocalStore(url: url, userID: "race-u1")
        let policy = DatabaseSuspension.shared
        for _ in 0..<50 {
            let generation = policy.generation
            await withTaskGroup(of: Void.self) { group in
                group.addTask { policy.noteResumed() }
                group.addTask { _ = policy.suspendIfGeneration(generation) }
                group.addTask { policy.noteSuspended() }
                group.addTask { policy.noteResumed() }
            }
            // Whatever won, flag and queue must agree: a suspended flag
            // refuses, a resumed flag serves. Disagreement (served-while-
            // suspended or refused-while-resumed) fails the round.
            if policy.isSuspended {
                do {
                    _ = try await store.categories()
                    Issue.record("queue served while policy suspended")
                } catch {
                    #expect(DatabaseSuspension.isSuspensionError(error))
                }
            } else {
                _ = try await store.categories()
            }
        }
        if policy.isSuspended {
            policy.noteResumed()
        }
        _ = try await store.categories()
    }
}

/// The background execution window (fix-database-suspension-kill): entering
/// it resumes the queues the suspension parked, but must NOT emit the
/// foreground app-level resume — no new sync trigger, bind, or UI reload
/// may fan out from reap entry. Baseline sync triggers stay
/// foreground/connectivity/manual/pull-only.
@MainActor
@Suite("Background access window")
struct BackgroundAccessWindowTests {

    /// Lock-guarded delivery counter (repo `SignOutBox` precedent: Swift 6
    /// forbids mutating captured vars in concurrently-executing closures).
    final class DidResumeBox: @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0
        var delivered: Int {
            lock.lock(); defer { lock.unlock() }
            return count
        }
        func record() {
            lock.lock(); count += 1; lock.unlock()
        }
    }

    @Test("background entry resumes queues without foreground effects")
    func backgroundEntryResumesQueuesWithoutForegroundEffects() async throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent(LocalStore.databaseFileName(userID: "bg-u1"))
        // swiftlint:disable:next force_try
        let store = try! LocalStore(url: url, userID: "bg-u1")
        let box = DidResumeBox()
        let observation = NotificationCenter.default.addObserver(
            forName: DatabaseSuspension.didResumeNotification,
            object: nil,
            queue: nil
        ) { _ in box.record() }
        defer { NotificationCenter.default.removeObserver(observation) }
        DatabaseSuspension.shared.noteSuspended()
        // The granted-window entry: queues become usable, the foreground
        // signal stays silent (no sync/bind/reload fanout).
        _ = DatabaseSuspension.shared.resumeForBackgroundTask()
        _ = try await store.categories()
        #expect(box.delivered == 0)
        // True foreground resume still emits exactly one foreground signal.
        DatabaseSuspension.shared.noteResumed()
        #expect(box.delivered == 1)
    }
}
