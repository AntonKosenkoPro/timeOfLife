// RED-PHASE ATDD scaffold — disabled until the behavior is verified/implemented. Activate by removing .disabled() during the green phase.
import Testing
import Foundation
@testable import TimeOfLife

@MainActor
@Suite("UndoBufferGapScaffold")
struct UndoBufferGapScaffoldTests {

    // MARK: - Supersession commit (1.1-UNIT-008)

    @Test("supersession commits the prior hold exactly once via onCommit", .disabled())
    func supersessionCommitsPriorHold() async {
        // RED: on supersession the prior unexpired hold must be committed via onCommit exactly once (UndoBuffer.swift:94-108); the existing supersession test only asserts the latest is restorable, not the immediate commit of the superseded item.
        let buffer = UndoBuffer(scheduler: .manual)
        var committed: [UndoableItem] = []
        buffer.onCommit = { item in committed.append(item) }
        let t0 = Date(timeIntervalSince1970: 0)
        let first = TestCatalogFactory.activity(name: "First")
        let second = TestCatalogFactory.activity(name: "Second")
        buffer.record(.activity(first), window: 30, now: t0)
        buffer.record(.activity(second), window: 30, now: t0.addingTimeInterval(1))

        for _ in 0..<8 {
            if !committed.isEmpty { break }
            await Task.yield()
        }

        #expect(committed == [.activity(first)])
        let holdsSecond: Bool = if case .holding(.activity(let item), expiresAt: _) = buffer.state {
            item == second
        } else {
            false
        }
        #expect(holdsSecond)
    }

    @Test("supersession at the exact expiry boundary does not double-commit", .disabled())
    func supersessionAtBoundaryDoesNotCommit() async {
        // RED: recording over an expired hold at exactly now == expiresAt must NOT commit the expired item via the supersession path (only the scheduler/commit path commits expired items); boundary semantics are uncovered.
        let buffer = UndoBuffer(scheduler: .manual)
        var committed: [UndoableItem] = []
        buffer.onCommit = { item in committed.append(item) }
        let t0 = Date(timeIntervalSince1970: 0)
        buffer.record(.activity(TestCatalogFactory.activity(name: "First")), window: 30, now: t0)
        let second = TestCatalogFactory.activity(name: "Second")

        buffer.record(.activity(second), window: 30, now: t0.addingTimeInterval(30))

        for _ in 0..<4 {
            await Task.yield()
        }
        #expect(committed.isEmpty)
        let holdsSecond: Bool = if case .holding(.activity(let item), expiresAt: _) = buffer.state {
            item == second
        } else {
            false
        }
        #expect(holdsSecond)
    }

    // MARK: - Undo boundary (window semantics)

    @Test("undo at exactly the boundary (now == expiresAt) returns nil", .disabled())
    func undoAtBoundaryReturnsNil() {
        // RED: undo must only succeed while now < expiresAt; at now == expiresAt the window has closed and undo must return nil — the strict-inequality boundary is uncovered (existing tests use t0+31 and t0+10).
        let buffer = UndoBuffer(scheduler: .manual)
        let t0 = Date(timeIntervalSince1970: 0)
        buffer.record(.activity(TestCatalogFactory.activity()), window: 30, now: t0)

        let restored = buffer.undo(now: t0.addingTimeInterval(30))

        #expect(restored == nil)
    }
}
