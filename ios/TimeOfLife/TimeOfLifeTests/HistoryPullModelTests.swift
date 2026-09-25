import Testing
import Foundation
@testable import TimeOfLife

@MainActor
@Suite("HistoryPullModel")
struct HistoryPullModelTests {

    @Test("offline pull shows the offline notice and burns no cycle")
    func offlinePullShowsNoticeWithoutCycle() async throws {
        let (mock, model, controller) = makeContext(connected: false)
        controller.activate(userID: "u1")
        await waitForCycle(controller)
        mock.clearLog()

        await model.refresh()

        #expect(model.notice == .offline)
        #expect(mock.calls.isEmpty)
        #expect(model.syncErrorMessage == nil)
    }

    @Test("offline notice auto-dismisses after its lifetime")
    func offlineNoticeAutoDismisses() async {
        let (_, model, _) = makeContext(connected: false, noticeLifetime: 0.2)

        await model.refresh()
        #expect(model.notice == .offline)

        try? await Task.sleep(nanoseconds: 350_000_000)
        #expect(model.notice == nil)
    }

    @Test("re-pull resets the notice timer")
    func rePullResetsNoticeTimer() async {
        let (_, model, _) = makeContext(connected: false, noticeLifetime: 0.2)

        await model.refresh()
        try? await Task.sleep(nanoseconds: 150_000_000)
        await model.refresh()
        // 0.15s after the second pull (0.3s after the first): the first
        // timer would have fired, the reset one has not.
        try? await Task.sleep(nanoseconds: 150_000_000)
        #expect(model.notice == .offline)

        try? await Task.sleep(nanoseconds: 300_000_000)
        #expect(model.notice == nil)
    }

    @Test("cancelNotice dismisses immediately")
    func cancelNoticeDismissesImmediately() async {
        let (_, model, _) = makeContext(connected: false)

        await model.refresh()
        #expect(model.notice == .offline)

        model.cancelNotice()
        #expect(model.notice == nil)
    }

    @Test("online pull runs a cycle with no notice and no error")
    func onlinePullRunsCycle() async throws {
        let (mock, model, controller) = makeContext(connected: true)
        controller.activate(userID: "u1")
        await waitForCycle(controller)
        mock.clearLog()

        await model.refresh()

        #expect(mock.calls.contains { $0.method == "fetchEntries" })
        #expect(model.notice == nil)
        #expect(model.syncErrorMessage == nil)
        if case .idle = controller.status {} else {
            Issue.record("expected idle status, got \(controller.status)")
        }
    }

    @Test("concurrent pulls join a single cycle")
    func concurrentPullsJoinSingleCycle() async throws {
        let (mock, model, controller, store) = makeFullContext(connected: true)
        controller.activate(userID: "u1")
        await waitForCycle(controller)

        try await store.createEntry(TimeEntry(
            id: "e1", activityText: "Gym",
            startedAt: Date(timeIntervalSinceReferenceDate: 1_000),
            endedAt: Date(timeIntervalSinceReferenceDate: 1_600),
            durationSeconds: 600, source: "manual"
        ))
        mock.createEntryHandler = { _ in
            try await Task.sleep(nanoseconds: 300_000_000)
        }
        mock.clearLog()

        let first = Task { await model.refresh() }
        await waitUntil {
            if case .syncing = controller.status { return true }
            return false
        }
        await model.refresh()
        await first.value
        await waitForCycle(controller)

        let pushes = mock.calls.filter { $0.method == "createEntry" }
        #expect(pushes.count == 1)
        #expect(model.syncErrorMessage == nil)
    }

    @Test("failed pull surfaces the cycle error as dialog content")
    func failedPullSetsErrorMessage() async throws {
        let (mock, model, controller, store) = makeFullContext(connected: true)
        controller.activate(userID: "u1")
        await waitForCycle(controller)

        try await store.createCategory(Category(id: "c1", name: "Sport", icon: "figure.run"))
        mock.createCategoryHandler = { _ in
            throw APIError.server(code: "internal_error", message: "boom", details: [:])
        }

        await model.refresh()

        #expect(model.syncErrorMessage == "server(internal_error): boom")
        #expect(model.notice == nil)
    }

    @Test("background cycle failure with no pull in flight sets no dialog content")
    func backgroundFailureSetsNoDialog() async throws {
        let (mock, model, controller, store) = makeFullContext(connected: true)
        controller.activate(userID: "u1")
        await waitForCycle(controller)

        try await store.createCategory(Category(id: "c1", name: "Sport", icon: "figure.run"))
        mock.createCategoryHandler = { _ in
            throw APIError.server(code: "internal_error", message: "boom", details: [:])
        }

        // A background trigger (foreground/connectivity), not a pull.
        await controller.syncNow(userID: "u1")

        guard case .error = controller.status else {
            Issue.record("expected error status, got \(controller.status)")
            return
        }
        #expect(model.syncErrorMessage == nil)
    }

    @Test("mid-cycle failure routes to the dialog, not the offline notice")
    func midCycleFailureRoutesToDialog() async throws {
        let (mock, model, controller, _) = makeFullContext(connected: true)
        controller.activate(userID: "u1")
        await waitForCycle(controller)

        // Online at pull time, failing mid-cycle.
        mock.fetchDeletionsHandler = { _ in throw APIError.offline }

        await model.refresh()

        #expect(model.notice == nil)
        #expect(model.syncErrorMessage != nil)
    }

    // MARK: - Helpers

    private func makeContext(
        connected: Bool,
        noticeLifetime: TimeInterval = 5
    ) -> (mock: MockCatalogRepository, model: HistoryPullModel, controller: SyncController) {
        let (mock, model, controller, _) = makeFullContext(
            connected: connected, noticeLifetime: noticeLifetime
        )
        return (mock, model, controller)
    }

    private func makeFullContext(
        connected: Bool,
        noticeLifetime: TimeInterval = 5
    ) -> (
        mock: MockCatalogRepository,
        model: HistoryPullModel,
        controller: SyncController,
        store: LocalStore
    ) {
        // swiftlint:disable:next force_try
        let store = try! LocalStore(url: temporaryStoreURL())
        let mock = MockCatalogRepository()
        let connectivity = MockConnectivity(connected: connected)
        let controller = SyncController(store: store, remote: mock, connectivity: connectivity) { "u1" }
        let model = HistoryPullModel(
            sync: controller,
            connectivity: connectivity,
            sessionUserIDProvider: { "u1" },
            noticeLifetime: noticeLifetime
        )
        return (mock, model, controller, store)
    }

    private func temporaryStoreURL() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent(LocalStore.databaseFileName(userID: "u1"))
    }

    private func waitForCycle(_ controller: SyncController) async {
        await waitUntil {
            if case .syncing = controller.status { return false }
            return true
        }
    }

    private func waitUntil(timeout: TimeInterval = 2, _ condition: @escaping () -> Bool) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline, !condition() {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    }
}
