import XCTest

/// Day-planner §15 probe (TimeOfLife-HoldHarness scheme — opt-in only,
/// never CI): task notes end-to-end through the real UI, live bidirectional
/// convergence, and the richer rows, driven on the REAL app (stub graph,
/// `plannerNotes` screen: "Note Alpha" tagged + annotated, bare "Note
/// Beta").
///
/// Flow: instant counts → seeded row announces categories + notes →
/// Start Beta (linked run) → Track retag reaches the task → running row
/// reads `In progress` → sheet notes edit on the running task → row gains
/// the indicator → the running draft carries the notes (sheet→draft).
/// Labels assume the Hold scheme's English simulator (same as the §12
/// probe).
final class PlannerNotesHoldTests: XCTestCase {
    func testNotesLiveSyncAndRicherRows() throws {
        continueAfterFailure = false
        let app = HoldHarnessFlow.launchApp(screen: "plannerNotes")
        try assertInstantCounts(in: app)
        try openToday(in: app)
        try assertSeededRowAnnouncesBoth(in: app)
        let betaID = try startBeta(in: app)
        try assertTrackRetagReachesTask(in: app, betaID: betaID)
        try assertRunningRowReadsInProgress(in: app, betaID: betaID)
        try editRunningTaskNotes(in: app, betaID: betaID)
        try assertDraftCarriesNotes(in: app)
    }

    // MARK: - Counts + seeded row (15.1, 15.4)

    private func assertInstantCounts(in app: XCUIApplication) throws {
        let progress = app.buttons["PlannerProgressControl"]
        let deadline = Date().addingTimeInterval(HoldHarnessFlow.shellSettleTimeout)
        var sawReal = false
        while Date() < deadline {
            guard progress.exists else {
                Thread.sleep(forTimeInterval: HoldHarnessFlow.shellPollStep)
                continue
            }
            if countDigits(progress.label) == "02" {
                sawReal = true
                break
            }
            Thread.sleep(forTimeInterval: HoldHarnessFlow.shellPollStep)
        }
        XCTAssertTrue(sawReal, "progress never showed the seeded 0-of-2 counts (label=\(progress.exists ? progress.label : "gone"))")
    }

    private func openToday(in app: XCUIApplication) throws {
        let progress = app.buttons["PlannerProgressControl"]
        guard progress.waitForExistence(timeout: HoldHarnessFlow.shellSettleTimeout) else {
            throw HoldHarnessError.blocker("PlannerProgressControl missing on Track; cannot open Today")
        }
        progress.tap()
        guard app.textFields["PlannerComposerField"].waitForExistence(timeout: HoldHarnessFlow.elementTimeout) else {
            throw HoldHarnessError.blocker("PlannerComposerField missing on Today")
        }
    }

    /// The seeded row announces its ordered categories and notes presence
    /// (day-planner 15.4: VoiceOver announces both).
    private func assertSeededRowAnnouncesBoth(in app: XCUIApplication) throws {
        let label = try rowLabel(containing: "Note Alpha", in: app)
        XCTAssertTrue(label.contains("Desk Work"), "row does not announce its category (label=\(label))")
        XCTAssertTrue(label.contains("has notes"), "row does not announce its notes (label=\(label))")
    }

    // MARK: - Linked Start (15.2 Track←task link, 15.4 In progress)

    /// Starts the bare task; returns its row id. The Start pops to Track
    /// with the run linked.
    private func startBeta(in app: XCUIApplication) throws -> String {
        let betaID = try rowID(containing: "Note Beta", in: app)
        let start = app.buttons["PlannerStart-\(betaID)"]
        guard start.waitForExistence(timeout: HoldHarnessFlow.elementTimeout) else {
            throw HoldHarnessError.blocker("PlannerStart missing for Note Beta")
        }
        start.tap()
        guard app.buttons["RunningNotesButton"].waitForExistence(timeout: HoldHarnessFlow.elementTimeout) else {
            throw HoldHarnessError.blocker("Track is not running after the linked Start")
        }
        return betaID
    }

    // MARK: - Track→task convergence (15.2)

    /// Toggles the seeded category on the running Track draft, returns to
    /// Today, and expects the running task's row to carry it.
    private func assertTrackRetagReachesTask(in app: XCUIApplication, betaID: String) throws {
        let chip = app.buttons["RunningTagsChip(uitest-note-work)"]
        guard chip.waitForExistence(timeout: HoldHarnessFlow.elementTimeout) else {
            throw HoldHarnessError.blocker("RunningTagsChip(uitest-note-work) missing on Track")
        }
        chip.tap()
        backToToday(in: app)
        let settled = waitUntil(timeout: HoldHarnessFlow.elementTimeout) {
            (try? self.rowLabel(containing: "Note Beta", in: app).contains("Desk Work")) == true
        }
        XCTAssertTrue(settled, "Track retag did not reach the linked task (rows: \(rowLabels(in: app)))")
    }

    /// The running row reads the localized `In progress` label over the
    /// preserved slot instead of any Start button.
    private func assertRunningRowReadsInProgress(in app: XCUIApplication, betaID: String) throws {
        let label = app.staticTexts["PlannerInProgress-\(betaID)"]
        guard label.waitForExistence(timeout: HoldHarnessFlow.elementTimeout) else {
            throw HoldHarnessError.blocker("PlannerInProgress missing for the running task")
        }
        XCTAssertEqual(label.label, "In progress")
        // The slot stays mounted (layout-preserving) with the control
        // hidden and inert — like completed rows, but layered with the
        // label. `exists` is true by design (mounted); hittability proves
        // no Start can fire.
        XCTAssertFalse(
            app.buttons["PlannerStart-\(betaID)"].isHittable,
            "running task mounts a hittable Start button"
        )
    }

    // MARK: - Sheet notes edit (15.1) → draft (15.2)

    /// Edits the running task's notes in the editor sheet: the notes
    /// presenter pushes the shared editor, ✓ writes the draft, Save
    /// closes with the row updated in place.
    private func editRunningTaskNotes(in app: XCUIApplication, betaID: String) throws {
        app.buttons["PlannerName-\(betaID)"].tap()
        guard app.buttons["PlannerEditorSaveButton"].waitForExistence(timeout: HoldHarnessFlow.elementTimeout) else {
            throw HoldHarnessError.blocker("task editor sheet did not open for the running task")
        }
        // The notes presenter carries the card's row identifier (the card
        // chrome owns the AX element — the inner link merges into it).
        app.buttons["PlannerEditorNotesRow"].tap()
        // The pushed editor is the only TextEditor in the hierarchy (the
        // sheet's Name row is a TextField): its appearance proves the push.
        // (The page identifier lands on the editor element, so an
        // `otherElements` query never matches — query the editor directly.)
        let editor = app.textViews.element
        guard editor.waitForExistence(timeout: HoldHarnessFlow.elementTimeout) else {
            throw HoldHarnessError.blocker("notes TextEditor did not push from the sheet notes row")
        }
        editor.tap()
        editor.typeText("live note")
        app.buttons["NotesEditorSaveButton"].tap()
        // The pushed page pops back to the sheet (not to Today): the sheet
        // Save is back and the row is still note-less until it saves.
        let backOnSheet = waitUntil(timeout: HoldHarnessFlow.elementTimeout) {
            !app.textViews.element.exists
                && app.buttons["PlannerEditorSaveButton"].exists
        }
        guard backOnSheet else {
            throw HoldHarnessError.blocker("sheet lost after the notes ✓ (popped instead of staying)")
        }
        app.buttons["PlannerEditorSaveButton"].tap()
        let settled = waitUntil(timeout: HoldHarnessFlow.elementTimeout) {
            !app.buttons["PlannerEditorSaveButton"].exists
                && (try? self.rowLabel(containing: "Note Beta", in: app).contains("has notes")) == true
        }
        XCTAssertTrue(settled, "sheet save did not close with the notes indicator (rows: \(rowLabels(in: app)))")
    }

    /// The running draft carries the sheet-saved notes (task→draft). The
    /// sheet save posts the convergence event and Track reloads its
    /// in-memory snapshot — the notes button's value converges first, so
    /// the editor is only opened once Track carries the text (no reload
    /// race).
    private func assertDraftCarriesNotes(in app: XCUIApplication) throws {
        backToTrack(in: app)
        let button = app.buttons["RunningNotesButton"]
        guard button.waitForExistence(timeout: HoldHarnessFlow.elementTimeout) else {
            throw HoldHarnessError.blocker("RunningNotesButton missing on Track")
        }
        let converged = waitUntil(timeout: HoldHarnessFlow.shellSettleTimeout) {
            (button.value as? String)?.contains("live note") == true
        }
        XCTAssertTrue(converged, "Track did not converge the sheet-saved notes (value=\(button.value ?? "nil"))")
        button.tap()
        let editor = app.textViews.element
        guard editor.waitForExistence(timeout: HoldHarnessFlow.elementTimeout) else {
            throw HoldHarnessError.blocker("running notes TextEditor did not open on Track")
        }
        let deadline = Date().addingTimeInterval(HoldHarnessFlow.elementTimeout)
        var value = ""
        while Date() < deadline {
            if let current = editor.value as? String, current.contains("live note") {
                value = current
                break
            }
            Thread.sleep(forTimeInterval: 0.2)
        }
        XCTAssertTrue(value.contains("live note"), "running draft does not carry the sheet-saved notes (value=\(value))")
    }

    // MARK: - Drivers (PlannerDayTwelveTests grammar)

    private func backToToday(in app: XCUIApplication) {
        let progress = app.buttons["PlannerProgressControl"]
        guard progress.waitForExistence(timeout: HoldHarnessFlow.shellSettleTimeout) else { return }
        progress.tap()
    }

    private func backToTrack(in app: XCUIApplication) {
        app.navigationBars.buttons.element(boundBy: 0).tap()
    }

    private func countDigits(_ label: String) -> String {
        String(label.filter { $0.isWholeNumber })
    }

    private func plannerRows(_ app: XCUIApplication) -> XCUIElementQuery {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "PlannerName-"))
    }

    private func rowLabels(in app: XCUIApplication) -> [String] {
        var out: [String] = []
        let rows = plannerRows(app)
        let count = rows.count
        for index in 0..<count {
            let element = rows.element(boundBy: index)
            guard element.exists else { return out }
            out.append(element.label)
        }
        return out
    }

    private func rowLabel(containing text: String, in app: XCUIApplication) throws -> String {
        let deadline = Date().addingTimeInterval(HoldHarnessFlow.elementTimeout)
        while Date() < deadline {
            let rows = plannerRows(app)
            for index in 0..<rows.count {
                let element = rows.element(boundBy: index)
                if element.exists, element.label.contains(text) {
                    return element.label
                }
            }
            Thread.sleep(forTimeInterval: 0.2)
        }
        throw HoldHarnessError.blocker("no row containing \(text) (rows: \(rowLabels(in: app)))")
    }

    private func rowID(containing text: String, in app: XCUIApplication) throws -> String {
        let prefix = "PlannerName-"
        let deadline = Date().addingTimeInterval(HoldHarnessFlow.elementTimeout)
        while Date() < deadline {
            let rows = plannerRows(app)
            for index in 0..<rows.count {
                let element = rows.element(boundBy: index)
                if element.exists, element.label.contains(text), element.identifier.hasPrefix(prefix) {
                    return String(element.identifier.dropFirst(prefix.count))
                }
            }
            Thread.sleep(forTimeInterval: 0.2)
        }
        throw HoldHarnessError.blocker("no row id containing \(text) (rows: \(rowLabels(in: app)))")
    }

    private func waitUntil(timeout: TimeInterval, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            Thread.sleep(forTimeInterval: 0.2)
        }
        return condition()
    }
}
