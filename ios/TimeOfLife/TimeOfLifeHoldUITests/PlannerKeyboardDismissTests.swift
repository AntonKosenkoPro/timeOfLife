import XCTest

/// Keyboard-dismiss probes for Today (day-planner §24): the spec demands
/// Return on an empty draft dismiss the keyboard AND the dismissal stick
/// until the user refocuses, and dragging the task list dismiss it too
/// (Messages grammar) — with draft, chips, and selection untouched and
/// nothing submitted. Drives the REAL keyboard path in a real scene:
/// hosted unit tests never present a software keyboard, so they prove
/// first-responder bookkeeping only — this probe owns the actual
/// dismiss/stays-dismissed verdict, on sim AND device (day-planner 24.3).
///
/// Opt-in only (TimeOfLife-HoldHarness scheme): never runs in CI.
final class PlannerKeyboardDismissTests: XCTestCase {
    /// Absence-poll window after the dismiss gesture: covers the dismiss
    /// animation plus any delayed re-grab (the device symptom is a reopen
    /// within ~2s).
    private let pollSeconds: TimeInterval = 3
    /// Minimum AX samples for a verdict (guards a vacuous pass).
    private let minSamples = 10

    func testEmptyReturnDismissesAndStaysDismissed() throws {
        continueAfterFailure = false
        let app = HoldHarnessFlow.launchApp(screen: "plannerWarm")
        let composer = try openTodayComposer(in: app)
        let rowsBefore = taskRows(in: app)
        guard rowsBefore.count == 3 else {
            throw HoldHarnessError.blocker(
                "plannerWarm seed missing (rows=\(rowsBefore.count), want 3) — dismiss would be unverifiable"
            )
        }
        try tapReturnKey(in: app)
        let poll = pollKeyboardAbsence(in: app)
        HoldHarnessFlow.attachNote(
            "samples=\(poll.samples) present=\(poll.present)",
            named: "dismiss-poll",
            to: self
        )
        XCTAssertGreaterThanOrEqual(
            poll.samples, minSamples,
            "poll sampled only \(poll.samples)x in \(pollSeconds)s — no verdict possible"
        )
        if poll.present > 0 {
            HoldHarnessFlow.attach(XCUIScreen.main.screenshot(), named: "dismiss-regrab", to: self)
        }
        XCTAssertEqual(
            poll.present, 0,
            "keyboard present \(poll.present)/\(poll.samples) samples after empty Return (never dismissed, or re-grabbed)"
        )
        // Nothing submitted: the same three seed rows, no probe row.
        XCTAssertEqual(
            taskRows(in: app).map { $0.label }.sorted(),
            rowsBefore.map { $0.label }.sorted(),
            "empty Return submitted a task (rows changed)"
        )
        XCTAssertTrue(composer.exists, "composer gone after empty-Return dismiss")
    }

    func testDragDismissesAndKeepsContent() throws {
        continueAfterFailure = false
        let app = HoldHarnessFlow.launchApp(screen: "plannerWarm")
        _ = try openTodayComposer(in: app)
        let rowsBefore = taskRows(in: app)
        guard rowsBefore.count == 3 else {
            throw HoldHarnessError.blocker(
                "plannerWarm seed missing (rows=\(rowsBefore.count), want 3) — drag needs a list"
            )
        }
        guard let list = app.descendants(matching: .any)["PlannerTaskList"].firstMatch as XCUIElement?,
              list.waitForExistence(timeout: HoldHarnessFlow.elementTimeout) else {
            throw HoldHarnessError.blocker("PlannerTaskList missing on Today; nothing to drag")
        }
        list.swipeUp()
        let poll = pollKeyboardAbsence(in: app)
        HoldHarnessFlow.attachNote(
            "samples=\(poll.samples) present=\(poll.present)",
            named: "drag-dismiss-poll",
            to: self
        )
        XCTAssertGreaterThanOrEqual(
            poll.samples, minSamples,
            "poll sampled only \(poll.samples)x in \(pollSeconds)s — no verdict possible"
        )
        if poll.present > 0 {
            HoldHarnessFlow.attach(XCUIScreen.main.screenshot(), named: "drag-dismiss-regrab", to: self)
        }
        XCTAssertEqual(
            poll.present, 0,
            "keyboard present \(poll.present)/\(poll.samples) samples after drag (never dismissed, or re-grabbed)"
        )
        // Content untouched: same three rows, nothing submitted.
        XCTAssertEqual(
            taskRows(in: app).map { $0.label }.sorted(),
            rowsBefore.map { $0.label }.sorted(),
            "drag submitted or removed a task (rows changed)"
        )
    }

    /// Opens Today from Track and focuses the composer (keyboard up,
    /// proven present — a dismiss probe without a raised keyboard is
    /// vacuous).
    private func openTodayComposer(in app: XCUIApplication) throws -> XCUIElement {
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

    /// Taps the REAL keyboard return key (never typeText("\n"), whose AX
    /// round-trip would blind the poll to the dismiss itself). Waits for
    /// the key to settle hittable first (a mid-animation tap fails to
    /// scroll-to-visible); throws a blocker when the key never settles —
    /// falling back would test a different path than the owner's finger.
    private func tapReturnKey(in app: XCUIApplication) throws {
        var key: XCUIElement?
        for keyID in ["Done", "done", "Return", "return", "Send", "send"] {
            let candidate = app.keyboards.element.buttons[keyID]
            if candidate.exists {
                key = candidate
                break
            }
        }
        guard let key else {
            throw HoldHarnessError.blocker("keyboard return key absent")
        }
        let hittable = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "hittable == true"),
            object: key
        )
        guard XCTWaiter.wait(for: [hittable], timeout: HoldHarnessFlow.elementTimeout) == .completed else {
            throw HoldHarnessError.blocker("keyboard return key never became hittable (frame=\(key.frame))")
        }
        key.tap()
    }

    /// Tight-polls software keyboard ABSENCE until the window elapses.
    private func pollKeyboardAbsence(in app: XCUIApplication) -> (samples: Int, present: Int) {
        var samples = 0
        var present = 0
        let deadline = Date().addingTimeInterval(pollSeconds)
        while Date() < deadline {
            samples += 1
            if app.keyboards.element.exists {
                present += 1
            }
        }
        return (samples, present)
    }

    /// The visible task rows by label (the `PlannerName-` buttons).
    private func taskRows(in app: XCUIApplication) -> [XCUIElement] {
        app.buttons.allElementsBoundByIndex.filter { $0.identifier.hasPrefix("PlannerName-") }
    }
}
