import Testing
import Foundation
@testable import TimeOfLife

@MainActor
@Suite("TimerService")
struct TimerServiceTests {

    @Test("prepareActivity creates a categoryless activity")
    func prepareCreates() async throws {
        let service = makeService()
        let outcome = try await service.prepareActivity(named: "  Gym  ")

        guard case let .created(activity) = outcome else {
            Issue.record("expected created outcome, got \(outcome)")
            return
        }
        #expect(activity.name == "Gym")
        #expect(activity.categoryIDs.isEmpty)
        let stored = try await service.store.activity(id: activity.id)
        #expect(stored?.name == "Gym")
        #expect(stored?.categoryIDs.isEmpty == true)
    }

    @Test("prepareActivity reuses a case-insensitive existing activity")
    func prepareReusesExisting() async throws {
        let service = makeService()
        try await service.store.createActivity(Activity(id: "a1", name: "Deep work"))

        let outcome = try await service.prepareActivity(named: "DEEP WORK")
        guard case let .existing(activity) = outcome else {
            Issue.record("expected existing outcome, got \(outcome)")
            return
        }
        #expect(activity.id == "a1")
        let count = try await service.store.activities().count
        #expect(count == 1)
    }

    @Test("prepareActivity trims surrounding whitespace before identity resolution")
    func prepareTrimsWhitespace() async throws {
        let service = makeService()
        try await service.store.createActivity(Activity(id: "a1", name: "Reading"))

        let outcome = try await service.prepareActivity(named: "  reading  ")
        guard case let .existing(activity) = outcome else {
            Issue.record("expected existing outcome, got \(outcome)")
            return
        }
        #expect(activity.id == "a1")
    }

    @Test("prepareActivity reports a pending deletion as restorable")
    func prepareFindsPendingDeletion() async throws {
        let service = makeService()
        let activity = Activity(id: "a1", name: "Coding")
        let snapshot = DeletionSnapshot(records: [
            DeletionSnapshot.Record(
                resource: "activity",
                recordID: activity.id,
                data: try JSONEncoder().encode(activity)
            ),
        ])
        try await service.store.undoBufferEnter(
            payload: try JSONEncoder().encode(snapshot),
            deletedAt: Date()
        )

        let outcome = try await service.prepareActivity(named: "coding")
        guard case let .restorableDeletion(pending) = outcome else {
            Issue.record("expected restorableDeletion outcome, got \(outcome)")
            return
        }
        #expect(pending.id == "a1")
    }

    @Test("prepareActivity validates the name")
    func prepareValidates() async throws {
        let service = makeService()
        let empty = try await service.prepareActivity(named: "   ")
        #expect(empty == .invalid(.empty))
        let long = try await service.prepareActivity(named: String(repeating: "a", count: 61))
        #expect(long == .invalid(.tooLong))
    }

    @Test("prepareActivity works offline")
    func prepareOffline() async throws {
        let service = makeService()
        let outcome = try await service.prepareActivity(named: "Offline")
        guard case .created = outcome else {
            Issue.record("expected created outcome, got \(outcome)")
            return
        }
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
            .appendingPathComponent("timeoflife.sqlite")
    }
}
