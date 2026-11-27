import Testing
import Foundation
@testable import TimeOfLife

/// Pins the day-planner single-surface invariants (change `add-day-planner`
/// §5/§12/§15): open and completed rows share one exact height because the
/// Start affordance slot stays mounted in both states, and the running row
/// layers the `In progress` label over the same preserved footprint; rows
/// announce their ordered categories and notes presence (day-planner 15.4).
/// A fresh row expands in at the top (opacity-only under Reduce Motion).
/// The pure helpers below are consumed by `PlannerView` — SwiftUI layout
/// itself is not unit-testable, so the tests pin the helpers (the
/// `ClearButtonVisibility` precedent).
@Suite("Planner row layout (day-planner 5.3/12.2)")
struct PlannerRowLayoutTests {

    private func task(named name: String, completedOn: String? = nil) -> PlannerTask {
        PlannerTask(id: UUID().uuidString, name: name, positionKey: "500000", completedOn: completedOn)
    }

    // MARK: - Start slot (5.3)

    @Test("open rows mount a visible Start slot")
    func openRowMountsVisibleSlot() {
        let slot = PlannerStartSlot.slot(for: task(named: "Read"), isRunning: false)
        #expect(slot == .visible)
        #expect(slot.showsButton)
        #expect(slot.isHidden == false)
        #expect(slot.showsLabel == false)
    }

    @Test("completed rows keep the slot mounted but hidden")
    func completedRowKeepsHiddenSlot() {
        // The slot stays mounted (layout-preserving) instead of being
        // omitted: the row keeps its exact height and no sibling moves.
        let slot = PlannerStartSlot.slot(for: task(named: "Read", completedOn: "2026-11-25"), isRunning: false)
        #expect(slot == .hiddenPreservingLayout)
        #expect(slot.showsButton == false)
        #expect(slot.isHidden == true)
        #expect(slot.showsLabel == false)
    }

    @Test("the running row reads In progress over the preserved slot")
    func runningRowShowsInProgress() {
        let slot = PlannerStartSlot.slot(for: task(named: "Read"), isRunning: true)
        #expect(slot == .inProgress)
        #expect(slot.showsButton == false)
        #expect(slot.isHidden == true)
        #expect(slot.showsLabel)
    }

    @Test("the running run wins over completion")
    func runningWinsOverCompleted() {
        // A task completed mid-run still carries the live timer.
        let slot = PlannerStartSlot.slot(for: task(named: "Read", completedOn: "2026-11-25"), isRunning: true)
        #expect(slot == .inProgress)
        #expect(slot.showsLabel)
    }

    // MARK: - Row categories and notes (15.4)

    @Test("whitespace-only notes count as empty for the indicator")
    func whitespaceNotesShowNoIndicator() {
        var task = self.task(named: "Read")
        task.notes = "   "
        #expect(PlannerTaskRow.hasNotes(task) == false)
        task.notes = "chapter 3"
        #expect(PlannerTaskRow.hasNotes(task))
        task.notes = ""
        #expect(PlannerTaskRow.hasNotes(task) == false)
    }

    @Test("the VoiceOver label folds in category names and notes presence")
    func voiceOverLabelAnnouncesBoth() {
        var task = self.task(named: "Read")
        task.notes = "chapter 3"
        let categories = [
            Category(id: "c1", name: "Work", icon: "briefcase"),
            Category(id: "c2", name: "Gym", icon: "dumbbell"),
        ]
        let label = PlannerTaskRow.accessibilityLabel(task: task, categories: categories)
        #expect(label.contains("Read"))
        #expect(label.contains("Work"))
        #expect(label.contains("Gym"))
        #expect(label.contains(L10n.historyHasNotes.text))
    }

    @Test("bare rows announce the name alone")
    func bareRowAnnouncesNameAlone() {
        let label = PlannerTaskRow.accessibilityLabel(task: task(named: "Read"), categories: [])
        #expect(label == "Read")
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
