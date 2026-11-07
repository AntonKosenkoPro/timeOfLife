// swiftlint:disable file_length
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
    private struct PriorFailure: Error {
        let ack: CaptureCleanupState
    }

    /// Loads the last capture state and verifies the invocation's run
    /// identity against it (fail closed — never a blind/global clear). The
    /// acknowledgement is written in every outcome where the directory is
    /// known, so the runner never waits on silence.
    static func loadVerifiedPrior(
        documents: URL,
        invocation: ScreenshotCleanupInvocation
    ) throws -> CaptureState {
        guard let prior = try? CaptureStateWriter.read(from: documents) else {
            let ack = CaptureCleanupState(
                status: "failure",
                runID: invocation.runID,
                requestSHA256: invocation.expectedSHA256,
                endedActivityIDs: [],
                removedSession: false,
                error: CaptureStateFailure(code: "no-prior-state", detail: "No readable capture-state.json to verify against; nothing touched."),
                sessionNonce: invocation.sessionNonce,
                sessionDomain: invocation.sessionDomain,
                finalSeq: invocation.finalSeq,
                removedSessionQueue: false
            )
            try? CaptureCleanupWriter.write(ack, to: documents)
            throw PriorFailure(ack: ack)
        }
        guard prior.runID == invocation.runID, prior.requestSHA256 == invocation.expectedSHA256 else {
            let ack = CaptureCleanupState(
                status: "mismatch",
                runID: invocation.runID,
                requestSHA256: invocation.expectedSHA256,
                endedActivityIDs: [],
                removedSession: false,
                error: CaptureStateFailure(code: "cleanup-mismatch", detail: "run_id/request_sha256 do not match the last capture state; nothing touched."),
                sessionNonce: invocation.sessionNonce,
                sessionDomain: invocation.sessionDomain,
                finalSeq: invocation.finalSeq,
                removedSessionQueue: false
            )
            try? CaptureCleanupWriter.write(ack, to: documents)
            throw PriorFailure(ack: ack)
        }
        return prior
    }

    static func perform(
        documents: URL,
        invocation: ScreenshotCleanupInvocation,
        activityPollTimeout: TimeInterval = 5
    ) async -> CaptureCleanupState {
        let prior: CaptureState
        do {
            prior = try loadVerifiedPrior(documents: documents, invocation: invocation)
        } catch let failure as PriorFailure {
            return failure.ack
        } catch {
            return CaptureCleanupState(
                status: "failure",
                runID: invocation.runID,
                requestSHA256: invocation.expectedSHA256,
                endedActivityIDs: [],
                removedSession: false,
                error: CaptureStateFailure(code: "unexpected", detail: "\(error)"),
                sessionNonce: invocation.sessionNonce,
                sessionDomain: invocation.sessionDomain,
                finalSeq: invocation.finalSeq,
                removedSessionQueue: false
            )
        }
        // Strict v2 session binding: invocations without session tokens are
        // not valid session cleanups (v1 roots and partial token sets never
        // parse at the launch grammar). They fail here without touching
        // anything, even with a matching run and SHA.
        guard invocation.sessionNonce != nil,
              invocation.sessionDomain != nil,
              invocation.finalSeq != nil
        else {
            let ack = CaptureCleanupState(
                status: "mismatch",
                runID: invocation.runID,
                requestSHA256: invocation.expectedSHA256,
                endedActivityIDs: [],
                removedSession: false,
                error: CaptureStateFailure(code: "cleanup-mismatch", detail: "Cleanup invocation carries no session binding; nothing touched."),
                sessionNonce: invocation.sessionNonce,
                sessionDomain: invocation.sessionDomain,
                finalSeq: invocation.finalSeq,
                removedSessionQueue: false
            )
            try? CaptureCleanupWriter.write(ack, to: documents)
            return ack
        }
        // Session binding (protocol v2): the invocation's nonce/domain/final
        // seq must match the persisted accepted transcript — cleanup runs in
        // a fresh process, so the transcript file is the only memory. A
        // consumed-but-unacked command (crash mid-frame) fails closed as an
        // interrupted session rather than a clean one.
        switch resolveTranscript(prior: prior, invocation: invocation, documents: documents) {
        case let .transcript(resolved):
            return await finishCleanup(
                prior: prior,
                invocation: invocation,
                documents: documents,
                transcript: resolved,
                activityPollTimeout: activityPollTimeout
            )
        case let .refused(ack):
            return ack
        }
    }

    private enum TranscriptResolution {
        case transcript([ScreenshotSessionTranscriptEntry])
        case refused(CaptureCleanupState)
    }

    /// Resolves the transcript for cleanup: the invocation's session
    /// binding is verified against the persisted accepted transcript
    /// (unbound invocations never reach here — `perform` rejects them
    /// first). Refusals arrive with their acknowledgement already written.
    private static func resolveTranscript(
        prior: CaptureState,
        invocation: ScreenshotCleanupInvocation,
        documents: URL
    ) -> TranscriptResolution {
        // Session binding is guaranteed by the caller (`perform` rejects
        // unbound invocations before reaching here).
        do {
            return .transcript(try verifySessionTranscript(prior: prior, invocation: invocation, documents: documents))
        } catch let error as ScreenshotRequestError {
            let ack = CaptureCleanupState(
                status: error.code == "interrupted-command" ? "failure" : "mismatch",
                runID: invocation.runID,
                requestSHA256: invocation.expectedSHA256,
                endedActivityIDs: [],
                removedSession: false,
                error: CaptureStateFailure(code: error.code, detail: error.detail),
                sessionNonce: invocation.sessionNonce,
                sessionDomain: invocation.sessionDomain,
                finalSeq: invocation.finalSeq,
                removedSessionQueue: false
            )
            try? CaptureCleanupWriter.write(ack, to: documents)
            return .refused(ack)
        } catch {
            let ack = CaptureCleanupState(
                status: "failure",
                runID: invocation.runID,
                requestSHA256: invocation.expectedSHA256,
                endedActivityIDs: [],
                removedSession: false,
                error: CaptureStateFailure(code: "unexpected", detail: "\(error)"),
                sessionNonce: invocation.sessionNonce,
                sessionDomain: invocation.sessionDomain,
                finalSeq: invocation.finalSeq,
                removedSessionQueue: false
            )
            try? CaptureCleanupWriter.write(ack, to: documents)
            return .refused(ack)
        }
    }

    /// Verified reset: end capture-owned activities by anchor id, remove
    /// only the named run's session directory plus its owned session queue
    /// directory, restore pre-capture process defaults, and acknowledge
    /// with the bound transcript.
    ///
    /// Owned-artifact receipt/clear boundary: cleanup removes the fixture
    /// store directory, the `capture-sessions/<nonce>` queue directory
    /// (queue file, consumed records, end marker — all derived from the
    /// invocation nonce, never another session's), and the capture
    /// preferences domain. The fixed `capture-state.json` /
    /// `capture-cleanup.json` acks always survive for the runner read:
    /// cleanup never deletes evidence the runner polls.
    static func finishCleanup(
        prior: CaptureState,
        invocation: ScreenshotCleanupInvocation,
        documents: URL,
        transcript: [ScreenshotSessionTranscriptEntry],
        activityPollTimeout: TimeInterval
    ) async -> CaptureCleanupState {
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
        let removedSessionQueue = removeOwnedQueue(documents: documents, invocation: invocation)
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
            error: nil,
            sessionNonce: invocation.sessionNonce,
            sessionDomain: invocation.sessionDomain,
            finalSeq: invocation.finalSeq,
            transcript: transcript.isEmpty ? nil : transcript,
            removedSessionQueue: removedSessionQueue
        )
        try? CaptureCleanupWriter.write(ack, to: documents)
        return ack
    }

    /// Removes the invocation's OWNED session queue directory, if a session
    /// invocation names one. The path is derived from the validated nonce —
    /// traversal/symlink escapes fail closed with nothing removed, and no
    /// other nonce's directory is ever touched. Invocations without
    /// session tokens remove nothing here (no queue is staged without a
    /// bound session).
    /// Returns true when no queue directory remains for the nonce.
    static func removeOwnedQueue(documents: URL, invocation: ScreenshotCleanupInvocation) -> Bool {
        guard let nonce = invocation.sessionNonce else { return true }
        let dir: URL
        do {
            dir = try ScreenshotSessionPaths.sessionDirectory(documents: documents, nonce: nonce)
        } catch {
            return false
        }
        guard FileManager.default.fileExists(atPath: dir.path) else { return true }
        try? FileManager.default.removeItem(at: dir)
        return !FileManager.default.fileExists(atPath: dir.path)
    }

    /// Session transcript verification for identity-bound cleanup: the
    /// invocation's nonce/domain/final seq must match the persisted
    /// accepted transcript, and no consumed record may lie outside it.
    /// Throws `cleanup-mismatch` (nothing touched) or
    /// `interrupted-command` (a claim never acked) fail-closed.
    static func verifySessionTranscript(
        prior: CaptureState,
        invocation: ScreenshotCleanupInvocation,
        documents: URL
    ) throws -> [ScreenshotSessionTranscriptEntry] {
        let transcript = prior.transcript ?? []
        guard let nonce = invocation.sessionNonce,
              let domain = invocation.sessionDomain,
              let finalSeq = invocation.finalSeq,
              prior.sessionNonce == nonce,
              prior.sessionDomain == domain,
              let last = transcript.last,
              last.seq == finalSeq,
              last.requestSHA256 == invocation.expectedSHA256
        else {
            throw ScreenshotRequestError(code: "cleanup-mismatch", detail: "Session nonce/domain/final-seq do not match the accepted transcript; nothing touched.")
        }
        if let interruption = orphanedCommandDetail(documents: documents, nonce: nonce, transcript: transcript) {
            throw ScreenshotRequestError(code: "interrupted-command", detail: interruption)
        }
        return transcript
    }

    /// Consumed queue records beyond the accepted transcript prove a crash
    /// between claim and acknowledgement: the session was interrupted, so
    /// cleanup cannot attest a clean transcript. Returns a detail string,
    /// or nil when the consumed set matches the transcript exactly.
    static func orphanedCommandDetail(
        documents: URL,
        nonce: String,
        transcript: [ScreenshotSessionTranscriptEntry]
    ) -> String? {
        let dir: URL
        do {
            dir = try ScreenshotSessionPaths.sessionDirectory(documents: documents, nonce: nonce)
        } catch {
            return nil
        }
        let covered = Set(transcript.map(\.seq))
        let names = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        for name in names where name.hasPrefix("consumed-") && name.hasSuffix(".json") {
            let middle = name.dropFirst("consumed-".count).dropLast(".json".count)
            guard let seq = Int(middle), covered.contains(seq) else {
                return "Consumed command '\(name)' is not in the accepted transcript; the session was interrupted."
            }
        }
        return nil
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
