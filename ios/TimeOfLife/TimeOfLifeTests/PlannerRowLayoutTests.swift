import Testing
import Foundation
@testable import TimeOfLife

/// Pins the day-planner single-surface invariants (change `add-day-planner`
/// §5): open and completed rows share one exact height because the Start
/// affordance slot stays mounted in both states, and suggestion rows split
/// the matched prefix for highlight. The pure helpers below are consumed by
/// `PlannerView` — SwiftUI layout itself is not unit-testable, so the tests
/// pin the helpers (the `ClearButtonVisibility` precedent).
@Suite("Planner row layout (day-planner 5.3/5.4)")
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

    // MARK: - Suggestion highlight (5.4)

    @Test("highlight splits the matched prefix")
    func highlightSplitsPrefix() {
        let parts = PlannerSuggestionHighlight.split(text: "Reading", draft: "read")
        #expect(parts.match == "Read")
        #expect(parts.rest == "ing")
    }

    @Test("highlight match is case-insensitive but keeps the original casing")
    func highlightKeepsCasing() {
        let parts = PlannerSuggestionHighlight.split(text: "Read docs", draft: "READ")
        #expect(parts.match == "Read")
        #expect(parts.rest == " docs")
    }

    @Test("non-matching text highlights nothing")
    func nonMatchHighlightsNothing() {
        let parts = PlannerSuggestionHighlight.split(text: "Gym", draft: "run")
        #expect(parts.match.isEmpty)
        #expect(parts.rest == "Gym")
    }

    @Test("blank draft highlights nothing")
    func blankDraftHighlightsNothing() {
        #expect(PlannerSuggestionHighlight.split(text: "Gym", draft: "").match.isEmpty)
        #expect(PlannerSuggestionHighlight.split(text: "Gym", draft: "   ").rest == "Gym")
    }
}
