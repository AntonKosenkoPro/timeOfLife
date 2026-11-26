import Testing
import Foundation
@testable import TimeOfLife

/// Pins the day-planner single-surface invariants (change `add-day-planner`
/// §5/§8): open and completed rows share one exact height because the Start
/// affordance slot stays mounted in both states, and a fresh row expands in
/// at the top (opacity-only under Reduce Motion). The pure helpers below
/// are consumed by `PlannerView` — SwiftUI layout itself is not
/// unit-testable, so the tests pin the helpers (the `ClearButtonVisibility`
/// precedent).
@Suite("Planner row layout (day-planner 5.3/8.1)")
struct PlannerRowLayoutTests {

    private func task(named name: String, completedOn: String? = nil) -> PlannerTask {
        PlannerTask(id: UUID().uuidString, name: name, positionKey: "500000", completedOn: completedOn)
    }

    // MARK: - Start slot (5.3)

    @Test("open rows mount a visible Start slot")
    func openRowMountsVisibleSlot() {
        let slot = PlannerStartSlot.slot(for: task(named: "Read"))
        #expect(slot == .visible)
        #expect(slot.isHidden == false)
    }

    @Test("completed rows keep the slot mounted but hidden")
    func completedRowKeepsHiddenSlot() {
        // The slot stays mounted (layout-preserving) instead of being
        // omitted: the row keeps its exact height and no sibling moves.
        let slot = PlannerStartSlot.slot(for: task(named: "Read", completedOn: "2026-11-25"))
        #expect(slot == .hiddenPreservingLayout)
        #expect(slot.isHidden == true)
    }

    // MARK: - Insertion transition (8.1)

    @Test("fresh rows expand outside Reduce Motion")
    func insertionExpands() {
        #expect(PlannerRowInsertion.expands(reduceMotion: false))
    }

    @Test("Reduce Motion insertions never expand")
    func reduceMotionNeverExpands() {
        #expect(!PlannerRowInsertion.expands(reduceMotion: true))
    }
}
