import Testing
import Foundation
import GRDB
@testable import TimeOfLife

/// LocalStore stop-path regressions (preserve-running-notes-on-live-stop
/// 2.2–2.3, 4.2): the atomic stop transition and the notes-only update path.
/// Fail-before proof for the receipt half lives in
/// `RunningNotesReviewTests` (nonthrowing `.failure`, retry identity);
/// these pin the storage contract the receipt stands on.
@MainActor
@Suite("LocalStoreStop")
struct LocalStoreStopTests {

    @Test("stopRunningTimer creates the entry, enqueues one create, and clears the draft atomically")
    func stopRunningTimerIsAtomic() async throws {
        let store = try LocalStore(url: temporaryStoreURL())
        let startedAt = Date(timeIntervalSince1970: 1_600_000_000)
        try await store.saveTimerDraft(activityText: "Gym", categoryIDs: [], startedAt: startedAt, notes: "confirmed")

        let entry = TimeEntry(
            id: "e-stop", activityText: "Gym",
            startedAt: startedAt, endedAt: startedAt.addingTimeInterval(600), durationSeconds: 600,
            notes: "confirmed"
        )
        let mutation = try await store.stopRunningTimer(entry)

        guard case let .created(saved) = mutation else {
            Issue.record("expected .created, got \(mutation)")
            return
        }
        #expect(saved.id == "e-stop")
        let entries = try await store.entries()
        #expect(entries.count == 1)
        #expect(entries.first?.notes == "confirmed")
        let creates = try await store.outboxRows().filter { $0.resource == "entry" && $0.op == "create" }
        #expect(creates.count == 1)
        #expect(creates.first?.recordID == "e-stop")
        #expect(try await store.timerDraft() == nil, "the draft clears in the same transaction")
    }

    @Test("stopRunningTimer replay of an idempotent id converges without a second entry or outbox row")
    func stopRunningTimerReplayIsIdempotent() async throws {
        let store = try LocalStore(url: temporaryStoreURL())
        let startedAt = Date(timeIntervalSince1970: 1_600_000_000)
        let entry = TimeEntry(
            id: "e-stop", activityText: "Gym",
            startedAt: startedAt, endedAt: startedAt.addingTimeInterval(600), durationSeconds: 600
        )
        _ = try await store.stopRunningTimer(entry)
        // A crash between commit and receipt leaves the draft behind; the
        // retried stop replays the same id.
        try await store.saveTimerDraft(activityText: "Gym", categoryIDs: [], startedAt: startedAt)

        let replay = try await store.stopRunningTimer(entry)

        guard case let .created(existing) = replay else {
            Issue.record("expected .created(existing), got \(replay)")
            return
        }
        #expect(existing.id == "e-stop")
        #expect(try await store.entries().count == 1)
        #expect(try await store.outboxRows().filter { $0.op == "create" }.count == 1)
        #expect(try await store.timerDraft() == nil)
    }

    @Test("stopRunningTimer rejects invalid text and keeps the draft")
    func stopRunningTimerInvalidTextKeepsDraft() async throws {
        let store = try LocalStore(url: temporaryStoreURL())
        let startedAt = Date(timeIntervalSince1970: 1_600_000_000)
        try await store.saveTimerDraft(activityText: "Gym", categoryIDs: [], startedAt: startedAt)

        let mutation = try await store.stopRunningTimer(TimeEntry(
            id: "e-bad", activityText: "   ",
            startedAt: startedAt, endedAt: startedAt.addingTimeInterval(60), durationSeconds: 60
        ))

        guard case .invalid = mutation else {
            Issue.record("expected .invalid, got \(mutation)")
            return
        }
        #expect(try await store.entries().isEmpty)
        #expect(try await store.outboxRows().isEmpty)
        #expect(try await store.timerDraft() != nil, "no success receipt: the draft stays for retry")
    }

    @Test("stopRunningTimer reports nonthrowing failure and rolls back with the draft kept")
    func stopRunningTimerFailureKeepsDraft() async throws {
        let url = temporaryStoreURL()
        let store = try LocalStore(url: url)
        let startedAt = Date(timeIntervalSince1970: 1_600_000_000)
        try await store.saveTimerDraft(activityText: "Gym", categoryIDs: [], startedAt: startedAt, notes: "confirmed")
        try failEntryInserts(at: url)

        let mutation = try await store.stopRunningTimer(TimeEntry(
            id: "e-stop", activityText: "Gym",
            startedAt: startedAt, endedAt: startedAt.addingTimeInterval(600), durationSeconds: 600,
            notes: "confirmed"
        ))

        guard case .failure = mutation else {
            Issue.record("expected .failure, got \(mutation)")
            return
        }
        #expect(try await store.entries().isEmpty, "the transaction rolls back as one")
        #expect(try await store.outboxRows().isEmpty)
        #expect(try await store.timerDraft() != nil, "the draft stays for retry")
    }

    @Test("updateEntryNotes rewrites only notes with an ordinary update outbox row")
    func updateEntryNotesWritesOrdinaryUpdate() async throws {
        let store = try LocalStore(url: temporaryStoreURL())
        try await store.createCategory(Category(id: "c1", name: "Work", icon: CatalogIcon.briefcase.rawValue))
        let startedAt = Date(timeIntervalSince1970: 1_600_000_000)
        let before = TimeEntry(
            id: "e-notes", activityText: "Gym",
            startedAt: startedAt, endedAt: startedAt.addingTimeInterval(600), durationSeconds: 600,
            categoryIDs: ["c1"], notes: "confirmed"
        )
        _ = try await store.createEntry(before)

        let updated = try await store.updateEntryNotes(id: "e-notes", notes: "reviewed")

        #expect(updated)
        let resolved = try #require(try await store.entry(id: "e-notes"))
        #expect(resolved.notes == "reviewed")
        #expect(resolved.activityText == "Gym")
        #expect(resolved.categoryIDs == ["c1"])
        #expect(resolved.startedAt == startedAt)
        #expect(resolved.endedAt == startedAt.addingTimeInterval(600))
        #expect(resolved.durationSeconds == 600)
        #expect(resolved.updatedAt > before.updatedAt, "strictly later at wire precision")
        let ops = try await store.outboxRows().filter { $0.resource == "entry" }
        #expect(ops.map(\.op) == ["create", "update"], "the ordinary create followed by a separate update")
        #expect(ops.last?.recordID == "e-notes")
    }

    @Test("updateEntryNotes after a synced create enqueues only the update")
    func updateEntryNotesAfterSyncedCreateEnqueuesOnlyUpdate() async throws {
        let store = try LocalStore(url: temporaryStoreURL())
        let startedAt = Date(timeIntervalSince1970: 1_600_000_000)
        _ = try await store.createEntry(TimeEntry(
            id: "e-synced", activityText: "Gym",
            startedAt: startedAt, endedAt: startedAt.addingTimeInterval(600), durationSeconds: 600,
            notes: "confirmed"
        ))
        // The relay already holds the create: the row converges like a
        // still-queued create — an ordinary update, no second create.
        try await store.removeOutboxRow(resource: "entry", recordID: "e-synced")

        #expect(try await store.updateEntryNotes(id: "e-synced", notes: "reviewed"))

        let ops = try await store.outboxRows().filter { $0.resource == "entry" }
        #expect(ops.map(\.op) == ["update"])
        #expect(try await store.entry(id: "e-synced")?.notes == "reviewed")
    }

    @Test("updateEntryNotes on a missing target returns false and never recreates")
    func updateEntryNotesMissingNeverRecreates() async throws {
        let store = try LocalStore(url: temporaryStoreURL())

        #expect(!(try await store.updateEntryNotes(id: "gone", notes: "reviewed")))

        #expect(try await store.entries().isEmpty)
        #expect(try await store.outboxRows().isEmpty)
    }

    @Test("updateEntryNotes preserves a concurrent unrelated edit")
    func updateEntryNotesPreservesConcurrentEdit() async throws {
        let store = try LocalStore(url: temporaryStoreURL())
        try await store.createCategory(Category(id: "c1", name: "Work", icon: CatalogIcon.briefcase.rawValue))
        try await store.createCategory(Category(id: "c2", name: "Health", icon: CatalogIcon.heart.rawValue))
        let startedAt = Date(timeIntervalSince1970: 1_600_000_000)
        _ = try await store.createEntry(TimeEntry(
            id: "e-notes", activityText: "Gym",
            startedAt: startedAt, endedAt: startedAt.addingTimeInterval(600), durationSeconds: 600,
            categoryIDs: ["c1"], notes: "confirmed"
        ))
        // A concurrent merge retags the entry before the review resolves.
        var merged = try #require(try await store.entry(id: "e-notes"))
        merged.categoryIDs = ["c1", "c2"]
        try await store.mergeEntry(merged)

        #expect(try await store.updateEntryNotes(id: "e-notes", notes: "reviewed"))

        let resolved = try #require(try await store.entry(id: "e-notes"))
        #expect(resolved.notes == "reviewed")
        #expect(resolved.categoryIDs == ["c1", "c2"], "the latest other fields are preserved, never reverted")
    }

    // MARK: - Helpers

    /// Makes entry INSERTs fail while entry SELECTs keep working, so the
    /// atomic stop reports its nonthrowing `.failure` instead of throwing.
    /// Fixture-only: app mutation paths stay behind LocalStore.
    private func failEntryInserts(at url: URL) throws {
        let queue = try DatabaseQueue(path: url.path)
        try queue.write { db in
            try db.execute(sql: """
                CREATE TRIGGER stop_repro_fail BEFORE INSERT ON entries
                BEGIN SELECT RAISE(ABORT, 'stop-repro'); END
                """)
        }
    }

    private func temporaryStoreURL() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent(LocalStore.databaseFileName(userID: "u1"))
    }
}
