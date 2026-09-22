import Testing
import Foundation
@testable import TimeOfLife

@MainActor
@Suite("TimerService")
struct TimerServiceTests {

    @Test("stopTimerDraft saves the entry with the final tags and clears the draft")
    func stopSavesEntryAndClearsDraft() async throws {
        let service = makeService()
        let store = service.store
        try await store.createCategory(Category(id: "c1", name: "Work", icon: CatalogIcon.briefcase.rawValue))
        let startedAt = Date(timeIntervalSince1970: 1_600_000_000)
        try await store.saveTimerDraft(activityText: "Gym", categoryIDs: ["c1"], startedAt: startedAt)

        let endedAt = startedAt.addingTimeInterval(600)
        try await service.stopTimerDraft(
            text: "Gym",
            categoryIDs: ["c1"],
            startedAt: startedAt,
            endedAt: endedAt
        )

        let entries = try await store.entries()
        #expect(entries.count == 1)
        #expect(entries.first?.activityText == "Gym")
        #expect(entries.first?.categoryIDs == ["c1"])
        #expect(entries.first?.notes.isEmpty == true)
        #expect(entries.first?.durationSeconds == 600)
        #expect(entries.first?.source == "manual")
        #expect(try await store.outboxRows().filter { $0.resource == "entry" }.count == 1)
        #expect(try await service.runningTimerDraft() == nil)
    }

    @Test("startTimerDraft persists the running draft for crash recovery")
    func startPersistsDraft() async throws {
        let service = makeService()
        let startedAt = Date(timeIntervalSince1970: 1_600_000_000)

        try await service.startTimerDraft(text: "  Gym  ", categoryIDs: ["c2", "c1"], startedAt: startedAt)

        let draft = try await service.runningTimerDraft()
        #expect(draft?.activityText == "Gym")
        #expect(draft?.categoryIDs == ["c2", "c1"])
        #expect(draft?.status == "running")
    }

    @Test("in-progress drafts never enter the outbox")
    func draftsNeverSync() async throws {
        let service = makeService()
        try await service.startTimerDraft(text: "Work", categoryIDs: [], startedAt: Date())

        #expect(try await service.store.outboxRows().isEmpty)
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
