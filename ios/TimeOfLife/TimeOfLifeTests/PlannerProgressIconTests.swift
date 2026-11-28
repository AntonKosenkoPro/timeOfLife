import Testing
import UIKit
@testable import TimeOfLife

/// The Track progress icon follows completion (day-planner 14.3):
/// `checklist.unchecked` at 0 done (including the empty 0/0 list),
/// `checklist` while partially done, `checklist.checked` at N/N with N > 0.
/// A missing SF Symbol renders nothing, so each case also resolves its
/// symbol at runtime on the test host (iOS 18 SDK) — the suite fails
/// instead of shipping a silent blank.
@Suite("Planner progress icon states (day-planner 14.3)")
struct PlannerProgressIconTests {
    @Test("empty list renders unchecked", arguments: [(0, 0), (0, 3)])
    func emptyAndZeroRenderUnchecked(pair: (done: Int, total: Int)) {
        #expect(PlannerProgressIcon.symbol(done: pair.done, total: pair.total) == "checklist.unchecked")
    }

    @Test("partial completion renders the plain checklist")
    func partialRendersChecklist() {
        #expect(PlannerProgressIcon.symbol(done: 1, total: 3) == "checklist")
        #expect(PlannerProgressIcon.symbol(done: 2, total: 3) == "checklist")
    }

    @Test("full completion renders checked", arguments: [(1, 1), (3, 3)])
    func fullRendersChecked(pair: (done: Int, total: Int)) {
        #expect(PlannerProgressIcon.symbol(done: pair.done, total: pair.total) == "checklist.checked")
    }

    @Test("all three symbols resolve at runtime")
    func symbolsResolveAtRuntime() {
        for name in ["checklist.unchecked", "checklist", "checklist.checked"] {
            #expect(UIImage(systemName: name) != nil, "SF Symbol \(name) does not resolve on this runtime")
        }
    }
}
