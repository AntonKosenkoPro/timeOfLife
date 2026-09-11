import Testing
import Foundation
@testable import TimeOfLife

/// Regression coverage for the base scenario behind the reported
/// activity-undo failure: deleting an activity from its editor must be
/// undoable from the presenting surface, and MUST NOT be claimable by the
/// entry surface (whose snapshots overlap by resource).
///
/// Root cause it guards: activity snapshots carry entry records, so the
/// entry decoder used to match activity rows and the detail sheet registered
/// a phantom "Delete entry" undo that raced the real "Delete activity"
/// registration — and no-op'd (or, without FK enforcement, shredded the
/// activity snapshot into an orphan entry).
@MainActor
@Suite("Activity delete undo base scenario (unify-catalog-deletion)")
struct ActivityDeleteUndoBaseScenarioTests {

    private func makeStore() throws -> LocalStore {
        try LocalStore(url: URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("timeoflife.sqlite"))
    }

    private func seedActivityWithEntry(_ store: LocalStore) async throws {
        try await store.createActivity(Activity(id: "a1", name: "Running"))
        try await store.createEntry(TimeEntry(
            id: "e1", activityID: "a1", activityName: "Running",
            startedAt: Date(timeIntervalSinceReferenceDate: 1_000),
            endedAt: Date(timeIntervalSinceReferenceDate: 1_600), durationSeconds: 600,
            source: "manual"
        ))
    }

    @Test("entry surface ignores an activity deletion; activity surface restores it")
    func entrySurfaceYieldsToActivitySurface() async throws {
        let store = try makeStore()
        try await seedActivityWithEntry(store)
        // The editor's confirmed delete.
        _ = try await store.deleteActivityUndoable(id: "a1", deletedAt: Date())
        let buffer = try #require(try await store.undoBufferMostRecent())

        // The detail sheet (entry surface): offers nothing, changes nothing.
        let detailVM = ActivityDetailViewModel(store: store, activityID: "a1")
        let detailUndo = UndoManager()
        await detailVM.registerSystemUndo(with: detailUndo)
        #expect(!detailUndo.canUndo)
        await detailVM.performUndo()
        #expect(try await store.undoBufferMostRecent()?.id == buffer.id)
        #expect(try await store.activity(id: "a1") == nil)

        // The presenting surface (History): offers and restores everything.
        let historyVM = HistoryViewModel(store: store)
        let historyUndo = UndoManager()
        await historyVM.registerActivityUndo(with: historyUndo)
        #expect(historyUndo.canUndo)
        #expect(historyUndo.undoActionName == L10n.activityEditorDelete.text)
        await historyVM.performActivityUndo()
        #expect(try await store.activity(id: "a1")?.name == "Running")
        #expect(try await store.entry(id: "e1")?.durationSeconds == 600)
        #expect(try await store.undoBufferMostRecent() == nil)
    }

    @Test("activity surface ignores an entry deletion; entry surface restores it")
    func activitySurfaceYieldsToEntrySurface() async throws {
        let store = try makeStore()
        try await seedActivityWithEntry(store)
        // The entry form's confirmed delete.
        _ = try await store.deleteEntryUndoable(id: "e1", deletedAt: Date())
        let buffer = try #require(try await store.undoBufferMostRecent())

        // History (activity surface): offers nothing, changes nothing.
        let historyVM = HistoryViewModel(store: store)
        let historyUndo = UndoManager()
        await historyVM.registerActivityUndo(with: historyUndo)
        #expect(!historyUndo.canUndo)
        await historyVM.performActivityUndo()
        #expect(try await store.undoBufferMostRecent()?.id == buffer.id)
        #expect(try await store.entry(id: "e1") == nil)

        // The detail sheet (entry surface): offers and restores.
        let detailVM = ActivityDetailViewModel(store: store, activityID: "a1")
        let detailUndo = UndoManager()
        await detailVM.registerSystemUndo(with: detailUndo)
        #expect(detailUndo.canUndo)
        await detailVM.performUndo()
        #expect(try await store.entry(id: "e1") != nil)
        #expect(try await store.undoBufferMostRecent() == nil)
    }
}
