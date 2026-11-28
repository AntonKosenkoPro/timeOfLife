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
    private let pollSeconds: TimeInterval = 2.5
    /// Blind settle before polling: the 0.25s dismiss animation churns
    /// the AX hierarchy, and raw queries during the transition can fail
    /// the snapshot itself. A re-grab lands well inside the settle; the
    /// waiter below still observes the full absence window.
    private let settleSeconds: TimeInterval = 1
    /// Minimum AX samples for a verdict (guards a vacuous pass).
    private let minSamples = 10

    func testEmptyReturnDismissesAndStaysDismissed() throws {
        continueAfterFailure = false
        let app = HoldHarnessFlow.launchApp(screen: "plannerWarm")
        let composer = try openTodayComposer(in: app)
        let rowsBefore = taskRowCount(in: app)
        guard rowsBefore == 3 else {
            throw HoldHarnessError.blocker(
                "plannerWarm seed missing (rows=\(rowsBefore), want 3) — dismiss would be unverifiable"
            )
        }
        try tapReturnKey(in: app)
        // Blind settle past the dismiss animation (raw AX queries during
        // the transition can fail the snapshot itself), then assert the
        // keyboard never presents for the whole window.
        Thread.sleep(forTimeInterval: settleSeconds)
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
        // Count-only, after a settle past the chips-unmount animation
        // (label resolution mid-animation races the AX snapshot).
        Thread.sleep(forTimeInterval: settleSeconds)
        XCTAssertEqual(
            taskRowCount(in: app),
            rowsBefore,
            "empty Return submitted a task (rows changed)"
        )
        XCTAssertTrue(composer.exists, "composer gone after empty-Return dismiss")
    }

    func testDragDismissesAndKeepsContent() throws {
        continueAfterFailure = false
        // `plannerLong` seeds fifteen open tasks: a scrollable list, so a
        // real drag scrolls and the scroll-view dismiss fires (three rows
        // fit on screen — no scroll, no dismiss — which is why this probe
        // does not reuse `plannerWarm`). AX only exposes RENDERED rows
        // (List virtualizes off-screen rows), so the probe scrolls to
        // materialize the far end instead of counting the whole set.
        let app = HoldHarnessFlow.launchApp(screen: "plannerLong")
        _ = try openTodayComposer(in: app)
        let (list, rowsBefore) = try prepareScrollableList(in: app)
        // The measured drags, retried until one provably scrolls (event
        // synthesis drops flicks on a loaded host — an undelivered swipe
        // is inconclusive, never a verdict). Every delivered swipe is a
        // dismiss attempt: the first absence ends the loop green.
        let dismissed = try performMeasuredDrag(list: list, in: app)
        XCTAssertTrue(dismissed, "scrolling the list did not dismiss the keyboard")
        // Stays dismissed: a full quiet window with zero presence.
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
            "keyboard present \(poll.present)/\(poll.samples) samples after drag (re-grabbed)"
        )
        // Content untouched: both ends of the list still render and the
        // top window counts the same as before the measured drag (a
        // scroll neither submits nor deletes; counts compare the same
        // stable top window, not the virtualized whole).
        list.swipeDown()
        Thread.sleep(forTimeInterval: settleSeconds)
        XCTAssertTrue(seededRow(named: "Long 01", in: app), "first seeded row missing after drag")
        XCTAssertEqual(taskRowCount(in: app), rowsBefore, "visible rows changed after drag")
    }

    /// Scrolls to the far end and back to the top, refocuses the composer,
    /// and returns the list plus the stable top-window row count for the
    /// after-drag comparison (relative — AX exposes only the rendered
    /// visible window, so absolute totals are meaningless here).
    private func prepareScrollableList(in app: XCUIApplication) throws -> (XCUIElement, Int) {
        guard let list = app.descendants(matching: .any)["PlannerTaskList"].firstMatch as XCUIElement?,
              list.waitForExistence(timeout: HoldHarnessFlow.elementTimeout) else {
            throw HoldHarnessError.blocker("PlannerTaskList missing on Today; nothing to drag")
        }
        try materializeFarEnd(list: list, in: app)
        list.swipeDown()
        Thread.sleep(forTimeInterval: settleSeconds)
        list.swipeDown()
        Thread.sleep(forTimeInterval: settleSeconds)
        let rowsBefore = taskRowCount(in: app)
        let composer = app.textFields["PlannerComposerField"]
        composer.tap()
        guard app.keyboards.element.waitForExistence(timeout: HoldHarnessFlow.elementTimeout) else {
            throw HoldHarnessError.blocker("software keyboard never re-appeared before the drag")
        }
        // Let the keyboard finish presenting: a scroll started mid-animation
        // may not engage dismissal (the keyboard is not "up" yet from
        // UIKit's perspective).
        Thread.sleep(forTimeInterval: settleSeconds)
        return (list, rowsBefore)
    }

    /// The measured drags: up to three swipeUps, each followed by an
    /// immediate keyboard check — the first absence ends the loop green.
    /// Returns whether any swipe dismissed; throws a blocker when no swipe
    /// even scrolled (undelivered gestures are inconclusive, never a red).
    private func performMeasuredDrag(list: XCUIElement, in app: XCUIApplication) throws -> Bool {
        var dismissed = false
        var everScrolled = false
        for _ in 1...3 {
            list.swipeUp()
            Thread.sleep(forTimeInterval: 0.5)
            if keyboardDismissed(in: app) {
                dismissed = true
                break
            }
            everScrolled = everScrolled || scrolledPastTop(in: app)
        }
        if !dismissed, !everScrolled {
            throw HoldHarnessError.blocker("measured swipes never scrolled — gestures not delivering on this host")
        }
        return dismissed
    }

    /// Scrolls through the list until the far end materializes (up to five
    /// swipes); throws a blocker when the seed never renders. AX exposes
    /// only rendered rows, so reaching the far end proves scrollability.
    private func materializeFarEnd(list: XCUIElement, in app: XCUIApplication) throws {
        for _ in 1...5 {
            list.swipeUp()
            Thread.sleep(forTimeInterval: settleSeconds)
            if seededRow(named: "Long 15", in: app) { return }
        }
        throw HoldHarnessError.blocker("seeded Long 15 never rendered (list did not scroll full length)")
    }

    /// Whether the top seeded row has virtualized away (a scroll moved
    /// content). Atomic existence check — no waiting (the caller owns
    /// the settle).
    private func scrolledPastTop(in app: XCUIApplication) -> Bool {
        !app.buttons.containing(NSPredicate(format: "label == %@", "Long 01")).firstMatch.exists
    }

    /// Whether the keyboard is currently absent (one immediate sample).
    private func keyboardDismissed(in app: XCUIApplication) -> Bool {
        !app.keyboards.element.exists
    }

    /// Whether the seeded row with a visible AX label currently renders
    /// (atomic existence — DayTwelve precedent).
    private func seededRow(named name: String, in app: XCUIApplication) -> Bool {
        app.buttons.containing(NSPredicate(format: "label == %@", name)).firstMatch
            .waitForExistence(timeout: HoldHarnessFlow.elementTimeout)
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
    /// Runs only after the dismiss animation settles (see the callers),
    /// so the hierarchy is stable and every sample is a real verdict.
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

    /// The visible task-row COUNT (the `PlannerName-` buttons). Count-only:
    /// resolving individual row labels mid-animation races the AX snapshot
    /// (the dismiss settle covers the animation; the count query is atomic).
    private func taskRowCount(in app: XCUIApplication) -> Int {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "PlannerName-")).count
    }
}
