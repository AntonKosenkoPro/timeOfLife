import Testing
import Foundation
@testable import TimeOfLife

/// Linked-run convergence from the Track side (day-planner 15.2): mid-run
/// retag and notes edits write through to the linked task in the same
/// chokepoint transaction, re-mirror the Live Activity chips, and stay
/// draft-only on ordinary runs. Split from `TimerServiceTests`
/// (file-length rule).
@MainActor
@Suite("Linked-run convergence (day-planner 15.2)")
struct TimerLinkedConvergenceTests {
    // MARK: - Linked-run convergence (day-planner 15.2)

    @Test("Track retag writes through to the linked task with one outbox row")
    func trackRetagWritesThrough() async throws {
        let service = makeService()
        let store = service.store
        _ = try await store.createPlannerTask(
            id: "task-1", name: "Read", positionKey: "500000",
            operationID: UUID().uuidString
        )
        let startedAt = Date(timeIntervalSince1970: 1_600_000_000)
        _ = try await service.startLinkedTask(
            name: "Read", categoryIDs: [], notes: "", taskID: "task-1", startedAt: startedAt
        )
        let before = try await store.outboxRowCount()

        try await service.retagRunningDraft(["c1"])

        // The draft and the task converge; exactly one retag row rides the
        // outbox — no draft-sync row, no extra intent. The locked text and
        // the notes snapshot are untouched.
        let draft = try #require(try await store.timerDraft())
        #expect(draft.categoryIDs == ["c1"])
        #expect(draft.activityText == "Read")
        #expect(draft.notes.isEmpty)
        #expect(try await store.plannerTask(id: "task-1")?.categoryIDs == ["c1"])
        #expect(try await store.outboxRowCount() == before + 1)
        let intents = try await store.outboxRows().compactMap { row -> String? in
            guard let payload = row.payload?.data(using: .utf8),
                  row.resource == LocalStore.plannerResource
            else { return nil }
            return try? JSONDecoder().decode(PlannerOperationPayload.self, from: payload).intent
        }
        #expect(intents == ["create", "retag"])
    }

    @Test("Track retag re-mirrors the Live Activity chips in place")
    func trackRetagRemirrorsChips() async throws {
        // swiftlint:disable:next force_try
        let store = try! LocalStore(url: temporaryStoreURL())
        let fake = FakeLiveActivities()
        let service = TimerService(store: store, liveActivities: fake)
        _ = try await store.createPlannerTask(
            id: "task-1", name: "Read", positionKey: "500000",
            operationID: UUID().uuidString
        )
        let startedAt = Date(timeIntervalSince1970: 1_600_000_000)
        _ = try await service.startLinkedTask(
            name: "Read", categoryIDs: [], notes: "", taskID: "task-1", startedAt: startedAt
        )
        #expect(fake.started.count == 1)

        try await service.retagRunningDraft(["c1"])

        // Same-text singleton: one re-mirror with the new chips, no restart
        // (no end, no start change).
        #expect(fake.started.count == 2)
        #expect(fake.started.last?.startedAt == startedAt)
        #expect(fake.ended.isEmpty)
        #expect(fake.startChanged.isEmpty)
    }

    @Test("Track notes edit writes through to the linked task with one outbox row")
    func trackNotesWritesThrough() async throws {
        let service = makeService()
        let store = service.store
        _ = try await store.createPlannerTask(
            id: "task-1", name: "Read", positionKey: "500000",
            operationID: UUID().uuidString
        )
        let startedAt = Date(timeIntervalSince1970: 1_600_000_000)
        _ = try await service.startLinkedTask(
            name: "Read", categoryIDs: [], notes: "", taskID: "task-1", startedAt: startedAt
        )
        let before = try await store.outboxRowCount()

        try await service.updateTimerDraftNotes("mid-run thought")

        let draft = try #require(try await store.timerDraft())
        #expect(draft.notes == "mid-run thought")
        #expect(draft.activityText == "Read")
        #expect(try await store.plannerTask(id: "task-1")?.notes == "mid-run thought")
        #expect(try await store.outboxRowCount() == before + 1)
        let intents = try await store.outboxRows().compactMap { row -> String? in
            guard let payload = row.payload?.data(using: .utf8),
                  row.resource == LocalStore.plannerResource
            else { return nil }
            return try? JSONDecoder().decode(PlannerOperationPayload.self, from: payload).intent
        }
        #expect(intents == ["create", "notes"])
    }

    @Test("write-through on an ordinary run touches no task and queues nothing")
    func writeThroughUnlinkedIsDraftOnly() async throws {
        let service = makeService()
        let store = service.store
        _ = try await store.createPlannerTask(
            id: "task-1", name: "Read", positionKey: "500000",
            operationID: UUID().uuidString
        )
        try await service.startTimerDraft(text: "Gym", categoryIDs: [], startedAt: Date())

        try await service.retagRunningDraft(["c1"])
        try await service.updateTimerDraftNotes("mid-run thought")

        #expect(try await store.timerDraft()?.categoryIDs == ["c1"])
        #expect(try await store.timerDraft()?.notes == "mid-run thought")
        // The unrelated task is untouched and the planner outbox stays at
        // the single create row.
        #expect(try await store.plannerTask(id: "task-1")?.categoryIDs.isEmpty == true)
        #expect(try await store.plannerTask(id: "task-1")?.notes.isEmpty == true)
        #expect(try await store.outboxRows().count == 1)
    }

    // MARK: - Helpers

    private func makeService() -> TimerService {
        // swiftlint:disable:next force_try
        let store = try! LocalStore(url: temporaryStoreURL())
        return TimerService(store: store)
    }

    private func temporaryStoreURL() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent(LocalStore.databaseFileName(userID: "timer-convergence"))
    }
}
