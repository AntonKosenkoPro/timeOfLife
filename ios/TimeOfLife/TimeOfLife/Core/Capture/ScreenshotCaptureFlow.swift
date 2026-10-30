#if SCREENSHOT_CAPTURE
import Foundation
import SwiftUI
import UIKit

/// The capture run driver: request → preparing → validated native view →
/// `ready` (or `invalid`/`failure`). The state file is the runner's only
/// readiness signal; no overlay is ever rendered into exported images.
@MainActor
final class ScreenshotCaptureModel: ObservableObject {
    enum Phase {
        case preparing
        case ready(ReadyContext)
        case failed(message: String)
    }

    struct ReadyContext {
        let container: AppContainer
        let shellVM: AppShellViewModel
        let snapshot: TrackSnapshot
        let clock: AppClock
        let frame: ScreenshotFrame
        let localeIdentifier: String
    }

    struct Session {
        let clock: AppClock
        let container: AppContainer
        let liveActivity: CaptureStateLiveActivity?
    }

    @Published private(set) var phase: Phase = .preparing
    /// Flipped by the mounted shell's `onAppear` — mount confirmed.
    @Published var mounted = false
    private var didRun = false

    private var stateDirectory: URL?
    private var request: ScreenshotCaptureRequest?

    /// Idempotent entry (the root `.task` may re-fire on identity change;
    /// a second run would only re-prepare the same request).
    func runOnce() async {
        guard !didRun else { return }
        didRun = true
        await run()
    }

    func run() async {
        do {
            try await execute()
        } catch let error as ScreenshotRequestError {
            writeTerminalState(status: Self.terminalStatus(for: error.code), error: error)
            phase = .failed(message: error.detail)
        } catch {
            writeTerminalState(
                status: "failure",
                error: ScreenshotRequestError(code: "unexpected", detail: "\(error)")
            )
            phase = .failed(message: "\(error)")
        }
    }

    /// Request problems are `invalid`; runtime/environment problems are
    /// `failure` (spec: evidence requirement).
    private static func terminalStatus(for code: String) -> String {
        let invalidCodes: Set<String> = [
            "missing-file", "invalid-json", "missing-field", "unsupported-schema",
            "unknown-deck", "unsupported-locale", "unsupported-calendar",
            "unsupported-week-rule", "unsupported-reference", "unsupported-elapsed",
            "unknown-frame", "frame-not-listed", "unknown-mode", "mode-mismatch",
            "bad-filename", "invalid-run-id",
        ]
        return invalidCodes.contains(code) ? "invalid" : "failure"
    }

    private func execute() async throws {
        let documents = try ScreenshotApp.documentsDirectory()
        stateDirectory = documents
        let parsed = try loadParsedRequest(documents: documents)
        // Locale first: every `Locale.current` read below follows the request.
        ScreenshotApp.applyProcessLocale(parsed)
        let context = try await ScreenshotPreparation.prepare(request: parsed)
        let session = try await makeSession(parsed: parsed, context: context)
        let validationElapsed = try await validateAndMount(
            parsed: parsed,
            context: context,
            clock: session.clock,
            container: session.container
        )
        await settleAndSignal(
            totals: context.totals,
            liveActivity: session.liveActivity,
            validationElapsed: validationElapsed
        )
    }

    /// Detection → filename gate → read → validate. Fail-closed at every
    /// step; writes `preparing` once the request is accepted.
    private func loadParsedRequest(documents: URL) throws -> ScreenshotCaptureRequest {
        let detection = ScreenshotLaunch.detect(
            argv: CommandLine.arguments,
            environment: ProcessInfo.processInfo.environment
        )
        guard case let .requested(filename) = detection else {
            // No token: inert (TimeOfLifeApp never mounts this model then —
            // defensive; the placeholder path renders instead).
            phase = .failed(message: "Screenshot capture build requires a launch request.")
            throw ScreenshotRequestError(code: "bad-filename", detail: "No capture launch token.")
        }
        guard filename == ScreenshotCaptureRequest.requestFilename else {
            throw ScreenshotRequestError(code: "bad-filename", detail: "Only '\(ScreenshotCaptureRequest.requestFilename)' is accepted, got '\(filename)'.")
        }
        let fileURL = documents.appendingPathComponent(ScreenshotCaptureRequest.requestFilename)
        guard let data = try? Data(contentsOf: fileURL) else {
            throw ScreenshotRequestError(code: "missing-file", detail: "No capture request at Documents/\(ScreenshotCaptureRequest.requestFilename).")
        }
        let parsed = try ScreenshotRequestLoader.parse(data: data)
        request = parsed
        writeState(status: "preparing", totals: nil, liveActivity: nil, error: nil)
        return parsed
    }

    /// View clock + isolated container for the requested mode. Pinned modes
    /// freeze app time and suppress system timers; realtime runs on the wall
    /// clock with a real foreground ActivityKit request (design §3 vs §4).
    private func makeSession(parsed: ScreenshotCaptureRequest, context: ScreenshotPreparedContext) async throws -> Session {
        let clock: AppClock
        let liveActivities: LiveActivityControlling
        switch parsed.mode {
        case .appClockPinned:
            clock = AppClock(now: { parsed.referenceDate }, calendar: parsed.calendar)
            liveActivities = NoopLiveActivityController()
            // Historical fixtures must not mint system timers, and a previous
            // run's banner must not leak into this run (design §3). Ended
            // ids are recorded by the cleanup path, not here.
            _ = await ScreenshotApp.endFixtureActivities()
        case .liveActivityRealtime:
            clock = AppClock(now: Date.init, calendar: parsed.calendar)
            liveActivities = LiveActivityService {
                UIApplication.shared.applicationState == .active
            }
        }
        let container = ScreenshotApp.makeContainer(
            store: context.store,
            sessionDirectory: context.sessionDirectory,
            liveActivities: liveActivities
        )
        // Sync must never activate in capture (tasks 2.5): fail closed
        // through the state file rather than crashing.
        guard container.syncController.status == .inactive else {
            throw ScreenshotRequestError(code: "sync-active", detail: "Sync must stay inactive in capture.")
        }
        var liveActivity: CaptureStateLiveActivity?
        if parsed.mode == .liveActivityRealtime {
            liveActivity = try await startRealtimeActivity(request: parsed, container: container)
        }
        return Session(clock: clock, container: container, liveActivity: liveActivity)
    }

    /// View-model validation through the REAL view-model paths, then shell
    /// mount. Returns the measured validation duration (scales the settle
    /// grace below). Intervals always resolve against the PINNED reference —
    /// even in realtime mode, where the view clock runs on wall time.
    private func validateAndMount(
        parsed: ScreenshotCaptureRequest,
        context: ScreenshotPreparedContext,
        clock: AppClock,
        container: AppContainer
    ) async throws -> TimeInterval {
        let validationClock = AppClock(now: { parsed.referenceDate }, calendar: parsed.calendar)
        let validationStart = Date()
        try await validateViewModels(request: parsed, container: container, expected: context.totals, clock: validationClock)
        let validationElapsed = Date().timeIntervalSince(validationStart)
        let snapshot = try await container.timerService.loadSnapshot(recentsLimit: TrackViewModel.recentsLimit)
        let shellVM = AppShellViewModel(service: container.timerService, now: clock.now)
        switch parsed.frame {
        case .trackRunning, .liveActivity, .laLock, .laCompact, .laExpanded:
            shellVM.selectedTab = .track
        case .insights:
            shellVM.selectedTab = .insights
        case .history, .addEntry:
            // The Add-entry frame is the History [+] Log Time sheet: the
            // History top viewport sits behind the presented sheet.
            shellVM.selectedTab = .history
        }
        phase = .ready(ReadyContext(
            container: container,
            shellVM: shellVM,
            snapshot: snapshot,
            clock: clock,
            frame: parsed.frame,
            localeIdentifier: parsed.localeIdentifier
        ))
        return validationElapsed
    }

    /// Mounted native view + validated state + runloop settle (bounded grace
    /// scaled from the measured validation): `ready` means the requested
    /// frame is loaded, not just that seeding finished.
    private func settleAndSignal(
        totals: CaptureExpectedTotals,
        liveActivity: CaptureStateLiveActivity?,
        validationElapsed: TimeInterval
    ) async {
        let deadline = Date().addingTimeInterval(10)
        while !mounted, Date() < deadline {
            await Task.yield()
        }
        let grace = min(3, max(1, validationElapsed * 3))
        try? await Task.sleep(nanoseconds: UInt64(grace * 1_000_000_000))
        writeState(status: "ready", totals: totals, liveActivity: liveActivity, error: nil)
    }

    /// Realtime frame (tasks 4.3): same approved content, but the draft is
    /// re-anchored to wall-clock-now minus the elapsed offset and started
    /// through the REAL TimerService/ActivityKit path while foregrounded.
    /// The historical reference is NEVER passed to the system timer.
    private func startRealtimeActivity(
        request: ScreenshotCaptureRequest,
        container: AppContainer
    ) async throws -> CaptureStateLiveActivity {
        _ = await ScreenshotApp.endFixtureActivities()
        let anchor = Date().addingTimeInterval(-request.appElapsed)
        let draftText = ScreenshotFixture.draftText(for: request.localeIdentifier)
        try await container.timerService.startTimerDraft(
            text: draftText,
            categoryIDs: ScreenshotFixture.draftCategoryIDs(for: request.localeIdentifier),
            notes: ScreenshotFixture.draftNotes(for: request.localeIdentifier),
            startedAt: anchor
        )
        let requestedAt = Date()
        guard let activity = await ScreenshotApp.awaitLiveActivity(text: draftText) else {
            throw ScreenshotRequestError(
                code: "live-activity-unavailable",
                detail: "No live activity acknowledged within tolerance (disabled, backgrounded, or refused)."
            )
        }
        return CaptureStateLiveActivity(
            activityID: activity.id,
            startedAt: ScreenshotApp.iso8601(anchor, timeZone: request.timeZone),
            requestAcknowledgedAt: ScreenshotApp.iso8601(requestedAt, timeZone: request.timeZone)
        )
    }

    /// Loads History + Insights through the production view models with the
    /// capture clock and asserts agreement with the fixture totals — the
    /// running draft must not contribute (spec: Running entry remains
    /// uncommitted).
    private func validateViewModels(
        request: ScreenshotCaptureRequest,
        container: AppContainer,
        expected: CaptureExpectedTotals,
        clock: AppClock
    ) async throws {
        let historyVM = HistoryViewModel(
            store: container.localStore,
            undoBuffer: container.undoBuffer,
            now: clock.now,
            calendar: clock.calendar
        )
        await historyVM.load()
        let historyCount = historyVM.dayGroups.reduce(0) { $0 + $1.entries.count }
        guard historyCount == ScreenshotFixture.entryCount else {
            throw ScreenshotRequestError(code: "totals-invalid", detail: "History shows \(historyCount), expected 55.")
        }
        let insightsVM = InsightsViewModel(store: container.localStore, now: clock.now)
        await insightsVM.load()
        let week = insightsVM.breakdown(period: .week, lens: .category, calendar: clock.calendar)
        guard week.totalSeconds == expected.weekSeconds else {
            throw ScreenshotRequestError(code: "totals-invalid", detail: "Insights week \(week.totalSeconds) != \(expected.weekSeconds).")
        }
        let all = insightsVM.breakdown(period: .all, lens: .activity, calendar: clock.calendar)
        guard all.totalSeconds == expected.allSeconds else {
            throw ScreenshotRequestError(code: "totals-invalid", detail: "Insights all-time \(all.totalSeconds) != \(expected.allSeconds).")
        }
        if request.frame == .addEntry {
            try ScreenshotAddEntry.validate(request: request, container: container)
        }
    }

    private func writeState(
        status: String,
        totals: CaptureExpectedTotals?,
        liveActivity: CaptureStateLiveActivity?,
        error: ScreenshotRequestError?
    ) {
        guard let directory = stateDirectory, let request else { return }
        let state = CaptureState(
            status: status,
            requestSHA256: request.sha256,
            deckVersion: request.deckVersion,
            frame: request.frame.rawValue,
            mode: request.mode.rawValue,
            runID: request.runID,
            counts: status == "ready" ? CaptureStateCounts(entries: ScreenshotFixture.entryCount) : nil,
            expectedTotals: totals,
            build: CaptureStateBuild(
                configuration: "Screenshot",
                bundleID: Bundle.main.bundleIdentifier ?? "unknown",
                commit: ScreenshotApp.commitSHA()
            ),
            clocks: CaptureStateClocks(
                referenceLocalISO: ScreenshotCaptureRequest.pinnedReferenceISO,
                referenceDate: ScreenshotApp.iso8601(request.referenceDate, timeZone: request.timeZone),
                timeZone: request.timeZone.identifier
            ),
            liveActivity: liveActivity,
            error: error.map { CaptureStateFailure(code: $0.code, detail: $0.detail) }
        )
        try? CaptureStateWriter.write(state, to: directory)
    }

    private func writeTerminalState(status: String, error: ScreenshotRequestError) {
        if request == nil {
            // No parsed request (bad token / missing file / invalid JSON):
            // emit a minimal state without request-bound fields so the runner
            // still observes a terminal status instead of silence.
            guard let directory = stateDirectory else { return }
            let state = CaptureState(
                status: status,
                requestSHA256: nil,
                deckVersion: nil,
                frame: nil,
                mode: nil,
                runID: nil,
                counts: nil,
                expectedTotals: nil,
                build: CaptureStateBuild(
                    configuration: "Screenshot",
                    bundleID: Bundle.main.bundleIdentifier ?? "unknown",
                    commit: ScreenshotApp.commitSHA()
                ),
                clocks: nil,
                liveActivity: nil,
                error: CaptureStateFailure(code: error.code, detail: error.detail)
            )
            try? CaptureStateWriter.write(state, to: directory)
            return
        }
        writeState(status: status, totals: nil, liveActivity: nil, error: error)
    }
}

/// Capture root: a blank hold while preparing, then the REAL app shell with
/// the capture graph — no substitute views, no overlays in exported images.
struct ScreenshotCaptureRootView: View {
    @ObservedObject var model: ScreenshotCaptureModel

    var body: some View {
        switch model.phase {
        case .preparing:
            Theme.backgroundPrimary
                .ignoresSafeArea()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityHidden(true)
        case let .ready(context):
            AppShellView(
                vm: context.shellVM,
                container: context.container,
                trackSnapshot: context.snapshot,
                clock: context.clock
            )
            .environmentObject(context.container)
            .environmentObject(context.container.sessionStore)
            .environmentObject(context.container.navigation)
            .environmentObject(context.container.syncController)
            // System-provided UI (pickers, system buttons) follows the
            // request locale in the same launch — `AppleLanguages` alone
            // never moves it post-launch (screenshot-capture chrome fix).
            .environment(
                \.locale,
                context.clock.calendar.locale ?? Locale(identifier: context.localeIdentifier)
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onAppear { model.mounted = true }
            // Add-entry frame: the genuine Log Time sheet over the History
            // viewport, prefilled with the fixture sample (draft-only —
            // nothing is saved). Constant binding: the sheet never
            // dismisses during capture.
            .sheet(isPresented: .constant(context.frame == .addEntry)) {
                ScreenshotAddEntrySheet(clock: context.clock, localeIdentifier: context.localeIdentifier)
                    .environmentObject(context.container)
            }
        case let .failed(message):
            VStack(spacing: 12) {
                Text("Screenshot capture unavailable")
                    .font(.headline)
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.backgroundPrimary.ignoresSafeArea())
        }
    }
}
#endif
