#if SCREENSHOT_CAPTURE
import Foundation
import SwiftUI

/// Capture-only session reset (tasks 2.5/4.2 support).
///
/// The runner invokes the Screenshot build with
/// `SCREENSHOT_CLEANUP=<run_id> SCREENSHOT_CLEANUP_SHA=<request_sha256>`
/// (values read from the last `capture-state.json`) after exporting a
/// frame's screenshots. This path verifies both values against that same
/// state file, then ends ONLY capture-owned (fixture-text) live activities
/// and removes ONLY the named run's session directory plus the capture
/// prefs domain — never another account, never a global clear. It writes
/// `Documents/capture-cleanup.json` as the acknowledgement. Absent from
/// shipping builds; no production path changes.
@MainActor
enum ScreenshotCleanup {
    /// Suite keys for the pre-capture process-default snapshot. The
    /// snapshot must persist (the cleanup that restores it runs in a
    /// separate process), so it lives in the capture suite — never in
    /// memory, never in the state file. Internal (not private) so tests
    /// can seed an empty snapshot: the real standard domain always falls
    /// through to ambient AppleLanguages/AppleLocale, so "no prior value"
    /// is otherwise unconstructible.
    static let priorSnapshotFlagKey = "screenshot.priorLocaleSnapshotted"
    static let priorLanguagesKey = "screenshot.priorAppleLanguages"
    static let priorLocaleKey = "screenshot.priorAppleLocale"

    /// Snapshots the current `AppleLanguages`/`AppleLocale` standard values
    /// into the capture suite before the first override. First call per
    /// suite wins: a crashed run whose cleanup never restores leaves its
    /// snapshot behind, and that snapshot still holds the true pre-capture
    /// values (every later run only ever wrote capture locales), so
    /// re-snapshotting over it would preserve capture state as "prior".
    /// Domains are injectable so tests never touch the real standard suite.
    static func recordPriorDefaultsIfNeeded(
        suite: UserDefaults = ScreenshotApp.captureSuite(),
        standard: UserDefaults = .standard
    ) {
        guard (suite.object(forKey: priorSnapshotFlagKey) as? Bool) != true else { return }
        if let languages = standard.object(forKey: "AppleLanguages") {
            suite.set(languages, forKey: priorLanguagesKey)
        }
        if let locale = standard.object(forKey: "AppleLocale") {
            suite.set(locale, forKey: priorLocaleKey)
        }
        suite.set(true, forKey: priorSnapshotFlagKey)
    }

    /// Restores the snapshotted process defaults (keys absent before capture
    /// are removed, not zeroed). No-op when nothing was snapshotted.
    static func restorePriorDefaults(
        suite: UserDefaults = ScreenshotApp.captureSuite(),
        standard: UserDefaults = .standard
    ) {
        guard (suite.object(forKey: priorSnapshotFlagKey) as? Bool) == true else { return }
        if let languages = suite.object(forKey: priorLanguagesKey) {
            standard.set(languages, forKey: "AppleLanguages")
        } else {
            standard.removeObject(forKey: "AppleLanguages")
        }
        if let locale = suite.object(forKey: priorLocaleKey) {
            standard.set(locale, forKey: "AppleLocale")
        } else {
            standard.removeObject(forKey: "AppleLocale")
        }
    }

    /// Runs the verified reset against an explicit documents directory
    /// (parameterized so tests use a temp dir; the app passes Documents).
    /// The acknowledgement is written in every outcome where the directory
    /// is known — including `mismatch`/`failure`, so the runner never waits
    /// on silence.
    static func perform(
        documents: URL,
        invocation: ScreenshotCleanupInvocation,
        activityPollTimeout: TimeInterval = 5
    ) async -> CaptureCleanupState {
        guard let prior = try? CaptureStateWriter.read(from: documents) else {
            let ack = CaptureCleanupState(
                status: "failure",
                runID: invocation.runID,
                requestSHA256: invocation.expectedSHA256,
                endedActivityIDs: [],
                removedSession: false,
                error: CaptureStateFailure(code: "no-prior-state", detail: "No readable capture-state.json to verify against; nothing touched.")
            )
            try? CaptureCleanupWriter.write(ack, to: documents)
            return ack
        }
        guard prior.runID == invocation.runID, prior.requestSHA256 == invocation.expectedSHA256 else {
            let ack = CaptureCleanupState(
                status: "mismatch",
                runID: invocation.runID,
                requestSHA256: invocation.expectedSHA256,
                endedActivityIDs: [],
                removedSession: false,
                error: CaptureStateFailure(code: "cleanup-mismatch", detail: "run_id/request_sha256 do not match the last capture state; nothing touched.")
            )
            try? CaptureCleanupWriter.write(ack, to: documents)
            return ack
        }
        // The known live anchor (realtime frames) is targeted by id, not
        // just by draft text: a just-requested anchor can read as `.pending`
        // in this fresh process while older strays are already `.active` —
        // ending by text alone missed exactly the currently-live one
        // (runner stayed `partial`, reboot never clears the banner).
        let ended = await ScreenshotApp.endFixtureActivities(
            expectedActivityID: prior.liveActivity?.activityID,
            timeout: activityPollTimeout
        )
        var removedSession = false
        let sessionDir = try? ScreenshotPreparation.sessionDirectory(runID: invocation.runID)
        if let sessionDir, FileManager.default.fileExists(atPath: sessionDir.path) {
            try? FileManager.default.removeItem(at: sessionDir)
            removedSession = !FileManager.default.fileExists(atPath: sessionDir.path)
        }
        // Restore the pre-capture process defaults BEFORE dropping the
        // suite that holds the snapshot: without this the container keeps
        // the last capture locale and later launches of the screenshots
        // build start in it.
        ScreenshotCleanup.restorePriorDefaults()
        if let suite = UserDefaults(suiteName: ScreenshotApp.captureSuiteName) {
            suite.removePersistentDomain(forName: ScreenshotApp.captureSuiteName)
        }
        let ack = CaptureCleanupState(
            status: "cleaned",
            runID: invocation.runID,
            requestSHA256: invocation.expectedSHA256,
            endedActivityIDs: ended,
            removedSession: removedSession,
            error: nil
        )
        try? CaptureCleanupWriter.write(ack, to: documents)
        return ack
    }
}

/// Cleanup run driver: resolves Documents, performs the verified reset,
/// and renders the inert acknowledgement (never a captured frame).
/// Dev-only diagnostics (SCREENSHOT_CAPTURE builds never ship): hardcoded
/// English is intentional — no .lproj/L10n entries.
@MainActor
final class ScreenshotCleanupModel: ObservableObject {
    @Published private(set) var message = "Cleaning capture session…"
    private var didRun = false
    let invocation: ScreenshotCleanupInvocation

    init(invocation: ScreenshotCleanupInvocation) {
        self.invocation = invocation
    }

    func runOnce() async {
        guard !didRun else { return }
        didRun = true
        guard let documents = try? ScreenshotApp.documentsDirectory() else {
            message = "Cleanup unavailable: no documents directory."
            return
        }
        let ack = await ScreenshotCleanup.perform(documents: documents, invocation: invocation)
        switch ack.status {
        case "cleaned":
            message = "Capture session '\(invocation.runID)' cleaned."
        case "mismatch":
            message = ack.error?.detail ?? "Cleanup request did not match the last capture state."
        default:
            message = ack.error?.detail ?? "Cleanup failed."
        }
    }
}

/// Inert cleanup root (never screenshotted — the runner reads the ack file).
struct ScreenshotCleanupRootView: View {
    @StateObject private var model: ScreenshotCleanupModel

    init(invocation: ScreenshotCleanupInvocation) {
        _model = StateObject(wrappedValue: ScreenshotCleanupModel(invocation: invocation))
    }

    var body: some View {
        Text(model.message)
            .font(.footnote)
            .foregroundStyle(Theme.textSecondary)
            .multilineTextAlignment(.center)
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.backgroundPrimary.ignoresSafeArea())
            .task { await model.runOnce() }
    }
}
#endif
