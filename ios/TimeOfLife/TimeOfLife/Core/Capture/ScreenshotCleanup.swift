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
    /// Runs the verified reset against an explicit documents directory
    /// (parameterized so tests use a temp dir; the app passes Documents).
    /// The acknowledgement is written in every outcome where the directory
    /// is known — including `mismatch`/`failure`, so the runner never waits
    /// on silence.
    static func perform(documents: URL, invocation: ScreenshotCleanupInvocation) async -> CaptureCleanupState {
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
        let ended = await ScreenshotApp.endFixtureActivities()
        var removedSession = false
        let sessionDir = try? ScreenshotPreparation.sessionDirectory(runID: invocation.runID)
        if let sessionDir, FileManager.default.fileExists(atPath: sessionDir.path) {
            try? FileManager.default.removeItem(at: sessionDir)
            removedSession = !FileManager.default.fileExists(atPath: sessionDir.path)
        }
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
