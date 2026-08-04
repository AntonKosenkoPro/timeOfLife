import XCTest

/// AC10 / Phase 9.5 — XCUITest smoke suite for critical rendered flows.
///
/// The app is launched with `UITEST_SCREEN=signedIn` (DEBUG-only stub graph)
/// and `UITEST_SEED_CATALOG=1` so the per-account catalog DB contains
/// deterministic data (Reading / Coding / Designing + Work category + 1 entry).
/// No real backend, no email, no OTP — the flow runs fully offline.
@MainActor
final class CatalogSmokeUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Launches the app onto the signed-in timer with seeded catalog data.
    private func launchSeeded() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["UITEST_SCREEN"] = "signedIn"
        app.launchEnvironment["UITEST_SEED_CATALOG"] = "1"
        app.launchArguments += [
            "UITEST_SCREEN=signedIn",
            "UITEST_SEED_CATALOG=1"
        ]
        app.launch()
        return app
    }

    // MARK: - Suggestion start

    func testSuggestionStartRunsTimer() throws {
        let app = launchSeeded()

        // The most recent activity (Reading) appears as a suggestion.
        let readingSuggestion = app.buttons["TimerSuggestion(uitest-act-1)"]
        XCTAssertTrue(
            readingSuggestion.waitForExistence(timeout: 5),
            "Reading suggestion should appear in the timer suggestions")

        // Selecting it pre-fills the activity field.
        readingSuggestion.tap()
        let activityField = app.textFields["TimerActivityField"]
        XCTAssertTrue(activityField.waitForExistence(timeout: 3))
        XCTAssertEqual(activityField.value as? String, "Reading")

        // Start the timer.
        app.buttons["TimerStartButton"].tap()
        let stopButton = app.buttons["TimerStopButton"]
        XCTAssertTrue(
            stopButton.waitForExistence(timeout: 5),
            "Stop button should appear once the timer is running")

        // Stop saves the entry.
        stopButton.tap()
        XCTAssertTrue(
            app.buttons["TimerStartButton"].waitForExistence(timeout: 5),
            "Timer should return to the start state after stop")
    }

    // MARK: - Quick-add

    func testQuickAddCreatesActivity() throws {
        let app = launchSeeded()

        let quickAdd = app.buttons["TimerQuickAddButton"]
        XCTAssertTrue(quickAdd.waitForExistence(timeout: 5))
        quickAdd.tap()

        let field = app.textFields["QuickAddActivityField"]
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        field.tap()
        field.typeText("Yoga")

        app.buttons["QuickAddSaveButton"].tap()

        // The new activity is selected on the timer.
        let activityField = app.textFields["TimerActivityField"]
        XCTAssertTrue(activityField.waitForExistence(timeout: 5))
        let value = activityField.value as? String
        XCTAssertEqual(value, "Yoga", "Quick-add should select the new activity")
    }

    // MARK: - Manage Activities navigation + editor

    func testManageActivitiesAddAndEdit() throws {
        let app = launchSeeded()

        app.buttons["TimerManageActivitiesButton"].tap()

        let list = app.collectionViews["ManageActivitiesList"]
        guard list.waitForExistence(timeout: 5) else {
            print(app.debugDescription)
            XCTFail("Manage Activities list should appear after navigation")
            return
        }

        // Add a new activity via the toolbar.
        app.buttons["ManageActivitiesAddButton"].tap()
        let editorField = app.textFields["ActivityEditorNameField"]
        XCTAssertTrue(editorField.waitForExistence(timeout: 3))
        editorField.tap()
        editorField.typeText("Writing")
        app.buttons["ActivityEditorSaveButton"].tap()

        // The new activity appears in the list.
        let newRow = list.staticTexts["Writing"]
        XCTAssertTrue(
            newRow.waitForExistence(timeout: 5),
            "Newly created activity should appear in the list")
    }

    // MARK: - Delete confirmation + undo

    func testDeleteActivityAndUndo() throws {
        let app = launchSeeded()

        app.buttons["TimerManageActivitiesButton"].tap()
        let list = app.collectionViews["ManageActivitiesList"]
        guard list.waitForExistence(timeout: 5) else {
            print(app.debugDescription)
            XCTFail("Manage Activities list should appear before deleting")
            return
        }

        // Coding has no entries → swipe-delete shows the simple confirmation.
        let codingRow = app.buttons["ActivityRow(uitest-act-2)"]
        XCTAssertTrue(codingRow.waitForExistence(timeout: 5))
        codingRow.swipeLeft()

        let deleteButton = app.buttons["ActivityDeleteButton(uitest-act-2)"]
        XCTAssertTrue(deleteButton.waitForExistence(timeout: 3))
        deleteButton.tap()

        // Undo toast appears after deletion (activity hidden in undo window).
        let undoButton = app.buttons["UndoToastButton"]
        XCTAssertTrue(
            undoButton.waitForExistence(timeout: 5),
            "Undo toast should appear after deletion")

        undoButton.tap()

        // The row is restored.
        XCTAssertTrue(
            codingRow.waitForExistence(timeout: 5),
            "Activity should be restored after undo")
    }

    // MARK: - Manage Categories navigation

    func testManageCategoriesNavigation() throws {
        let app = launchSeeded()

        app.buttons["TimerManageActivitiesButton"].tap()
        let list = app.collectionViews["ManageActivitiesList"]
        guard list.waitForExistence(timeout: 5) else {
            print(app.debugDescription)
            XCTFail("Manage Activities list should appear before categories navigation")
            return
        }

        app.buttons["ManageActivitiesCategoriesButton"].tap()
        let categoriesList = app.collectionViews["ManageCategoriesList"]
        XCTAssertTrue(
            categoriesList.waitForExistence(timeout: 5),
            "Manage Categories list should appear")
    }
}
