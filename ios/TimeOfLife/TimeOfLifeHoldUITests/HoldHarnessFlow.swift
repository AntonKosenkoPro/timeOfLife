import XCTest

/// Shared UI driver for the capture-only hold harness (GH #238).
///
/// Capture-only: launches the Debug app on the deterministic signed-in
/// shell (`UITEST_SCREEN=signedIn`, stub graph — no network, no OTP) and
/// drives the real Track UI to a running timer, which is the only
/// `Activity.request` path. No app code is referenced or changed.
///
/// Bounded waits throughout (existing POLL/CLEANUP scale, no increases):
/// element waits cap at 10s, alert probes at 5s. Headless-plausible: only
/// XCUITest APIs, no Simulator.app scripting, no AppleScript.
enum HoldHarnessFlow {
    /// Element-settle ceiling per wait (well under POLL_TIMEOUT_S).
    static let elementTimeout: TimeInterval = 10
    /// Cold-start shell settle ceiling: first launch on a busy host can
    /// take far longer than steady-state element waits; still well under
    /// the existing CLEANUP deadline scale (no deadline increased).
    static let shellSettleTimeout: TimeInterval = 30
    /// Cold-start poll step inside the shell settle window.
    static let shellPollStep: TimeInterval = 0.5
    /// Alert-probe ceiling per wait.
    static let alertTimeout: TimeInterval = 5
    /// SpringBoard bundle for island coordinates + alert queries.
    static let springboardBundleID = "com.apple.springboard"
    /// Probe run name typed through the real name picker.
    static let probeName = "Hold probe"
    /// Runner-supplied press-point override keys (normalized 0...1). The
    /// override is honored only inside the verified live pill box;
    /// otherwise the image-derived centroid is used. No key (or an
    /// unparseable one) means image-derived.
    static let pressXKey = "LIFIO_ISLAND_PRESS_X"
    static let pressYKey = "LIFIO_ISLAND_PRESS_Y"

    /// Launches the Debug app on the deterministic signed-in shell. Always
    /// cold-starts (terminate first): a leftover foreground instance from a
    /// prior run would otherwise make this a no-op attach with stale store
    /// state. Terminating never ends a live system activity — the island
    /// pill survives and the probe run reuses the same-text singleton.
    static func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.terminate()
        app.launchEnvironment["UITEST_SCREEN"] = "signedIn"
        app.launch()
        return app
    }

    /// Installs the SpringBoard consent monitor (AX-derived Allow taps
    /// only — an absent prompt answers false and taps nothing). The caller
    /// owns the token and must remove it when done.
    static func installConsentMonitor(for test: XCTestCase) -> NSObjectProtocol {
        test.addUIInterruptionMonitor(withDescription: "Live Activity consent") { element in
            let allow = element.buttons["Allow"]
            guard allow.exists else {
                return false
            }
            allow.tap()
            return true
        }
    }

    /// Pumps an installed interruption monitor once by re-tapping the
    /// selected tab bar item (already on Track — no navigation, no timer
    /// mutation; a tab pop-to-root on an empty path is a no-op). NOTE: the
    /// `TabTrack` identifier lives on the tab *content*, so the bar item
    /// itself is queried positionally through the native tab bar. Falls back
    /// to a center tap (running Track only — the tag area, never Start).
    static func pumpInterruptionMonitor(app: XCUIApplication) {
        let selectedTab = app.tabBars.buttons.firstMatch
        if selectedTab.waitForExistence(timeout: elementTimeout) {
            selectedTab.tap()
        } else {
            app.tap()
        }
    }

    /// Ensures a running timer, starting one through the real Track UI when
    /// idle. Throws an honest blocker (never a blind guess) when the shell
    /// does not settle. Assumes the consent monitor is already installed:
    /// on a fresh sim the request below raises the sheet, which the caller
    /// pumps and verifies.
    static func startTimerIfIdle(app: XCUIApplication) throws {
        let stopButton = app.buttons["TimerStopButton"]
        let startButton = app.buttons["TimerStartButton"]
        // Combined settle poll (not two serial 10s waits): cold start on a
        // busy host lands the shell anywhere inside the window, and either
        // button proves it. Neither within the window is an honest blocker.
        let settleDeadline = Date().addingTimeInterval(shellSettleTimeout)
        var idle = false
        while Date() < settleDeadline {
            if stopButton.exists {
                return
            }
            if startButton.exists {
                idle = true
                break
            }
            Thread.sleep(forTimeInterval: shellPollStep)
        }
        guard idle else {
            throw HoldHarnessError.blocker(
                "Track shell did not settle: neither TimerStopButton nor TimerStartButton appeared "
                    + "within \(shellSettleTimeout)s (UITEST_SCREEN=signedIn launch broken?)"
            )
        }
        try nameProbeRun(app: app, startButton: startButton)
        let armDeadline = Date().addingTimeInterval(elementTimeout)
        while !startButton.isEnabled, Date() < armDeadline {
            Thread.sleep(forTimeInterval: 0.2)
        }
        guard startButton.isEnabled else {
            throw HoldHarnessError.blocker("TimerStartButton stayed disabled after naming the probe run")
        }
        startButton.tap()
        guard stopButton.waitForExistence(timeout: elementTimeout) else {
            throw HoldHarnessError.blocker(
                "TimerStopButton never appeared after Start (timer failed to start; "
                    + "on a fresh sim a consent sheet may be blocking — see ConsentAllowTests)"
            )
        }
    }

    /// Names the probe run through the real name picker (Start needs
    /// non-empty text): opens the picker, types the probe name, commits via
    /// keyboard Done (submitLabel .done) with a Return fallback, and waits
    /// for the pop back to Track.
    private static func nameProbeRun(app: XCUIApplication, startButton: XCUIElement) throws {
        let nameRow = app.buttons["TimerNameRow"]
        guard nameRow.waitForExistence(timeout: elementTimeout) else {
            throw HoldHarnessError.blocker("TimerNameRow missing on idle Track; cannot name the probe run")
        }
        let enabledDeadline = Date().addingTimeInterval(elementTimeout)
        while !nameRow.isEnabled, Date() < enabledDeadline {
            Thread.sleep(forTimeInterval: 0.2)
        }
        guard nameRow.isEnabled else {
            throw HoldHarnessError.blocker("TimerNameRow stayed disabled (first snapshot never settled)")
        }
        nameRow.tap()
        let field = app.textFields["NamePickerField"]
        guard field.waitForExistence(timeout: elementTimeout) else {
            throw HoldHarnessError.blocker("NamePickerField missing after tapping TimerNameRow")
        }
        field.tap()
        field.typeText(probeName)
        if app.keyboards.buttons["Done"].waitForExistence(timeout: alertTimeout) {
            app.keyboards.buttons["Done"].tap()
        } else {
            field.typeText("\n")
        }
        guard startButton.waitForExistence(timeout: elementTimeout) else {
            throw HoldHarnessError.blocker("picker did not pop back to Track after naming the probe run")
        }
    }

    /// Full-screen screenshot decoded to top-first pixels, or an honest
    /// throw (no verdict without pixels).
    static func screenshotPixels(label: String) throws -> (shot: XCUIScreenshot, image: HoldHarnessPixels.DecodedScreenshot) {
        let shot = XCUIScreen.main.screenshot()
        let data = shot.pngRepresentation
        guard let image = HoldHarnessPixels.decode(data) else {
            throw HoldHarnessError.blocker("cannot decode \(label) screenshot (\(data.count) bytes) to pixels; no verdict possible")
        }
        return (shot, image)
    }

    /// Keeps a screenshot for evidence (attachments travel with the result
    /// bundle; nothing is written into git).
    static func attach(_ shot: XCUIScreenshot, named name: String, to test: XCTestCase) {
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        test.add(attachment)
    }

    /// Keeps a one-line verdict summary next to the screenshots.
    static func attachNote(_ note: String, named name: String, to test: XCTestCase) {
        let attachment = XCTAttachment(string: note)
        attachment.name = name
        attachment.lifetime = .keepAlways
        test.add(attachment)
    }

    /// Normalized press point for the island hold: the runner-supplied
    /// override when it parses and lands inside the verified live pill box,
    /// else the image-derived bright-content centroid. Throws when neither
    /// is available — the hold is refused, never fired blind.
    static func pressPoint(image: HoldHarnessPixels.DecodedScreenshot) throws -> (x: Double, y: Double) {
        guard let box = HoldHarnessPixels.islandBox(width: image.width, height: image.height) else {
            throw HoldHarnessError.blocker(
                "press point unattested for geometry \(image.width)x\(image.height); never pressing blind"
            )
        }
        let environment = ProcessInfo.processInfo.environment
        if let rawX = environment[pressXKey], let rawY = environment[pressYKey] {
            if let nx = Double(rawX), let ny = Double(rawY), nx >= 0, nx <= 1, ny >= 0, ny <= 1 {
                let px = nx * Double(image.width)
                let py = ny * Double(image.height)
                guard
                    px >= Double(box.x0), px <= Double(box.x1),
                    py >= Double(box.y0), py <= Double(box.y1)
                else {
                    throw HoldHarnessError.blocker(
                        "runner-supplied press point (\(nx), \(ny)) lands outside the verified pill box; refusing blind hold"
                    )
                }
                return (nx, ny)
            }
        }
        guard let derived = HoldHarnessPixels.islandPressPoint(image) else {
            throw HoldHarnessError.blocker("no image-derived press point (no live content); refusing blind hold")
        }
        return (derived.x, derived.y)
    }
}

/// Honest harness failure: setup or device state blocks the capture, so the
/// test reports the blocker with logs instead of guessing. Thrown errors
/// surface via LocalizedError so the message (not a generic line) is what
/// the result bundle shows.
enum HoldHarnessError: LocalizedError {
    case blocker(String)

    var errorDescription: String? {
        switch self {
        case let .blocker(message):
            return message
        }
    }
}
