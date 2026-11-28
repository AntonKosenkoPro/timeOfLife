import Testing
import Foundation
@testable import TimeOfLife

/// Pins the day-planner single-surface invariants (change `add-day-planner`
/// §5/§12/§15/§16): open and completed rows share one exact height because the
/// Start affordance slot stays mounted in both states, and the running row
/// layers the accent `In progress` label over the same preserved footprint;
/// rows render the ordered set as small icon+name chips under the name (Live
/// Activity cap grammar) with a notes indicator trailing them, and announce
/// name → categories → notes presence (no nav-bar subtitle — the accent
/// label is the indicator). A fresh row expands in at the top (opacity-only
/// under Reduce Motion). The pure helpers below are consumed by `PlannerView`
/// — SwiftUI layout itself is not unit-testable, so the tests pin the helpers
/// (the `ClearButtonVisibility` precedent).
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

    // MARK: - Row categories and notes (15.4, chips 16.1)

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

    // MARK: - Category chips (16.1, Live Activity cap grammar)

    /// The row shows at most two chips with a `+n` overflow — never grows
    /// with the set, so toggling completion (which never changes the set)
    /// keeps the row's exact height.
    @Test("chip slices cap at two with the overflow count")
    func chipSlicesCapAtTwo() {
        let categories = (1...4).map {
            Category(id: "c\($0)", name: "Cat \($0)", icon: CatalogIcon.tag.rawValue)
        }
        #expect(PlannerTaskRow.maxVisibleCategoryChips == 2)
        let empty = PlannerTaskRow.chipSlice(for: [])
        #expect(empty.shown.isEmpty && empty.overflow == 0)
        let one = PlannerTaskRow.chipSlice(for: Array(categories.prefix(1)))
        #expect(one.shown.map(\.id) == ["c1"] && one.overflow == 0)
        let two = PlannerTaskRow.chipSlice(for: Array(categories.prefix(2)))
        #expect(two.shown.map(\.id) == ["c1", "c2"] && two.overflow == 0)
        let four = PlannerTaskRow.chipSlice(for: categories)
        #expect(four.shown.map(\.id) == ["c1", "c2"] && four.overflow == 2)
    }

    @Test("the VoiceOver label announces categories in row order")
    func voiceOverLabelKeepsCategoryOrder() {
        let categories = [
            Category(id: "c1", name: "Work", icon: "briefcase"),
            Category(id: "c2", name: "Gym", icon: "dumbbell"),
        ]
        let label = PlannerTaskRow.accessibilityLabel(task: task(named: "Read"), categories: categories)
        // Name → chips → indicator: the ordered set reads between them.
        #expect(label == ["Read", "Work", "Gym"].joined(separator: ", "))
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
