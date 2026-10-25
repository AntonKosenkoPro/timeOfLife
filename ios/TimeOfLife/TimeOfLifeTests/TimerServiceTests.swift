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
            endedAt: endedAt,
            notes: "evening session"
        )

        let entries = try await store.entries()
        #expect(entries.count == 1)
        #expect(entries.first?.activityText == "Gym")
        #expect(entries.first?.categoryIDs == ["c1"])
        #expect(entries.first?.notes == "evening session")
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

    @Test("updateTimerDraftNotes rewrites the persisted notes snapshot")
    func updateNotesPersists() async throws {
        let service = makeService()
        try await service.startTimerDraft(text: "Gym", categoryIDs: [], startedAt: Date())

        try await service.updateTimerDraftNotes("mid-run thought")

        let draft = try await service.runningTimerDraft()
        #expect(draft?.notes == "mid-run thought")
        #expect(draft?.activityText == "Gym")
    }

    @Test("updateTimerDraftStartedAt rewrites the start without touching the draft")
    func updateStartPersists() async throws {
        let service = makeService()
        let startedAt = Date(timeIntervalSince1970: 1_600_000_000)
        try await service.startTimerDraft(text: "Gym", categoryIDs: [], startedAt: startedAt)
        let backdated = startedAt.addingTimeInterval(-600)

        try await service.updateTimerDraftStartedAt(backdated)

        let draft = try await service.runningTimerDraft()
        #expect(draft?.startedAt == backdated)
        #expect(draft?.activityText == "Gym")
        // The draft is never synced — Stop enqueues the single entry create.
        #expect(try await service.store.outboxRows().isEmpty)
    }

    @Test("updateTimerDraftStartedAt re-anchors the Live Activity singleton")
    func updateStartReanchorsLiveActivity() async throws {
        // swiftlint:disable:next force_try
        let store = try! LocalStore(url: temporaryStoreURL())
        let fake = FakeLiveActivities()
        let service = TimerService(store: store, liveActivities: fake)
        let startedAt = Date(timeIntervalSince1970: 1_600_000_000)
        try await service.startTimerDraft(text: "Gym", categoryIDs: [], startedAt: startedAt)
        let backdated = startedAt.addingTimeInterval(-600)

        try await service.updateTimerDraftStartedAt(backdated)

        #expect(fake.startChanged == [backdated])
        // The edit re-anchors in place: no re-request (no restart risk),
        // no end.
        #expect(fake.started.count == 1)
        #expect(fake.ended.isEmpty)
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
            .appendingPathComponent(LocalStore.databaseFileName(userID: "u1"))
    }
}
