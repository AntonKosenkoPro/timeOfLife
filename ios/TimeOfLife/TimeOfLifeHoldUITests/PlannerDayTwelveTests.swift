import XCTest

/// Day-planner §12–§13 probe (TimeOfLife-HoldHarness scheme — opt-in only,
/// never CI): native swipe actions on both edges, top prepend, and instant
/// Track counts, driven on the REAL app (stub graph, `plannerWarm`
/// screen: two open tasks + one completed today).
///
/// - Instant counts: the progress control reads actual counts from its
///   first appearance — the gate preload paints before any reload could
///   converge. The verdict polls from launch and fails if a 0/0 digit
///   shape is EVER observed (the recorded >1s flash).
/// - Top prepend: a composer submit lands the new task first.
/// - Native swipes (§11, restored by §13): swipe right reveals the
///   leading complete/reopen action, swipe left the trailing Delete;
///   tapping activates (leading completes in place, trailing deletes);
///   a full-width swipe deletes with no tap (Mail full-swipe).
/// Count assertions compare digit shapes only (locale-robust: every
/// locale renders `%d` numerals). Action-button labels assume the Hold
/// scheme's English simulator (same as the keyboard keys below).
final class PlannerDayTwelveTests: XCTestCase {
    func testNativeSwipesTopAndInstantCounts() throws {
        continueAfterFailure = false
        let app = HoldHarnessFlow.launchApp(screen: "plannerWarm")
        try assertInstantCounts(in: app)
        let composer = try openToday(in: app)
        try submitOnTop(in: app, via: composer)
        try assertLeadingSwipeCompletes(in: app)
        try assertTrailingSwipeDeletes(in: app)
        try assertFullSwipeDeletes(in: app)
        try assertFinalCounts(in: app)
    }

    // MARK: - Instant counts (12.3)

    /// The progress control shows actual counts from its first appearance
    /// and never a 0/0 shape while settling.
    private func assertInstantCounts(in app: XCUIApplication) throws {
        let progress = app.buttons["PlannerProgressControl"]
        let deadline = Date().addingTimeInterval(HoldHarnessFlow.shellSettleTimeout)
        var firstDigits: String?
        var sawReal = false
        var samples = 0
        while Date() < deadline {
            guard progress.exists else {
                Thread.sleep(forTimeInterval: HoldHarnessFlow.shellPollStep)
                continue
            }
            samples += 1
            let digits = countDigits(progress.label)
            if firstDigits == nil { firstDigits = digits }
            if digits == "00" {
                HoldHarnessFlow.attachNote(
                    "0/0 flash on warm planner data (samples=\(samples))",
                    named: "instant-counts-flash", to: self
                )
                XCTFail("progress control flashed 0/0 on warm planner data")
                return
            }
            if digits == "13" {
                sawReal = true
                break
            }
            Thread.sleep(forTimeInterval: HoldHarnessFlow.shellPollStep)
        }
        HoldHarnessFlow.attachNote(
            "first=\(firstDigits ?? "none") samples=\(samples) sawReal=\(sawReal)",
            named: "instant-counts", to: self
        )
        XCTAssertTrue(sawReal, "progress never showed the seeded 1-of-3 counts (first=\(firstDigits ?? "none"))")
    }

    /// Digit shape of a count label, locale-robust (`Done 1 of 3` → `13`).
    private func countDigits(_ label: String) -> String {
        String(label.filter { $0.isWholeNumber })
    }

    // MARK: - Today entry + top prepend (12.2)

    private func openToday(in app: XCUIApplication) throws -> XCUIElement {
        let progress = app.buttons["PlannerProgressControl"]
        guard progress.waitForExistence(timeout: HoldHarnessFlow.shellSettleTimeout) else {
            throw HoldHarnessError.blocker("PlannerProgressControl missing on Track; cannot open Today")
        }
        progress.tap()
        let composer = app.textFields["PlannerComposerField"]
        guard composer.waitForExistence(timeout: HoldHarnessFlow.elementTimeout) else {
            throw HoldHarnessError.blocker("PlannerComposerField missing on Today")
        }
        composer.tap()
        guard app.keyboards.element.waitForExistence(timeout: HoldHarnessFlow.elementTimeout) else {
            throw HoldHarnessError.blocker("software keyboard never appeared after tapping the composer")
        }
        return composer
    }

    /// A composer submit lands the new task FIRST (prepend, day-planner 12.2).
    private func submitOnTop(in app: XCUIApplication, via composer: XCUIElement) throws {
        composer.typeText("Warm newest")
        for keyID in ["Done", "done", "Return", "return", "Send", "send"] {
            let key = app.keyboards.element.buttons[keyID]
            if key.exists {
                key.tap()
                break
            }
        }
        let labels = waitForStableLabels(in: app)
        XCTAssertEqual(labels.first, "Warm newest", "newest submit is not at the top (rows: \(labels))")
    }

    // MARK: - Native swipes (11.2, restored by 13.1)

    /// Leading swipe: reveal → tap the complete action → the row
    /// completes in place (stays top).
    private func assertLeadingSwipeCompletes(in app: XCUIApplication) throws {
        let id = try rowID(label: "Warm newest", in: app)
        let toggleID = "PlannerToggle-\(id)"
        let before = app.buttons[toggleID].label
        try swipeRow(rowID: id, leading: true, in: app)
        // The revealed action shares the row toggle's label — exclude the
        // row's own button by identifier and tap the action.
        let deadline = Date().addingTimeInterval(HoldHarnessFlow.elementTimeout)
        var acted = false
        while Date() < deadline {
            let candidates = app.buttons.containing(NSPredicate(format: "label == %@", before))
            var tapped = false
            for index in 0..<candidates.count {
                let element = candidates.element(boundBy: index)
                guard element.exists else { break }
                if element.identifier != toggleID {
                    element.tap()
                    tapped = true
                    break
                }
            }
            if tapped {
                acted = true
                break
            }
            Thread.sleep(forTimeInterval: 0.2)
        }
        guard acted else {
            throw HoldHarnessError.blocker("leading swipe action missing after revealing (row Warm newest)")
        }
        let settled = waitUntil(timeout: HoldHarnessFlow.elementTimeout) {
            let toggle = app.buttons[toggleID]
            return toggle.exists && toggle.label != before
        }
        XCTAssertTrue(settled, "leading swipe action did not complete the row (toggle label still \(before))")
        let labels = waitForStableLabels(in: app)
        XCTAssertEqual(labels.first, "Warm newest", "completed row moved (rows: \(labels))")
    }

    /// Trailing swipe: reveal → tap Delete → the row is deleted.
    private func assertTrailingSwipeDeletes(in app: XCUIApplication) throws {
        let id = try rowID(label: "Warm Beta", in: app)
        try swipeRow(rowID: id, leading: false, in: app)
        // English-simulator label (Hold scheme runs en, same as the
        // keyboard keys above).
        let delete = app.buttons["Delete"]
        guard delete.waitForExistence(timeout: HoldHarnessFlow.elementTimeout) else {
            throw HoldHarnessError.blocker("trailing Delete missing after revealing (row Warm Beta)")
        }
        delete.tap()
        XCTAssertTrue(
            waitForRowGone(identifier: "PlannerName-\(id)", in: app),
            "trailing swipe did not delete Warm Beta (rows: \(rowLabels(in: app)))"
        )
    }

    /// Full swipe: a full-width drag deletes at once with no tap (Mail).
    private func assertFullSwipeDeletes(in app: XCUIApplication) throws {
        let id = try rowID(label: "Warm Alpha", in: app)
        try fullSwipeDelete(rowID: id, in: app)
        XCTAssertTrue(
            waitForRowGone(identifier: "PlannerName-\(id)", in: app),
            "full swipe did not delete Warm Alpha (rows: \(rowLabels(in: app)))"
        )
    }

    /// Final convergence back on Track: two completions of two rows.
    private func assertFinalCounts(in app: XCUIApplication) throws {
        app.navigationBars.buttons.element(boundBy: 0).tap()
        let progress = app.buttons["PlannerProgressControl"]
        guard progress.waitForExistence(timeout: HoldHarnessFlow.elementTimeout) else {
            throw HoldHarnessError.blocker("PlannerProgressControl missing after popping Today")
        }
        let settled = waitUntil(timeout: HoldHarnessFlow.shellSettleTimeout) {
            progress.exists && countDigits(progress.label) == "22"
        }
        HoldHarnessFlow.attachNote("final=\(progress.exists ? progress.label : "gone")", named: "final-counts", to: self)
        XCTAssertTrue(settled, "final counts are not 2-of-2 (label=\(progress.exists ? progress.label : "gone"))")
    }

    // MARK: - Drivers

    /// Native swipe on a row: a short press-drag toward the edge. The
    /// system reveals that edge's action (no tap).
    private func swipeRow(rowID id: String, leading: Bool, in app: XCUIApplication) throws {
        let row = rowElement(rowID: id, in: app)
        guard row.waitForExistence(timeout: HoldHarnessFlow.elementTimeout) else {
            throw HoldHarnessError.blocker("row \(id) vanished before the swipe (rows: \(rowLabels(in: app)))")
        }
        let start = row.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(forDuration: 0.1, thenDragTo: start.withOffset(CGVector(dx: leading ? 60 : -60, dy: 0)))
    }

    /// A press-drag across nearly the whole list width at the row's
    /// height: travels past the full-swipe fraction, so the edge action
    /// fires on release with no tap.
    private func fullSwipeDelete(rowID id: String, in app: XCUIApplication) throws {
        let list = app.descendants(matching: .any)["PlannerTaskList"]
        guard list.waitForExistence(timeout: HoldHarnessFlow.elementTimeout) else {
            throw HoldHarnessError.blocker("PlannerTaskList missing for the full-swipe drag")
        }
        let row = rowElement(rowID: id, in: app)
        guard row.waitForExistence(timeout: HoldHarnessFlow.elementTimeout) else {
            throw HoldHarnessError.blocker("row \(id) vanished before the full-swipe drag")
        }
        let listFrame = list.frame
        let midY = (row.frame.minY - listFrame.minY) / listFrame.height
        let start = list.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: midY))
        start.press(
            forDuration: 0.1,
            thenDragTo: list.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: midY))
        )
    }

    private func rowElement(rowID id: String, in app: XCUIApplication) -> XCUIElement {
        app.buttons["PlannerName-\(id)"]
    }

    /// The task-row query in AX order (top-to-bottom, the visual order).
    private func plannerRows(_ app: XCUIApplication) -> XCUIElementQuery {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "PlannerName-"))
    }

    private func rowLabels(in app: XCUIApplication) -> [String] {
        // Exists-guarded per element: a snapshot-publish rebuild between
        // the count and a label read must yield a partial array (the polls
        // retry) instead of a stale-reference test failure.
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

    private func rowIdentifiers(in app: XCUIApplication) -> [String] {
        var out: [String] = []
        let rows = plannerRows(app)
        let count = rows.count
        for index in 0..<count {
            let element = rows.element(boundBy: index)
            guard element.exists else { return out }
            out.append(element.identifier)
        }
        return out
    }

    /// Row labels polled until stable across two consecutive snapshots
    /// (the submit round-trip rebuilds the tree: insertion animation plus
    /// snapshot publish — a single read mid-churn goes stale).
    private func waitForStableLabels(in app: XCUIApplication) -> [String] {
        var last: [String] = []
        var stable = 0
        let deadline = Date().addingTimeInterval(HoldHarnessFlow.elementTimeout)
        while Date() < deadline {
            let current = rowLabels(in: app)
            if !current.isEmpty, current == last {
                stable += 1
                if stable >= 2 { return current }
            } else {
                stable = 0
                last = current
            }
            Thread.sleep(forTimeInterval: 0.3)
        }
        return last
    }

    private func rowID(label: String, in app: XCUIApplication) throws -> String {
        let prefix = "PlannerName-"
        let deadline = Date().addingTimeInterval(HoldHarnessFlow.elementTimeout)
        while Date() < deadline {
            let rows = plannerRows(app)
            for index in 0..<rows.count {
                let element = rows.element(boundBy: index)
                if element.exists, element.label == label, element.identifier.hasPrefix(prefix) {
                    return String(element.identifier.dropFirst(prefix.count))
                }
            }
            Thread.sleep(forTimeInterval: 0.2)
        }
        throw HoldHarnessError.blocker("no row with label \(label) (rows: \(rowLabels(in: app)))")
    }

    private func waitForRowGone(identifier: String, in app: XCUIApplication) -> Bool {
        waitUntil(timeout: HoldHarnessFlow.elementTimeout) {
            !rowIdentifiers(in: app).contains(identifier)
        }
    }

    /// Polls a condition without sleeping past the verdict.
    private func waitUntil(timeout: TimeInterval, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            Thread.sleep(forTimeInterval: 0.2)
        }
        return condition()
    }
}
