import Testing
import Foundation
@testable import TimeOfLife

@MainActor
@Suite("UndoBuffer")
struct UndoBufferTests {

    @Test("record holds the item")
    func recordHolds() {
        let buffer = UndoBuffer(scheduler: .manual)
        let activity = TestCatalogFactory.activity()

        buffer.record(.activity(activity), window: 30, now: Date(timeIntervalSince1970: 0))

        guard case let .holding(item, expiresAt) = buffer.state else {
            Issue.record("Expected holding state")
            return
        }
        #expect(item == .activity(activity))
        #expect(expiresAt == Date(timeIntervalSince1970: 30))
    }

    @Test("undo within the window returns the item and clears state")
    func undoWithinWindow() {
        let buffer = UndoBuffer(scheduler: .manual)
        let activity = TestCatalogFactory.activity()
        let t0 = Date(timeIntervalSince1970: 0)
        buffer.record(.activity(activity), window: 30, now: t0)

        let restored = buffer.undo(now: t0.addingTimeInterval(10))

        #expect(restored == .activity(activity))
        #expect(buffer.state == .empty)
    }

    @Test("undo after the window returns nil")
    func undoExpired() {
        let buffer = UndoBuffer(scheduler: .manual)
        let t0 = Date(timeIntervalSince1970: 0)
        buffer.record(.activity(TestCatalogFactory.activity()), window: 30, now: t0)

        let restored = buffer.undo(now: t0.addingTimeInterval(31))
        #expect(restored == nil)
    }

    @Test("a second record supersedes the first — only the latest is restorable")
    func supersession() {
        let buffer = UndoBuffer(scheduler: .manual)
        let t0 = Date(timeIntervalSince1970: 0)
        let first = TestCatalogFactory.activity(name: "First")
        let second = TestCatalogFactory.activity(name: "Second")
        buffer.record(.activity(first), window: 30, now: t0)
        buffer.record(.activity(second), window: 30, now: t0.addingTimeInterval(1))

        let restored = buffer.undo(now: t0.addingTimeInterval(2))

        #expect(restored == .activity(second))
    }

    @Test("expiry commits via onCommit and clears state")
    func expiryCommits() async {
        let buffer = UndoBuffer(scheduler: .manual)
        var committed: [UndoableItem] = []
        buffer.onCommit = { item in committed.append(item) }
        let activity = TestCatalogFactory.activity()
        let t0 = Date(timeIntervalSince1970: 0)
        buffer.record(.activity(activity), window: 30, now: t0)

        await buffer.commit(now: t0.addingTimeInterval(31))

        #expect(committed == [.activity(activity)])
        #expect(buffer.state == .empty)
    }

    @Test("commit before the window is a no-op")
    func commitBeforeWindowIsNoOp() async {
        let buffer = UndoBuffer(scheduler: .manual)
        var committed: [UndoableItem] = []
        buffer.onCommit = { item in committed.append(item) }
        let t0 = Date(timeIntervalSince1970: 0)
        buffer.record(.activity(TestCatalogFactory.activity()), window: 30, now: t0)

        await buffer.commit(now: t0.addingTimeInterval(10))

        #expect(committed.isEmpty)
        let isHolding: Bool = if case .holding = buffer.state { true } else { false }
        #expect(isHolding)
    }

    @Test("a fresh UndoBuffer starts empty (relaunch clears)")
    func freshIsEmpty() {
        let buffer = UndoBuffer(scheduler: .manual)
        #expect(buffer.state == .empty)
    }

    @Test("restore re-holds an item after a failed undo re-insert")
    func restoreReholds() {
        let buffer = UndoBuffer(scheduler: .manual)
        let activity = TestCatalogFactory.activity()
        let t0 = Date(timeIntervalSince1970: 0)
        buffer.record(.activity(activity), window: 30, now: t0)

        _ = buffer.undo(now: t0.addingTimeInterval(5))
        #expect(buffer.state == .empty)

        // Caller's re-insert failed → re-hold so the user can retry.
        buffer.restore(.activity(activity), window: 30, now: t0.addingTimeInterval(6))
        let restoredMatches: Bool = if case .holding(.activity(let restored), expiresAt: _) = buffer.state {
            restored == activity
        } else {
            false
        }
        #expect(restoredMatches)
    }
}
