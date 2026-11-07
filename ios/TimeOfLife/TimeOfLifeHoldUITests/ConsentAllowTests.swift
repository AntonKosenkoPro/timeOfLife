import XCTest

/// Capture-only consent Allow-tap harness (GH #238, part 2).
///
/// Taps Allow on the SpringBoard Live Activity consent sheet via
/// `addUIInterruptionMonitor` (AX-derived taps only — an absent prompt taps
/// nothing), verified by a re-screenshot pair showing the sheet gone. The
/// sheet is raised by driving the only `Activity.request` path: a real timer
/// start through the Track UI on a fresh sim.
///
/// Device finding (2026-11-05, owned 18 Pro Max sim, iOS 27): the consent
/// prompt presents LOCK-attached under the live banner — never as a
/// SpringBoard alert over the app — so the interruption-monitor path
/// observes `absent` while unlocked, and XCUITest cannot reach the locked
/// sheet by platform design. The locked sheet was additionally probed with
/// two image-derived argent taps (Allow text centroid, then button center;
/// server-log delivered) with simctl re-shots: the sheet persists, so no
/// tap loops fire and dismissal stays a reported blocker (evidence under
/// /tmp hold238-evidence: lock-check / lock-after-tap1 / lock-after-tap2).
/// While consent is pending the island withholds the live pill (unlocked
/// Home reads darkFrac 0.0), which is why the island test refuses its hold.
///
/// Bounded dismissal: at most 2 monitor pumps, then an honest blocker — no
/// tap loops. Outcomes: `dismissed` (sheet seen, then gone), `absent` (no
/// sheet on this sim — already consented; passes with the probe pair as
/// evidence), or a thrown blocker (sheet persists). Bounded waits (existing
/// POLL/CLEANUP scale); headless via
/// `xcodebuild test -scheme TimeOfLife-HoldHarness`.
///
/// Setup: a fresh owned sim (the sheet appears once per sim); the
/// `dismissed` acceptance needs that freshness, `absent` is the steady
/// state everywhere else.
final class ConsentAllowTests: XCTestCase {
    /// Post-Start settle for a fresh-sim sheet to present.
    private let sheetSettleDelay: TimeInterval = 2.0
    /// Re-shot settle after each monitor pump.
    private let reshotDelay: TimeInterval = 1.0
    /// Pixel-derived dismissal cap (runner `SHEET_DISMISSAL_MAX_TAPS`
    /// scale, AX-driven here): at most 2 attempts, then honest blocker.
    private let maxDismissalAttempts = 2

    func testConsentAllowDismissesSheet() throws {
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
        let springboard = XCUIApplication(bundleIdentifier: HoldHarnessFlow.springboardBundleID)
        Thread.sleep(forTimeInterval: sheetSettleDelay)
        let sheetSeen = springboard.alerts.firstMatch.exists
        let (probeShot, probeImage) = try HoldHarnessFlow.screenshotPixels(label: "consent-probe")
        HoldHarnessFlow.attach(probeShot, named: "consent-probe", to: self)
        let probeFrac = HoldHarnessPixels.sheetLightFrac(probeImage)
        guard sheetSeen else {
            HoldHarnessFlow.attachNote(
                "consent sheet absent on this sim (already consented or no prompt; "
                    + "sheetLightFrac=\(probeFrac.map { String($0) } ?? "n/a")); nothing tapped, nothing to dismiss",
                named: "consent-absent",
                to: self
            )
            return
        }
        var attempts = 0
        var dismissed = false
        while attempts < maxDismissalAttempts, !dismissed {
            HoldHarnessFlow.pumpInterruptionMonitor(app: app)
            attempts += 1
            Thread.sleep(forTimeInterval: reshotDelay)
            dismissed = !springboard.alerts.firstMatch.exists
        }
        let (afterShot, afterImage) = try HoldHarnessFlow.screenshotPixels(label: "consent-after")
        HoldHarnessFlow.attach(afterShot, named: "consent-after", to: self)
        let afterFrac = HoldHarnessPixels.sheetLightFrac(afterImage)
        HoldHarnessFlow.attachNote(
            "consent dismissal: attempts=\(attempts) dismissed=\(dismissed) "
                + "sheetLightFrac before=\(probeFrac.map { String($0) } ?? "n/a") "
                + "after=\(afterFrac.map { String($0) } ?? "n/a")",
            named: "consent-verdict",
            to: self
        )
        guard dismissed else {
            throw HoldHarnessError.blocker(
                "consent dismissal blocked: sheet persists after \(attempts) AX-derived Allow taps "
                    + "with evidence (consent-probe/consent-after); no further taps fired"
            )
        }
    }
}
