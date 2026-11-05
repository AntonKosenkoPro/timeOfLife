import XCTest

/// Capture-only Dynamic Island long-press harness (GH #238, part 1).
///
/// Long-presses the island pill via `XCUICoordinate.press(forDuration:)` —
/// the single-finger hold the Argent one-shot set provably lacks — at a
/// point derived from the live pre-hold screenshot (bright-content centroid,
/// or the runner-supplied `LIFIO_ISLAND_PRESS_*` override validated inside
/// the verified pill box). The island has no stable AX id, so the point
/// never comes from a hardcoded literal.
///
/// Staged pixels only: the post-hold screenshot is verified in-test
/// (card-band mass AND island-held AND app-chrome rejection, mirroring the
/// runner's `expanded_verdict`/`app_foreground_verdict` geometry logic with
/// no dependency); registration/finalization stay in the Python runner.
///
/// Guards: exactly one hold attempt (a tap opens the app Timer screen
/// instead of expanding — app chrome refuses the card, no retries, no tap
/// loops); the hold fires only against a verified-RUNNING pill inside the
/// hold-open window; bounded waits (existing POLL/CLEANUP scale); headless
/// via `xcodebuild test -scheme TimeOfLife-HoldHarness`.
///
/// Device finding (2026-11-05, owned 18 Pro Max sim, iOS 27): while the
/// lock-attached consent sheet is pending (see ConsentAllowTests) the
/// island withholds the live pill — unlocked Home reads darkFrac 0.0, and
/// only an idle-size pill renders on the lock screen — so the pre-hold gate
/// below refuses the hold instead of pressing blind. A granted-consent sim
/// is the remaining setup for a genuine expanded-card staging.
///
/// Setup: fresh owned iPhone 18 Pro Max sim (1320x2868); the harness starts
/// its own probe run through the real Track UI, so no external activity
/// setup is needed (a RUNNING activity from the hold-open flow is reused
/// when the shell already shows one).
final class IslandExpandedHoldTests: XCTestCase {
    /// Genuine long-press duration for the island hold.
    private let holdDuration: TimeInterval = 1.0
    /// Card-animation settle after the hold (runner `EXPANDED_HOLD_SETTLE_S`).
    private let settleDelay: TimeInterval = 1.5
    /// SpringBoard settle after Home before the pre-hold shot.
    private let homeSettleDelay: TimeInterval = 1.0

    func testIslandLongPressStagesExpandedCard() throws {
        continueAfterFailure = false
        let monitor = HoldHarnessFlow.installConsentMonitor(for: self)
        defer { removeUIInterruptionMonitor(monitor) }
        let app = HoldHarnessFlow.launchApp()
        do {
            try HoldHarnessFlow.startTimerIfIdle(app: app)
        } catch let error as HoldHarnessError {
            HoldHarnessFlow.attach(XCUIScreen.main.screenshot(), named: "settle-failure", to: self)
            throw error
        }
        HoldHarnessFlow.pumpInterruptionMonitor(app: app)
        XCUIDevice.shared.press(.home)
        Thread.sleep(forTimeInterval: homeSettleDelay)
        let (preShot, preImage) = try HoldHarnessFlow.screenshotPixels(label: "pre-hold")
        HoldHarnessFlow.attach(preShot, named: "pre-hold-island", to: self)
        try requireLivePill(image: preImage)
        let point = try HoldHarnessFlow.pressPoint(image: preImage)
        let springboard = XCUIApplication(bundleIdentifier: HoldHarnessFlow.springboardBundleID)
        springboard
            .coordinate(withNormalizedOffset: CGVector(dx: point.x, dy: point.y))
            .press(forDuration: holdDuration)
        Thread.sleep(forTimeInterval: settleDelay)
        let (postShot, postImage) = try HoldHarnessFlow.screenshotPixels(label: "post-hold")
        HoldHarnessFlow.attach(postShot, named: "post-hold-expanded", to: self)
        try requireExpandedCard(image: postImage)
    }

    /// Pre-hold gate: the pill must verify live, or the hold is refused
    /// (never fired blind).
    private func requireLivePill(image: HoldHarnessPixels.DecodedScreenshot) throws {
        let island = HoldHarnessPixels.islandVerdict(image)
        HoldHarnessFlow.attachNote(
            "pre-hold island: live=\(island.live) darkFrac=\(island.darkFrac) bright=\(island.bright) "
                + "geometry=\(image.width)x\(image.height) (\(island.reason))",
            named: "pre-hold-verdict",
            to: self
        )
        guard island.live else {
            throw HoldHarnessError.blocker(
                "refusing blind hold: pre-hold island not live (\(island.reason); "
                    + "darkFrac=\(island.darkFrac) bright=\(island.bright) "
                    + "geometry=\(image.width)x\(image.height)). "
                    + "A RUNNING Lifio activity is required; this harness starts one via Track Start, "
                    + "so a not-live pill means the request never presented (see ConsentAllowTests output)."
            )
        }
    }

    /// Post-hold gate: card-band mass AND island-held AND app-chrome
    /// rejection, mirroring the runner's expanded/app-chrome verdicts.
    private func requireExpandedCard(image: HoldHarnessPixels.DecodedScreenshot) throws {
        let expanded = HoldHarnessPixels.expandedVerdict(image)
        let postIsland = HoldHarnessPixels.islandVerdict(image)
        let islandHeld = postIsland.darkFrac >= HoldHarnessPixels.pillDarkFracMin
        let chrome = HoldHarnessPixels.appChromeVerdict(image)
        HoldHarnessFlow.attachNote(
            "post-hold: expanded=\(expanded.expanded) cardDarkFrac=\(expanded.darkFrac) cardBright=\(expanded.bright) "
                + "(\(expanded.reason)); islandHeld=\(islandHeld) postIslandDarkFrac=\(postIsland.darkFrac); "
                + "appChrome=\(chrome.app) share=\(chrome.share) (\(chrome.reason))",
            named: "post-hold-verdict",
            to: self
        )
        guard expanded.expanded, islandHeld, !chrome.app else {
            var why: [String] = []
            if !expanded.expanded {
                why.append("\(expanded.reason) (darkFrac=\(expanded.darkFrac) bright=\(expanded.bright))")
            }
            if !islandHeld {
                why.append("island pill hidden post-hold (a tap opens the app; expansion refused)")
            }
            if chrome.app {
                why.append("uniform app chrome post-hold (Timer screen, not a card); expansion refused (share=\(chrome.share))")
            }
            throw HoldHarnessError.blocker("no expanded card staged: \(why.joined(separator: "; "))")
        }
    }
}
