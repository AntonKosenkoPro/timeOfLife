import Testing
import Foundation
@testable import TimeOfLife

/// Sync cycles across suspension (fix-database-suspension-kill): no cycle
/// starts while suspended, and a cycle aborted by suspension stays silent
/// and triggerable (never `.error`, never stranded `.inactive` from a
/// triggerable state). Drives the production trigger/cycle path with a real
/// temporary-file store; suspends via the production policy. Every test
/// resumes in a `defer` so neighbors never observe a parked policy.
@MainActor
@Suite("SyncController suspension", .serialized)
struct SyncControllerSuspensionTests {

    private func makeContext() -> (store: LocalStore, mock: MockCatalogRepository, controller: SyncController) {
        // swiftlint:disable:next force_try
        let store = try! LocalStore(url: temporaryStoreURL())
        let mock = MockCatalogRepository()
        let controller = SyncController(
            store: store,
            remote: mock,
            connectivity: MockConnectivity(connected: true)
        ) { "u1" }
        return (store, mock, controller)
    }

    private func temporaryStoreURL() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent(LocalStore.databaseFileName(userID: "u1"))
    }

    private func waitUntilNotSyncing(_ controller: SyncController) async {
        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline {
            if case .syncing = controller.status {
                try? await Task.sleep(nanoseconds: 10_000_000)
                continue
            }
            return
        }
        Issue.record("cycle did not settle within 2s; later expectations may be vacuous")
    }

    @Test("trigger while suspended starts no cycle")
    func triggerWhileSuspendedStartsNoCycle() async {
        let (_, mock, controller) = makeContext()
        controller.activate(userID: "u1")
        await waitUntilNotSyncing(controller)
        mock.clearLog()
        DatabaseSuspension.shared.noteSuspended()
        defer { resumeIfNeeded() }
        controller.trigger(userID: "u1")
        try? await Task.sleep(nanoseconds: 100_000_000)
        if case .syncing = controller.status {
            Issue.record("cycle started while suspended")
        }
        #expect(mock.calls.isEmpty)
    }

    @Test("cycle aborted by suspension stays silent then recovers after resume")
    func suspendedCycleAbortsSilentlyThenRecovers() async throws {
        let (store, _, controller) = makeContext()
        try await store.createEntry(TimeEntry(
            id: UUID().uuidString,
            activityText: "Local",
            startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            endedAt: Date(timeIntervalSince1970: 1_700_000_600),
            durationSeconds: 600,
            categoryIDs: [],
            notes: "",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        ))
        // Suspend first so the activation cycle deterministically aborts on
        // its first store touch — no timing dependence.
        DatabaseSuspension.shared.noteSuspended()
        defer { resumeIfNeeded() }
        controller.activate(userID: "u1")
        await waitUntilNotSyncing(controller)
        if case .error = controller.status {
            Issue.record("suspended cycle surfaced .error")
        }
        DatabaseSuspension.shared.noteResumed()
        #expect(!(try await store.outboxRows().isEmpty))
        controller.activate(userID: "u1")
        await waitUntilNotSyncing(controller)
        #expect(isIdle(controller.status))
        #expect(try await store.outboxRows().isEmpty)
    }

    @Test("production resume trigger converges a suspended-aborted cycle")
    func productionResumeTriggerConvergesAfterAbort() async throws {
        // UI/sync review 1: after a suspended-aborted activation cycle the
        // status parks `.inactive`, and the production didResume path only
        // calls `trigger` (refused while inactive) — sync strands dead with
        // a full outbox and no second `activate` ever coming. This test
        // drives the production resume entry point: it must converge.
        let (store, mock, controller) = makeContext()
        try await store.createEntry(TimeEntry(
            id: UUID().uuidString,
            activityText: "Local",
            startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            endedAt: Date(timeIntervalSince1970: 1_700_000_600),
            durationSeconds: 600,
            categoryIDs: [],
            notes: "",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        ))
        DatabaseSuspension.shared.noteSuspended()
        defer { resumeIfNeeded() }
        controller.activate(userID: "u1")
        await waitUntilNotSyncing(controller)
        #expect(!isIdle(controller.status))
        DatabaseSuspension.shared.noteResumed()
        mock.clearLog()
        // Production did-resume path rebinds when inactive, else triggers.
        controller.resume(userID: "u1")
        await waitUntilNotSyncing(controller)
        #expect(isIdle(controller.status))
        #expect(try await store.outboxRows().isEmpty)
    }

    @Test("pre-bind resume stays inactive instead of erroring on an unbound store")
    func preBindResumeStaysInactive() async {
        // Review round 1 #5: `resume` while no account file is bound must
        // not `activate` a cycle — the first store touch would throw
        // `notBound` (not a suspension error), surfacing `.error` that then
        // blocks the post-bind `activate`. The bind path owns activation.
        let store = LocalStore()
        let mock = MockCatalogRepository()
        let controller = SyncController(
            store: store,
            remote: mock,
            connectivity: MockConnectivity(connected: true)
        ) { "u1" }
        controller.resume(userID: "u1")
        await waitUntilNotSyncing(controller)
        if case .error = controller.status {
            Issue.record("pre-bind resume surfaced .error instead of staying inactive")
        }
        #expect(controller.status == .inactive)
        #expect(mock.calls.isEmpty)
    }

    @Test("resume during an in-flight cycle retries after it settles")
    func resumeDuringInflightCycleChains() async {
        // Review round 1 #7: a resume landing while the previous cycle still
        // holds `cycleTask` must not drop the retry — `trigger` refuses
        // while the handle is live, so `resume` re-invokes after it settles.
        let (_, mock, controller) = makeContext()
        mock.fetchEntryPageHandler = { _, _ in
            try? await Task.sleep(nanoseconds: 300_000_000)
            return EntryPage(entries: [], nextCursor: nil)
        }
        controller.activate(userID: "u1")
        var live = false
        for _ in 0..<100 {
            if controller.isCycleLive { live = true; break }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        guard live else {
            Issue.record("first cycle never went live")
            return
        }
        mock.clearLog()
        controller.resume(userID: "u1")
        let deadline = Date().addingTimeInterval(5)
        var pulls = 0
        while Date() < deadline {
            pulls = mock.fetchedEntryPageCursors.count
            if pulls >= 2 { break }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        if pulls < 2 {
            Issue.record("chained retry never started; pulls=\(pulls)")
            return
        }
        await waitUntilNotSyncing(controller)
        #expect(isIdle(controller.status))
    }

    @Test("syncNow while suspended starts no cycle and keeps status")
    func syncNowWhileSuspendedStartsNoCycle() async {
        // UI/sync review 3: manual sync is user-initiated foreground work;
        // while suspended it must fail closed with no cycle, no status
        // churn, and no remote calls — the resume trigger owns the retry.
        let (_, mock, controller) = makeContext()
        controller.activate(userID: "u1")
        await waitUntilNotSyncing(controller)
        #expect(isIdle(controller.status))
        mock.clearLog()
        DatabaseSuspension.shared.noteSuspended()
        defer { resumeIfNeeded() }
        await controller.syncNow(userID: "u1")
        #expect(isIdle(controller.status))
        #expect(mock.calls.isEmpty)
        DatabaseSuspension.shared.noteResumed()
        await controller.syncNow(userID: "u1")
        #expect(isIdle(controller.status))
    }

    private func resumeIfNeeded() {
        if DatabaseSuspension.shared.isSuspended {
            DatabaseSuspension.shared.noteResumed()
        }
    }

    private func isIdle(_ status: SyncController.SyncStatus) -> Bool {
        if case .idle = status { return true }
        return false
    }
}
