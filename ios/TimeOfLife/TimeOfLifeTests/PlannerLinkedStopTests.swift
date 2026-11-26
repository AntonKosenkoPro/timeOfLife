import Testing
import Foundation
@testable import TimeOfLife

/// A linked Stop refreshes the Track progress control in place
/// (day-planner 14.2). Owner repro 2026-11-26: Stop completed the task,
/// but the control stayed put until further navigation — the Stop path
/// never invalidated the planner projection, so the stale snapshot kept
/// painting the old counts.
///
/// The service posts the commit event on the single end call site (every
/// Stop path — Track, retry, Island — flows through `stopTimerDraft`);
/// the planner view model observes it (History `timerStoppedExternally`
/// precedent: subscribed in the VM, not the view, so the real
/// notification path is unit-testable) and reloads. The test drives the
/// production pair with a private center and polls the snapshot the way
/// the control reads it: pre-fix the event never fires, so the snapshot
/// stays stale and the poll times out.
@MainActor
@Suite("Linked Stop refreshes the planner projection (day-planner 14.2)")
struct PlannerLinkedStopTests {
    @Test("a linked Stop posts the commit event and the projection reloads")
    func linkedStopRefreshesCounts() async throws {
        let center = NotificationCenter()
        let store = try LocalStore(url: temporaryStoreURL())
        let timer = TimerService(store: store, liveActivities: FakeLiveActivities(), notifications: center)
        let vm = PlannerViewModel(
            store: store,
            undoBuffer: UndoBufferStore(store: store),
            timer: timer,
            notifications: center
        )
        await vm.loadIfNeeded()
        // One open task, started and stopped through the production path.
        let created = try await store.createPlannerTask(
            id: UUID().uuidString, name: "Read", positionKey: "500000",
            operationID: UUID().uuidString
        )
        guard case let .saved(task) = created else {
            Issue.record("create failed: \(created)")
            return
        }
        vm.invalidate()
        await vm.loadIfNeeded()
        #expect(vm.snapshot.done == 0 && vm.snapshot.total == 1)
        #expect(await vm.startTask(try #require(vm.snapshot.tasks.first)))
        _ = try await timer.stopTimerDraft(
            text: "Read", categoryIDs: [],
            startedAt: Date().addingTimeInterval(-60), endedAt: Date()
        )
        // The control reads this snapshot: it must converge to done
        // without any test-side reload (the subscription does it).
        let deadline = Date().addingTimeInterval(3)
        while vm.snapshot.done == 0, Date() < deadline {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        #expect(vm.snapshot.done == 1, "linked Stop left the Track control stale — the projection never reloaded")
        #expect(vm.snapshot.total == 1)
        #expect(try await store.plannerTask(id: task.id)?.completedOn != nil)
    }

    @Test("an ordinary Stop posts no planner event")
    func ordinaryStopPostsNothing() async throws {
        let center = NotificationCenter()
        final class Flag: @unchecked Sendable { var fired = false }
        let flag = Flag()
        let token = center.addObserver(
            forName: .plannerLinkedStopCommitted, object: nil, queue: nil
        ) { _ in flag.fired = true }
        defer { center.removeObserver(token) }
        let store = try LocalStore(url: temporaryStoreURL())
        let timer = TimerService(store: store, liveActivities: FakeLiveActivities(), notifications: center)
        _ = try await store.claimTimerDraft(
            activityText: "Read", categoryIDs: [], startedAt: Date().addingTimeInterval(-60)
        )
        _ = try await timer.stopTimerDraft(
            text: "Read", categoryIDs: [],
            startedAt: Date().addingTimeInterval(-60), endedAt: Date()
        )
        #expect(flag.fired == false)
    }

    private func temporaryStoreURL() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent(LocalStore.databaseFileName(userID: "planner-linked-stop"))
    }
}
