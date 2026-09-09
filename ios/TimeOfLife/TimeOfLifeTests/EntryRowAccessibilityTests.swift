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

    @Test("rows with provenance fold the via label into the a11y label")
    func viaTextLabel() {
        let label = EntryRow.accessibilityLabel(
            activityName: "Running",
            categoryNames: "Health",
            timeframeText: "14:00 – 15:20",
            durationText: "1h 20m",
            isInProgress: false,
            viaText: L10n.provenanceViaScreentime.text
        )
        #expect(label.contains(L10n.provenanceViaScreentime.text))
    }

    @Test("provenance mapping: non-manual sources localize, manual and unknown are empty")
    func provenanceMapping() {
        #expect(EntryProvenance.viaText(for: "manual").isEmpty)
        #expect(EntryProvenance.viaText(for: "unknown-source").isEmpty)
        #expect(EntryProvenance.viaText(for: "widget") == L10n.provenanceViaWidget.text)
        #expect(EntryProvenance.viaText(for: "siri") == L10n.provenanceViaSiri.text)
        #expect(EntryProvenance.viaText(for: "control") == L10n.provenanceViaControl.text)
        #expect(EntryProvenance.viaText(for: "screentime") == L10n.provenanceViaScreentime.text)
        #expect(EntryProvenance.viaText(for: "garmin") == L10n.provenanceViaGarmin.text)
        #expect(EntryProvenance.viaText(for: "calendar") == L10n.provenanceViaCalendar.text)
        #expect(EntryProvenance.viaText(for: "healthkit") == L10n.provenanceViaHealthkit.text)
    }

    @Test("bare source names localize without the via prefix, manual is empty")
    func provenanceNameMapping() {
        #expect(EntryProvenance.name(for: "manual").isEmpty)
        #expect(EntryProvenance.name(for: "unknown-source").isEmpty)
        #expect(EntryProvenance.name(for: "garmin") == L10n.provenanceNameGarmin.text)
        #expect(!EntryProvenance.name(for: "screentime").contains("via"))
        #expect(!EntryProvenance.name(for: "screentime").contains("через"))
    }

    @Test("detail entry row folds range, provenance, and duration into one label")
    func detailEntryRowLabel() {
        let label = ActivityEntryRow.accessibilityLabel(
            timeRangeText: "2:34 PM – 5:46 PM",
            provenanceName: L10n.provenanceNameGarmin.text,
            durationText: "3h 11m 46s"
        )
        #expect(label.contains("2:34 PM – 5:46 PM"))
        #expect(label.contains("3h 11m 46s"))
        #expect(label.contains(L10n.provenanceNameGarmin.text))
    }
}
