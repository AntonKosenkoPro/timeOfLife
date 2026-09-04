import Testing
import Foundation
@testable import TimeOfLife

@Suite("EntryRow accessibility")
struct EntryRowAccessibilityTests {

    @Test("row folds category names and timing into a single label")
    func rowFoldsContentIntoLabel() {
        let label = EntryRow.accessibilityLabel(
            activityName: "Deep work",
            categoryNames: "Health, Morning",
            timeframeText: "14:00 – 15:20",
            durationText: "1h 20m",
            isInProgress: false
        )
        #expect(label.contains("Deep work"))
        #expect(label.contains("Health, Morning"))
        #expect(label.contains("14:00 – 15:20"))
        #expect(label.contains("1h 20m"))
    }

    @Test("row without categories omits the category part")
    func noCategoriesLabel() {
        let label = EntryRow.accessibilityLabel(
            activityName: "Reading",
            categoryNames: "",
            timeframeText: "09:00 – 09:33",
            durationText: "33m",
            isInProgress: false
        )
        #expect(label.hasPrefix("Reading"))
        #expect(label.contains("09:00 – 09:33"))
        #expect(!label.contains(", ,"))
    }

    @Test("in-progress rows append the in-progress indicator to the label")
    func inProgressLabel() {
        let label = EntryRow.accessibilityLabel(
            activityName: "Running",
            categoryNames: "",
            timeframeText: "09:00 – In progress",
            durationText: L10n.historyInProgress.text,
            isInProgress: true
        )
        #expect(label.contains(L10n.historyInProgress.text))
    }
}
