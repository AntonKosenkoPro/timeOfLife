import XCTest

/// Keyboard-stillness + section-header probe for Today (day-planner 6.1/6.2):
/// the spec demands the composer NEVER resign across a submit — no
/// dismiss/reopen flicker of any duration — and Mail-style `Suggestions` /
/// `Tasks` headers over the two list sections. Drives the REAL return-key
/// path in a real scene (unit hosts cannot dispatch `onSubmit`), then
/// tight-polls software keyboard presence: any sample without a keyboard
/// fails. A green run with a high sample count proves stillness; a red run
/// reproduces the owner's "closes then reopens" report in automation.
///
/// The `plannerHeaders` seed screen provides one committed entry, so the
/// "Header" prefix shows a suggestions section under its header right up to
/// the submit that unmounts it.
///
/// Opt-in only (TimeOfLife-HoldHarness scheme): never runs in CI.
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
        try assertHeadersWhileSuggesting(in: app)
        let returnTapped = try submitSeedSuggestion(in: app, via: composer)
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

    /// Both section headers read while suggestions show (the task list is
    /// up with an empty task section under its own header).
    private func assertHeadersWhileSuggesting(in app: XCUIApplication) throws {
        guard app.staticTexts["Suggestions"].waitForExistence(timeout: HoldHarnessFlow.elementTimeout) else {
            throw HoldHarnessError.blocker("Suggestions header missing (seed entry did not seed?)")
        }
        guard app.staticTexts["Tasks"].waitForExistence(timeout: HoldHarnessFlow.elementTimeout) else {
            throw HoldHarnessError.blocker("Tasks header missing while suggestions show")
        }
    }

    /// Fills the exact seed suggestion (creates no task), then submits it
    /// with the REAL return-key path: the keyboard's return key (never
    /// typeText("\n"), whose AX round-trip would blind the poll to the
    /// dismiss itself). Falls back to "\n" only when the key is absent.
    /// Rows match by label: a section-level identifier shadows the row
    /// identifiers in the AX tree, so `PlannerSuggestion-<text>` is not a
    /// reliable query (labels read correctly for VoiceOver regardless).
    private func submitSeedSuggestion(in app: XCUIApplication, via composer: XCUIElement) throws -> Bool {
        let suggestionPredicate = NSPredicate(format: "label == %@", "Header probe")
        let suggestion = app.buttons.containing(suggestionPredicate).firstMatch
        guard suggestion.waitForExistence(timeout: HoldHarnessFlow.elementTimeout) else {
            throw HoldHarnessError.blocker("seed suggestion row missing for the Header prefix")
        }
        suggestion.tap()
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

    /// The submit must have landed (the probe task reads back under Tasks),
    /// the suggestions section unmounted, and the Tasks header persisted.
    private func assertSubmitLanded(in app: XCUIApplication, composer: XCUIElement) throws {
        // The name sits in a labelled row button, so match the button by
        // label — a staticTexts subscript matches identifiers, not labels.
        let probePredicate = NSPredicate(format: "label == %@", "Header probe")
        let probeAppeared = app.buttons.containing(probePredicate).firstMatch.waitForExistence(
            timeout: HoldHarnessFlow.elementTimeout
        )
        if !probeAppeared {
            let rows = app.buttons.allElementsBoundByIndex
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
        XCTAssertTrue(probeAppeared, "probe task 'Header probe' never appeared — submit did not land")
        XCTAssertFalse(
            app.staticTexts["Suggestions"].exists,
            "Suggestions header lingered after the draft cleared"
        )
        XCTAssertTrue(app.staticTexts["Tasks"].exists, "Tasks header missing after submit")
    }
}
