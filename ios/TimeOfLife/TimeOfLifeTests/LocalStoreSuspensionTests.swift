import Testing
import Foundation
import GRDB
@testable import TimeOfLife

/// Regression tests for the 0xdead10cc background-suspension kill
/// (EXC_CRASH SIGKILL RUNNINGBOARD: the app held a file/SQLite lock across
/// suspension while `LocalStore.categories` decoded on a background thread).
///
/// Lifecycle-simulation note: these tests drive the production
/// `DatabaseSuspension` policy and the production GRDB
/// suspend/resume-notification + `DatabaseQueue` path with real
/// temporary-file stores. They prove fail-fast-vs-lock-acquisition behavior
/// across the lifecycle boundary — they do NOT reproduce a physical-device
/// RunningBoard SIGKILL, which cannot be produced in-process.
/// Every suspending test resumes in a `defer` so no test strands the
/// process-wide policy suspended for its neighbors.
@Suite("LocalStore suspension", .serialized)
struct LocalStoreSuspensionTests {

    private func makeStore(userID: String = "suspend-u1") throws -> LocalStore {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent(LocalStore.databaseFileName(userID: userID))
        return try LocalStore(url: url, userID: userID)
    }

    private func suspend() {
        DatabaseSuspension.shared.noteSuspended()
    }

    private func resume() {
        DatabaseSuspension.shared.noteResumed()
    }

    /// Resumes only if still suspended: mid-test explicit resumes plus this
    /// defer must not emit redundant resume bursts.
    private func resumeIfNeeded() {
        if DatabaseSuspension.shared.isSuspended {
            DatabaseSuspension.shared.noteResumed()
        }
    }

    private func seedCategory(in store: LocalStore, id: String = "c1", name: String = "Work") async throws {
        try await store.createCategory(
            Category(id: id, name: name, icon: "briefcase",
                     createdAt: Date(timeIntervalSinceReferenceDate: 1_000),
                     updatedAt: Date(timeIntervalSinceReferenceDate: 1_000))
        )
    }

    @Test("suspended store refuses lock acquisition instead of holding a lock")
    func suspendedStoreRefusesLockAcquisition() async throws {
        let store = try makeStore()
        // Baseline: reads work while resumed.
        _ = try await store.categories()
        suspend()
        defer { resumeIfNeeded() }
        // A suspended store must fail fast (SQLITE_ABORT "Database is
        // suspended", or SQLITE_INTERRUPT for an in-flight op) instead of
        // acquiring a file/SQLite lock that iOS would kill the process for
        // holding at suspension (0xdead10cc).
        do {
            _ = try await store.categories()
        } catch let error as DatabaseError {
            #expect(
                error.resultCode == .SQLITE_ABORT || error.resultCode == .SQLITE_INTERRUPT,
                "unexpected DatabaseError code: \(error.resultCode)"
            )
            return
        } catch let error as LocalStore.LocalStoreError {
            #expect(error == .suspended)
            return
        }
        Issue.record("store acquired database access while suspended — 0xdead10cc exposure")
    }

    @Test("resume restores database access")
    func resumeRestoresAccess() async throws {
        let store = try makeStore()
        suspend()
        resume()
        _ = try await store.categories()
    }

    @Test("repeated suspend/resume cycles keep working")
    func repeatSuspendResumeCycles() async throws {
        let store = try makeStore()
        for _ in 0..<3 {
            suspend()
            do {
                _ = try await store.categories()
                Issue.record("store acquired database access while suspended")
            } catch {
                #expect(DatabaseSuspension.isSuspensionError(error))
            }
            resume()
            _ = try await store.categories()
        }
        #expect(try await store.categories().isEmpty)
    }

    @Test("opening a store while suspended refuses unsafe access")
    func openWhileSuspendedRefusesAccess() async throws {
        // A queue bound while the app is already backgrounded must inherit
        // the current suspension state BEFORE any migration or read runs:
        // handling only queues that existed at notification time leaves a
        // fresh bind holding locks across suspension (0xdead10cc).
        suspend()
        defer { resumeIfNeeded() }
        let store: LocalStore
        do {
            store = try makeStore()
        } catch let error as DatabaseError {
            // Fail-fast inside open (migration writes refused) is an
            // acceptable inheritance shape — still no lock held.
            #expect(
                error.resultCode == .SQLITE_ABORT || error.resultCode == .SQLITE_INTERRUPT,
                "unexpected DatabaseError code: \(error.resultCode)"
            )
            return
        } catch let error as LocalStore.LocalStoreError {
            #expect(error == .suspended)
            return
        }
        do {
            _ = try await store.categories()
        } catch {
            #expect(DatabaseSuspension.isSuspensionError(error))
            return
        }
        Issue.record("store opened while suspended acquired database access — 0xdead10cc exposure")
    }

    @Test("suspended write fails without partial state")
    func suspendedWriteFailsWithoutPartialState() async throws {
        let store = try makeStore()
        suspend()
        defer { resumeIfNeeded() }
        // A refused mutation must leave no outbox row and no record behind:
        // interrupted transactions roll back, and the pre-check refuses
        // before any statement runs.
        do {
            _ = try await store.createCategory(
                draft: CategoryDraft(name: "Work", icon: .briefcase),
                id: "suspend-cat-1"
            )
            Issue.record("store mutated while suspended — 0xdead10cc exposure")
        } catch {
            #expect(DatabaseSuspension.isSuspensionError(error))
        }
        resume()
        #expect(try await store.categories().isEmpty)
        #expect(try await store.outboxRows().isEmpty)
    }

    @Test("account switch across suspension isolates files")
    func accountSwitchAcrossSuspension() async throws {
        let store = try makeStore(userID: "suspend-a")
        try await store.createCategory(
            Category(id: "a1", name: "Work", icon: "briefcase",
                     createdAt: Date(timeIntervalSinceReferenceDate: 1_000),
                     updatedAt: Date(timeIntervalSinceReferenceDate: 1_000))
        )
        // Sign-out lands while suspended: closing touches no database, so
        // it must succeed and drop the binding immediately.
        suspend()
        await store.closeAccount()
        do {
            _ = try await store.categories()
            Issue.record("closed store served reads")
        } catch let error as LocalStore.LocalStoreError {
            #expect(error == .notBound)
        }
        resume()
        // The new account binds a different file with none of the old rows;
        // resumption never reopens the dormant account or moves writes over.
        try await store.openAccount(userID: "suspend-b")
        #expect(try await store.categories().isEmpty)
    }

    @Test("redundant same-account bind while suspended preserves the binding")
    func sameAccountReopenWhileSuspendedPreservesBinding() async throws {
        // Storage review A: the pre-check must not precede the idempotent
        // same-account early return inside a catch-all that wipes the
        // binding — a redundant bind of the already-bound account is a
        // no-op touching no file and must stay one while suspended.
        let store = try makeStore(userID: "same-a")
        try await seedCategory(in: store, id: "a1")
        try await store.openAccount(userID: "same-a")
        suspend()
        defer { resumeIfNeeded() }
        try await store.openAccount(userID: "same-a")
        resume()
        #expect(try await store.categories().count == 1)
        #expect(await store.boundUserID == "same-a")
    }

    @Test("different-account bind while suspended fails safe without wiping")
    func differentAccountBindWhileSuspendedFailsSafe() async throws {
        // A switch attempted while suspended refuses WITHOUT destroying the
        // healthy binding and without touching any file: resumption keeps
        // serving the bound account; the switch retries after resume.
        let store = try makeStore(userID: "same-a")
        try await seedCategory(in: store, id: "a1")
        suspend()
        defer { resumeIfNeeded() }
        do {
            try await store.openAccount(userID: "same-b")
            Issue.record("bound a new account while suspended")
        } catch let error as LocalStore.LocalStoreError {
            #expect(error == .suspended)
        }
        resume()
        #expect(await store.boundUserID == "same-a")
        #expect(try await store.categories().count == 1)
    }

    @Test("resume racing a refusal never converts it into a silent pass")
    func resumeRacingRefusalStaysSafe() async throws {
        // The throw (while suspended) and the catch (possibly after resume)
        // straddle an await: classification must be stable across that hop.
        let store = try makeStore()
        suspend()
        let attempt = Task { try await store.categories() }
        resume()
        do {
            _ = try await attempt.value
        } catch {
            #expect(DatabaseSuspension.isSuspensionError(error))
        }
        _ = try await store.categories()
    }
}

/// Foreground view-model reloads across suspension: fail silent, keep the
/// last good snapshot, stay stale for the resume re-trigger — never blank
/// committed data or surface a failure banner for a transient transition.
@MainActor
@Suite("Suspension reloads")
struct SuspensionReloadTests {

    private func temporaryStoreURL() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent(LocalStore.databaseFileName(userID: "reload-u1"))
    }

    @Test("suspended Track load keeps the snapshot silently")
    func trackSuspendedLoadKeepsSnapshot() async throws {
        // swiftlint:disable:next force_try
        let store = try! LocalStore(url: temporaryStoreURL(), userID: "reload-u1")
        try await store.createCategory(
            Category(id: "c1", name: "Work", icon: "briefcase",
                     createdAt: Date(timeIntervalSinceReferenceDate: 1_000),
                     updatedAt: Date(timeIntervalSinceReferenceDate: 1_000))
        )
        let vm = TrackViewModel(
            service: TimerService(store: store, liveActivities: FakeLiveActivities()),
            connectivity: MockConnectivity(connected: true)
        )
        await vm.load()
        #expect(vm.categories.count == 1)
        DatabaseSuspension.shared.noteSuspended()
        defer { DatabaseSuspension.shared.noteResumed() }
        vm.invalidate()
        await vm.loadIfNeeded()
        #expect(vm.errorMessage == nil)
        #expect(vm.categories.count == 1)
        DatabaseSuspension.shared.noteResumed()
        vm.invalidate()
        await vm.loadIfNeeded()
        #expect(vm.errorMessage == nil)
        #expect(vm.categories.count == 1)
    }

    @Test("suspended History load keeps day groups instead of blanking")
    func historySuspendedLoadKeepsGroups() async throws {
        // swiftlint:disable:next force_try
        let store = try! LocalStore(url: temporaryStoreURL(), userID: "reload-u1")
        let startedAt = Date(timeIntervalSince1970: 1_700_000_000)
        _ = try await store.createEntry(TimeEntry(
            id: UUID().uuidString,
            activityText: "Gym",
            startedAt: startedAt,
            endedAt: startedAt.addingTimeInterval(600),
            durationSeconds: 600,
            categoryIDs: [],
            notes: "",
            createdAt: startedAt,
            updatedAt: startedAt
        ))
        let vm = HistoryViewModel(store: store, undoBuffer: UndoBufferStore(store: store))
        await vm.loadIfNeeded()
        #expect(vm.dayGroups.flatMap(\.entries).count == 1)
        DatabaseSuspension.shared.noteSuspended()
        defer { DatabaseSuspension.shared.noteResumed() }
        vm.invalidate()
        await vm.loadIfNeeded()
        #expect(vm.dayGroups.flatMap(\.entries).count == 1)
        DatabaseSuspension.shared.noteResumed()
        vm.invalidate()
        await vm.loadIfNeeded()
        #expect(vm.dayGroups.flatMap(\.entries).count == 1)
    }

    @Test("suspended Insights load keeps the last breakdown")
    func insightsSuspendedLoadKeepsBreakdown() async throws {
        // swiftlint:disable:next force_try
        let store = try! LocalStore(url: temporaryStoreURL(), userID: "reload-u1")
        let startedAt = Date(timeIntervalSince1970: 1_700_000_000)
        _ = try await store.createEntry(TimeEntry(
            id: UUID().uuidString,
            activityText: "Gym",
            startedAt: startedAt,
            endedAt: startedAt.addingTimeInterval(600),
            durationSeconds: 600,
            categoryIDs: [],
            notes: "",
            createdAt: startedAt,
            updatedAt: startedAt
        ))
        let vm = InsightsViewModel(store: store)
        await vm.loadIfNeeded()
        let populated = vm.breakdown(period: .all, lens: .activity)
        #expect(!populated.rows.isEmpty)
        DatabaseSuspension.shared.noteSuspended()
        defer { DatabaseSuspension.shared.noteResumed() }
        vm.invalidate()
        await vm.loadIfNeeded()
        #expect(vm.breakdown(period: .all, lens: .activity) == populated)
    }

    @Test("suspended orphan reap ends nothing and fabricates nothing")
    func suspendedOrphanReapEndsNothing() async throws {
        let fake = FakeLiveActivities()
        // swiftlint:disable:next force_try
        let store = try! LocalStore(url: temporaryStoreURL(), userID: "reload-u1")
        let service = TimerService(store: store, liveActivities: fake)
        try await service.startTimerDraft(text: "Gym", categoryIDs: [], startedAt: Date())
        DatabaseSuspension.shared.noteSuspended()
        defer { DatabaseSuspension.shared.noteResumed() }
        // Interrupted reads are distinct from an unbound store and from an
        // absent draft: end nothing, invent no Saved duration.
        await service.endOrphanedActivities(knownDurationSeconds: 60)
        await service.endOrphanedActivities()
        #expect(fake.orphanEnds.isEmpty)
    }
}
