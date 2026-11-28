import XCTest

/// Keyboard-stillness + chips-line probe for Today (day-planner 10.2):
/// the spec demands the composer NEVER resign across a submit — no
/// dismiss/reopen flicker of any duration — a single horizontally
/// scrollable chips line pinned between the bottom-fixed composer and the
/// keyboard (visible only while the keyboard is open, floating with a
/// breathing gap above it; empty draft shows the full capped strip,
/// typing prefix-filters it, a draft matching nothing shows the
/// localized no-match placeholder instead of an empty strip, tapping a
/// chip fills the composer and stages its categories without creating a
/// task or starting a timer), no section header over the task rows, a
/// bottom-fixed composer (contrasting card, no visible Add button —
/// Return or the composer's Add accessibility action submits — plus a
/// Track-grammar clear button that empties the draft without dismissing
/// the keyboard), the running row reading the accent `In progress` label
/// (no nav-bar subtitle — the label is the indicator), and
/// every submit prepending at the top with an expanding insertion. Drives the REAL return-key path in a real
/// scene (unit hosts cannot dispatch `onSubmit`), then tight-polls
/// software keyboard presence: any sample without a keyboard fails. A
/// green run with a high sample count proves stillness; a red run
/// reproduces the owner's "closes then reopens" report in automation.
///
/// The `plannerHeaders` seed screen provides one committed entry, so the
/// "Header" prefix shows a chip in the chips line right up to the submit
/// that fills the composer with it.
///
/// Opt-in only (TimeOfLife-HoldHarness scheme): never runs in CI.
/// Requires a simulator with the SOFTWARE keyboard: on a
/// hardware-keyboard-attached sim the field holds focus with no software
/// keyboard, so the chips line correctly stays hidden and this probe has
/// nothing to drive (a fresh standard sim works; the dual-display Duo sim
/// additionally reports broken AX frames for scroll content).
final class PlannerKeyboardStillnessTests: XCTestCase {
    /// Post-Return poll window: covers the dismiss animation plus the
    /// async reopen (store write + reload + focus re-request).
    private let pollSeconds: TimeInterval = 4
    /// Minimum AX samples for a verdict (guards a vacuous pass).
    private let minSamples = 10

    func testKeyboardNeverDisappearsAcrossSubmit() throws {
        continueAfterFailure = false
        let app = HoldHarnessFlow.launchApp(screen: "plannerHeaders")
        let composer = try openTodayComposer(in: app)
        composer.typeText("Header")
        try assertChipWhileTyping(in: app)
        let returnTapped = try submitSeedChip(in: app, via: composer)
        let poll = pollKeyboardPresence(in: app)
        HoldHarnessFlow.attachNote(
            "returnTapped=\(returnTapped) samples=\(poll.samples) misses=\(poll.misses)",
            named: "keyboard-poll",
            to: self
        )
        XCTAssertGreaterThanOrEqual(
            poll.samples, minSamples,
            "poll sampled only \(poll.samples)x in \(pollSeconds)s — no verdict possible"
        )
        if poll.misses > 0 {
            HoldHarnessFlow.attach(XCUIScreen.main.screenshot(), named: "keyboard-gap", to: self)
        }
        XCTAssertEqual(
            poll.misses, 0,
            "keyboard disappeared \(poll.misses)/\(poll.samples) samples across submit (dismiss/reopen flicker)"
        )
        try assertSubmitLanded(in: app, composer: composer)
        XCTAssertTrue(app.keyboards.element.exists, "keyboard gone at settle after submit")
        // Prepend contract (day-planner 12.2): a second submit lands at the top.
        try submitSecondTask(in: app, composer: composer)
        try assertNewestAtTop(in: app)
        try assertComposerBelowList(in: app, composer: composer)
        // Clear contract (day-planner 11.1): the × empties the draft with
        // the keyboard still up.
        try assertClearKeepsKeyboard(in: app, composer: composer)
    }

    /// Opens Today from Track and focuses the composer (keyboard up).
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

    /// The chips line shows while typing (keyboard open), with the seed
    /// chip for the "Header" prefix; the task list is still empty, so no
    /// task row exists yet — and the list carries no section header by
    /// design (day-planner 10.2).
    private func assertChipWhileTyping(in app: XCUIApplication) throws {
        // The ScrollView's AX element type varies by OS; match by
        // identifier across every type.
        guard chipsLine(in: app).waitForExistence(timeout: HoldHarnessFlow.elementTimeout) else {
            throw HoldHarnessError.blocker("PlannerChips line missing while typing (seed entry did not seed?)")
        }
        guard app.buttons["PlannerChip-Header probe"].waitForExistence(timeout: HoldHarnessFlow.elementTimeout) else {
            throw HoldHarnessError.blocker("seed chip missing for the Header prefix")
        }
        XCTAssertFalse(
            app.staticTexts["Suggestions"].exists,
            "retired Suggestions header still present"
        )
    }

    /// Fills the exact seed chip (creates no task, starts no timer), then
    /// submits it with the REAL return-key path: the keyboard's return key
    /// (never typeText("\n"), whose AX round-trip would blind the poll to
    /// the dismiss itself). Falls back to "\n" only when the key is absent.
    private func submitSeedChip(in app: XCUIApplication, via composer: XCUIElement) throws -> Bool {
        let chip = app.buttons["PlannerChip-Header probe"]
        guard chip.waitForExistence(timeout: HoldHarnessFlow.elementTimeout) else {
            throw HoldHarnessError.blocker("seed chip missing for the Header prefix")
        }
        // The chips line mounts with the keyboard animation and the list
        // above resizes under it: wait for the settled, tappable state
        // instead of tapping a mid-animation frame.
        let hittable = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "hittable == true"),
            object: chip
        )
        guard XCTWaiter.wait(for: [hittable], timeout: HoldHarnessFlow.elementTimeout) == .completed else {
            throw HoldHarnessError.blocker("seed chip never became hittable (frame=\(chip.frame))")
        }
        chip.tap()
        // Tapping fills the composer: still no task row (fill must not
        // submit) — the list carries no section header by design.
        XCTAssertNil(
            app.buttons.allElementsBoundByIndex.first {
                $0.identifier.hasPrefix("PlannerName-")
            },
            "chip tap created a task (fill must not submit)"
        )
        for keyID in ["Done", "done", "Return", "return", "Send", "send"] {
            let key = app.keyboards.element.buttons[keyID]
            if key.exists {
                key.tap()
                return true
            }
        }
        composer.typeText("\n")
        return false
    }

    /// Tight-polls software keyboard presence until the window elapses.
    private func pollKeyboardPresence(in app: XCUIApplication) -> (samples: Int, misses: Int) {
        var samples = 0
        var misses = 0
        let deadline = Date().addingTimeInterval(pollSeconds)
        while Date() < deadline {
            samples += 1
            if !app.keyboards.element.exists {
                misses += 1
            }
        }
        return (samples, misses)
    }

    /// The submit must have landed (the probe task reads back as a row),
    /// the draft cleared (chips fall back to the full capped strip while
    /// the keyboard stays open). The task list carries no section header
    /// by design (day-planner 10.2).
    private func assertSubmitLanded(in app: XCUIApplication, composer: XCUIElement) throws {
        // The name sits in a labelled row button, so match the button by
        // label — a staticTexts subscript matches identifiers, not labels.
        let probePredicate = NSPredicate(format: "label == %@", "Header probe")
        let probeAppeared = app.buttons.containing(probePredicate).firstMatch.waitForExistence(
            timeout: HoldHarnessFlow.elementTimeout
        )
        if !probeAppeared {
            attachRowDump(in: app, composer: composer)
        }
        XCTAssertTrue(probeAppeared, "probe task 'Header probe' never appeared — submit did not land")
        XCTAssertTrue(
            chipsLine(in: app).exists,
            "chips line missing after submit (keyboard still open, empty draft shows the full strip)"
        )
    }

    /// Submits a second task after the stillness poll (order
    /// only) and types it via the real keyboard path.
    private func submitSecondTask(in app: XCUIApplication, composer: XCUIElement) throws {
        // No committed entry matches this text, so no chip offers it: the
        // chips line shows the localized no-match placeholder instead of
        // an empty strip (day-planner 11.3), and the typed draft submits
        // as-is.
        composer.typeText("Header sequel")
        let noMatch = app.staticTexts["PlannerChipsNoMatch"]
        guard noMatch.waitForExistence(timeout: HoldHarnessFlow.elementTimeout) else {
            throw HoldHarnessError.blocker("PlannerChipsNoMatch missing for a draft matching nothing")
        }
        for keyID in ["Done", "done", "Return", "return", "Send", "send"] {
            let key = app.keyboards.element.buttons[keyID]
            if key.exists {
                key.tap()
                return
            }
        }
        composer.typeText("\n")
    }

    /// The composer clear button (day-planner 11.1, Track × grammar)
    /// empties the draft without dismissing the keyboard: the line falls
    /// back to the full capped strip while the keyboard stays open.
    private func assertClearKeepsKeyboard(in app: XCUIApplication, composer: XCUIElement) throws {
        composer.typeText("Header sequel")
        let clear = app.buttons["PlannerComposerClear"]
        guard clear.waitForExistence(timeout: HoldHarnessFlow.elementTimeout) else {
            // Diagnostic dump (day-planner 11.1 fails-first): distinguishes
            // an empty draft (typing never landed) from a hidden clear
            // button (visibility condition false) from an AX exposure gap.
            let ids = app.buttons.allElementsBoundByIndex.map {
                "\($0.identifier)[\($0.label)]"
            }.joined(separator: "; ")
            HoldHarnessFlow.attachNote(
                "clear missing; composerValue=\(composer.value as? String ?? "nil") noMatchExists=\(app.staticTexts["PlannerChipsNoMatch"].exists) buttons=[\(ids)]",
                named: "clear-missing",
                to: self
            )
            throw HoldHarnessError.blocker("PlannerComposerClear missing while editing a non-empty draft")
        }
        clear.tap()
        XCTAssertTrue(app.keyboards.element.exists, "keyboard dismissed by the composer clear button")
        // A cleared field exposes its placeholder (or nothing) as its AX
        // value — never the typed draft.
        XCTAssertNotEqual(
            composer.value as? String, "Header sequel",
            "clear did not empty the draft (value=\(composer.value as? String ?? "nil"))"
        )
        guard app.buttons["PlannerChip-Header probe"].waitForExistence(timeout: HoldHarnessFlow.elementTimeout) else {
            throw HoldHarnessError.blocker("full chips strip missing after clearing the draft")
        }
    }

    /// The newest task sits at the top of the list (day-planner 12.2).
    private func assertNewestAtTop(in app: XCUIApplication) throws {
        let rows = app.buttons.allElementsBoundByIndex
            .filter { $0.identifier.hasPrefix("PlannerName-") }
        guard let first = rows.first else {
            throw HoldHarnessError.blocker("no task rows after the second submit")
        }
        XCTAssertEqual(
            first.label, "Header sequel",
            "newest task is not at the top (rows: \(rows.map { $0.label }))"
        )
    }

    /// The composer sits below the list (day-planner 9.1 bottom-fixed
    /// entry): its top edge is at or below the last row's bottom edge.
    private func assertComposerBelowList(in app: XCUIApplication, composer: XCUIElement) throws {
        let rows = app.buttons.allElementsBoundByIndex
            .filter { $0.identifier.hasPrefix("PlannerName-") }
        guard let last = rows.last else {
            throw HoldHarnessError.blocker("no task rows for the placement check")
        }
        XCTAssertGreaterThanOrEqual(
            composer.frame.minY, last.frame.maxY,
            "composer is not below the list (composerTop=\(composer.frame.minY) lastRowBottom=\(last.frame.maxY))"
        )
    }

    /// The chips-line element by identifier across every AX type (the
    /// ScrollView's exposed type varies by OS).
    private func chipsLine(in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)["PlannerChips"]
    }

    private func attachRowDump(in app: XCUIApplication, composer: XCUIElement) {        let rows = app.buttons.allElementsBoundByIndex
            .filter { $0.identifier.hasPrefix("PlannerName-") }
            .map { "\($0.identifier)=\($0.label)" }
            .joined(separator: "; ")
        HoldHarnessFlow.attachNote(
            "probe missing; composerValue=\(composer.value as? String ?? "nil") rows=[\(rows)]",
            named: "submit-landing",
            to: self
        )
        HoldHarnessFlow.attach(XCUIScreen.main.screenshot(), named: "submit-landing", to: self)
    }
}
