// swiftlint:disable file_length
#if SCREENSHOT_CAPTURE
import Foundation
import SwiftUI
import UIKit

/// Batched session controller (tasks 3.x): one fresh process per
/// locale/pass/domain reuses a single seeded store across its story frames.
/// Each command rebuilds the native root revision (fresh shell identity, so
/// all view-local state resets), revalidates real view models + fixture
/// fingerprint + pinned clock, and binds mount/settle readiness to the
/// active revision. Late callbacks from an old root are ignored.
@MainActor
final class ScreenshotSessionController: ObservableObject {
    typealias ActivityStarter = (ScreenshotCaptureRequest, AppContainer) async throws -> CaptureStateLiveActivity

    struct Revision: Equatable {
        let nonce: String
        let seq: Int
        let id: UUID
    }

    enum DrainResult: Equatable {
        case empty
        case ready(frame: ScreenshotFrame, seq: Int)
        case failed(code: String)
    }

    enum Phase {
        case idle
        case presenting
        case terminal(message: String)
    }

    struct ActiveSession {
        let validator: ScreenshotSessionValidator
        let clock: AppClock
        let container: AppContainer
        let store: LocalStore
        let sessionDirectory: URL
        let totals: CaptureExpectedTotals
        let seedCategories: Int
        let seedEntries: Int
        var liveActivity: CaptureStateLiveActivity?
    }

    private static let mountDeadline: TimeInterval = 10
    private static let queuePollNanos: UInt64 = 250_000_000

    private let documents: URL
    private let activityStarter: ActivityStarter
    private var session: ActiveSession?
    /// Grace after mounting, defaulting to the existing validation-scaled
    /// formula; injectable so tests prove readiness without the delay.
    var settleGraceProvider: (TimeInterval) -> TimeInterval = { min(3, max(1, $0 * 3)) }
    /// Test hook: mount the active revision on the first poll iteration so
    /// tests prove the revision gate without a hosted view hierarchy.
    var autoMountInTests = false

    @Published private(set) var phase: Phase = .idle
    private(set) var transcript: [ScreenshotSessionTranscriptEntry] = []
    /// View-observed revision state: every assignment below invalidates the
    /// capture root so the next frame mounts (a same-case `phase` change
    /// alone would not re-render).
    @Published private(set) var revision: Revision?
    @Published private(set) var mountedFrame: ScreenshotFrame?
    @Published private(set) var activeFrame: ScreenshotFrame?
    @Published private(set) var shellVM: AppShellViewModel?
    @Published private(set) var snapshot: TrackSnapshot?
    @Published private(set) var viewClock: AppClock?
    private(set) var timings = ScreenshotSessionTimings()
    private(set) var pollAttempts = 0
    private var launches = 0
    private var terminalCode: String?

    init(documents: URL, activityStarter: ActivityStarter? = nil) {
        self.documents = documents
        self.activityStarter = activityStarter ?? Self.defaultActivityStarter
    }

    func recordRequestParse(nanos: UInt64) {
        timings.add(phase: "request_parse", elapsedNanos: nanos, count: 1)
    }

    /// Session init: locale first, one isolated store + seed, one container,
    /// one real-time anchor when applicable, then the seq-0 command.
    struct PreparedSession {
        let clock: AppClock
        let container: AppContainer
        let store: LocalStore
        let sessionDirectory: URL
        let totals: CaptureExpectedTotals
        let seedCategories: Int
        let seedEntries: Int
        var liveActivity: CaptureStateLiveActivity?
    }

    func start(initial envelope: ScreenshotSessionEnvelope) async -> CaptureState {
        do {
            guard envelope.seq == 0 else {
                throw ScreenshotRequestError(code: "bad-seq", detail: "Initial command must be seq 0, got \(envelope.seq).")
            }
            ScreenshotApp.applyProcessLocale(envelope.request)
            let prepared = try await prepareSession(request: envelope.request, domain: envelope.domain)
            // Retained record for the initial command: the seq-0 file is
            // consumed in place (no queue round-trip), so the record proves
            // acceptance for replay and orphan checks like every later seq.
            try retainInitialCommand(documents: documents, envelope: envelope)
            session = ActiveSession(
                validator: try ScreenshotSessionValidator(initial: envelope),
                clock: prepared.clock,
                container: prepared.container,
                store: prepared.store,
                sessionDirectory: prepared.sessionDirectory,
                totals: prepared.totals,
                seedCategories: prepared.seedCategories,
                seedEntries: prepared.seedEntries,
                liveActivity: prepared.liveActivity
            )
            launches = 1
            transcript = session?.validator.transcript ?? []
            return await execute(envelope)
        } catch let error as ScreenshotRequestError {
            return terminal(status: Self.terminalStatus(for: error.code), error: error)
        } catch {
            let wrapped = ScreenshotRequestError(code: "unexpected", detail: "\(error)")
            return terminal(status: "failure", error: wrapped)
        }
    }

    /// One isolated store + seed through the existing mutation boundary,
    /// one container with sync never activated, one real-time anchor when
    /// applicable. Normal migrations, no schema fast path, no outbox bypass.
    private func prepareSession(request: ScreenshotCaptureRequest, domain: ScreenshotSessionDomain) async throws -> PreparedSession {
        let seedStart = ScreenshotSessionClock.nowNanos()
        let prepared = try await ScreenshotPreparation.prepare(request: request)
        let entries = try await prepared.store.entries()
        timings.add(phase: "seed", elapsedNanos: ScreenshotSessionClock.nowNanos() - seedStart, count: entries.count)
        let clock: AppClock
        let liveActivities: LiveActivityControlling
        switch domain {
        case .pinned:
            clock = AppClock(now: { request.referenceDate }, calendar: request.calendar)
            liveActivities = NoopLiveActivityController()
            _ = await ScreenshotApp.endFixtureActivities()
        case .realtime:
            clock = AppClock(now: Date.init, calendar: request.calendar)
            liveActivities = LiveActivityService {
                UIApplication.shared.applicationState == .active
            }
        }
        let container = ScreenshotApp.makeContainer(
            store: prepared.store,
            sessionDirectory: prepared.sessionDirectory,
            liveActivities: liveActivities
        )
        try Self.verifyIsolation(container: container)
        var liveActivity: CaptureStateLiveActivity?
        if domain == .realtime {
            let anchorStart = ScreenshotSessionClock.nowNanos()
            liveActivity = try await activityStarter(request, container)
            timings.add(phase: "anchor", elapsedNanos: ScreenshotSessionClock.nowNanos() - anchorStart, count: 1)
        }
        let categories = try await prepared.store.categories()
        return PreparedSession(
            clock: clock,
            container: container,
            store: prepared.store,
            sessionDirectory: prepared.sessionDirectory,
            totals: prepared.totals,
            seedCategories: categories.count,
            seedEntries: entries.count,
            liveActivity: liveActivity
        )
    }

    /// One watcher step: claim at most one queued command and execute it.
    /// Empty queue is a no-op. After a terminal state, queued end-of-session
    /// commands are refused without touching files.
    func drainOne() async -> DrainResult {
        if let code = terminalCode { return .failed(code: code) }
        guard let active = session else { return .failed(code: "no-session") }
        pollAttempts += 1
        let claimed: ScreenshotSessionEnvelope
        do {
            let result = try ScreenshotSessionClaim.poll(
                documents: documents,
                nonce: active.validator.initial.nonce,
                consumedSeqs: Set(transcript.map(\.seq))
            )
            switch result {
            case .empty:
                return .empty
            case let .claimed(envelope):
                claimed = envelope
            }
        } catch let error as ScreenshotRequestError {
            _ = terminal(status: Self.terminalStatus(for: error.code), error: error)
            return .failed(code: error.code)
        } catch {
            _ = terminal(status: "failure", error: ScreenshotRequestError(code: "unexpected", detail: "\(error)"))
            return .failed(code: "unexpected")
        }
        let ack = await execute(claimed)
        if ack.status == "ready" {
            return .ready(frame: claimed.frame, seq: claimed.seq)
        }
        return .failed(code: ack.error?.code ?? "failure")
    }

    /// Session run loop for the entry view: start, then drain until a
    /// terminal state or task cancellation. Cancellation is cooperative and
    /// prompt (checked every poll); it never executes a further command.
    func runUntilTerminal(initial envelope: ScreenshotSessionEnvelope) async {
        _ = await start(initial: envelope)
        while terminalCode == nil {
            if Task.isCancelled { return }
            switch await drainOne() {
            case .empty:
                try? await Task.sleep(nanoseconds: Self.queuePollNanos)
            case .ready:
                continue
            case .failed:
                return
            }
        }
    }

    /// Revision-tagged mount callback. Only the active revision authorizes
    /// readiness; late callbacks from a previous root are ignored.
    @discardableResult
    func noteMounted(revision: Revision) -> Bool {
        guard let active = self.revision, active == revision else { return false }
        mountedFrame = activeFrame
        return true
    }

    /// Retained consumed record for the initial command (mirrors the queue
    /// claim path: replay and orphan checks treat every accepted seq alike).
    private func retainInitialCommand(documents: URL, envelope: ScreenshotSessionEnvelope) throws {
        let dir = try ScreenshotSessionPaths.sessionDirectory(documents: documents, nonce: envelope.nonce)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let record = try ScreenshotSessionEnvelopeLoader.makeOuter(
            payload: Data(envelope.requestJSON.utf8),
            runID: envelope.runID,
            nonce: envelope.nonce,
            domain: envelope.domain,
            seq: envelope.seq
        )
        try record.write(
            to: dir.appendingPathComponent(ScreenshotSessionPaths.consumedFilename(seq: envelope.seq)),
            options: .atomic
        )
    }

    /// Capture isolation gate: sync is constructed but never activated, so
    /// no network synchronization can run in a session. Test-injectable by
    /// construction (a container whose sync was activated must fail here).
    static func verifyIsolation(container: AppContainer) throws {
        guard container.syncController.status == .inactive else {
            throw ScreenshotRequestError(code: "sync-active", detail: "Sync must stay inactive in capture.")
        }
    }

    /// Test-only store access (fixture fingerprint assertions).
    func testStore() -> LocalStore {
        guard let session else {
            fatalError("ScreenshotSessionController.testStore: no active session.")
        }
        return session.store
    }

    /// Test-only revision advance (proves stale callbacks are ignored).
    func testOnlyBumpRevision() {
        guard let active = revision else { return }
        revision = Revision(nonce: active.nonce, seq: active.seq, id: UUID())
    }

    // MARK: - Command execution

    private func execute(_ envelope: ScreenshotSessionEnvelope) async -> CaptureState {
        guard let active = session else {
            return terminal(status: "failure", error: ScreenshotRequestError(code: "no-session", detail: "No active session."))
        }
        do {
            if envelope.seq != active.validator.initial.seq {
                try active.validator.validate(envelope)
            }
            transcript = active.validator.transcript
            writeState(status: "preparing", totals: nil, liveActivity: active.liveActivity, error: nil)
            let validationElapsed = try await validateCommand(
                envelope: envelope,
                container: active.container,
                expected: active.totals
            )
            try await presentRevision(envelope: envelope, container: active.container, clock: active.clock)
            try await awaitMount(envelope: envelope)
            try await verifyFixtureFingerprint(envelope: envelope, store: active.store, expected: active.totals)
            let settleStart = ScreenshotSessionClock.nowNanos()
            try? await Task.sleep(nanoseconds: UInt64(settleGraceProvider(validationElapsed) * 1_000_000_000))
            timings.add(phase: "settle", elapsedNanos: ScreenshotSessionClock.nowNanos() - settleStart, count: 1)
            guard mountedFrame == envelope.frame else {
                throw ScreenshotRequestError(code: "mount-timeout", detail: "Mount revision changed during settling.")
            }
            let ack = writeState(status: "ready", totals: active.totals, liveActivity: active.liveActivity, error: nil)
            return ack
        } catch let error as ScreenshotRequestError {
            return terminal(status: Self.terminalStatus(for: error.code), error: error)
        } catch {
            return terminal(status: "failure", error: ScreenshotRequestError(code: "unexpected", detail: "\(error)"))
        }
    }

    /// Real view-model validation through the production paths (never a
    /// mock drawing). Returns the validation duration in seconds, which
    /// scales the settle grace below.
    private func validateCommand(
        envelope: ScreenshotSessionEnvelope,
        container: AppContainer,
        expected: CaptureExpectedTotals
    ) async throws -> TimeInterval {
        let validationStart = ScreenshotSessionClock.nowNanos()
        try await validateViewModels(request: envelope.request, container: container, expected: expected)
        let elapsedNanos = ScreenshotSessionClock.nowNanos() - validationStart
        timings.add(phase: "validation", elapsedNanos: elapsedNanos, count: 1)
        return Double(elapsedNanos) / 1_000_000_000.0
    }

    /// Deterministic per-command presentation: a fresh view identity
    /// recreates the shell subtree, resetting paths, search, tab, lens,
    /// period, scroll, and sheet state for this revision.
    private func presentRevision(envelope: ScreenshotSessionEnvelope, container: AppContainer, clock: AppClock) async throws {
        let loaded = try await container.timerService.loadSnapshot(recentsLimit: TrackViewModel.recentsLimit)
        let shellVM = AppShellViewModel()
        switch envelope.frame {
        case .trackRunning, .laLock, .laCompact, .laExpanded:
            shellVM.selectedTab = .track
        case .insights:
            shellVM.selectedTab = .insights
        case .history, .addEntry:
            shellVM.selectedTab = .history
        }
        // Deterministic navigation: no pushes ever occur in capture, but a
        // shared container must not carry a pushed route across frames.
        container.navigation.path = []
        self.shellVM = shellVM
        self.snapshot = loaded
        self.viewClock = clock
        self.activeFrame = envelope.frame
        self.mountedFrame = nil
        self.revision = Revision(nonce: envelope.nonce, seq: envelope.seq, id: UUID())
        self.phase = .presenting
    }

    /// Mounted native view within the existing deadline (never ready on
    /// blank). The mount callback must carry the active revision.
    private func awaitMount(envelope: ScreenshotSessionEnvelope) async throws {
        let mountStart = ScreenshotSessionClock.nowNanos()
        let deadline = Date().addingTimeInterval(Self.mountDeadline)
        while mountedFrame != envelope.frame, Date() < deadline {
            if Task.isCancelled { break }
            if autoMountInTests, let rev = revision { noteMounted(revision: rev) }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        timings.add(phase: "mount_wait", elapsedNanos: ScreenshotSessionClock.nowNanos() - mountStart, count: 1)
        guard mountedFrame == envelope.frame, revision?.nonce == envelope.nonce, revision?.seq == envelope.seq else {
            throw ScreenshotRequestError(code: "mount-timeout", detail: "Capture shell did not mount revision \(envelope.seq) within tolerance.")
        }
    }

    /// Fixture fingerprint: committed data must still match the seeded
    /// totals exactly (Add entry never commits).
    private func verifyFixtureFingerprint(
        envelope: ScreenshotSessionEnvelope,
        store: LocalStore,
        expected: CaptureExpectedTotals
    ) async throws {
        let entries = try await store.entries()
        guard entries.count == ScreenshotFixture.entryCount else {
            throw ScreenshotRequestError(code: "count-mismatch", detail: "Expected 55 committed entries, found \(entries.count).")
        }
        let categories = try await store.categories()
        let categoriesByID = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0) })
        let calendar = envelope.request.calendar
        let dayStart = calendar.startOfDay(for: envelope.request.referenceDate)
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart),
              let week = calendar.dateInterval(of: .weekOfYear, for: envelope.request.referenceDate)
        else {
            throw ScreenshotRequestError(code: "totals-invalid", detail: "Reference intervals unresolvable.")
        }
        let current = CaptureExpectedTotals.compute(
            entries: entries,
            categoriesByID: categoriesByID,
            today: DateInterval(start: dayStart, end: dayEnd),
            week: week
        )
        guard current == expected else {
            throw ScreenshotRequestError(code: "totals-invalid", detail: "Fixture totals drifted mid-session.")
        }
    }

    private func validateViewModels(
        request: ScreenshotCaptureRequest,
        container: AppContainer,
        expected: CaptureExpectedTotals
    ) async throws {
        let validationClock = AppClock(now: { request.referenceDate }, calendar: request.calendar)
        let historyVM = HistoryViewModel(
            store: container.localStore,
            undoBuffer: container.undoBuffer,
            now: validationClock.now,
            calendar: validationClock.calendar
        )
        await historyVM.load()
        let historyCount = historyVM.dayGroups.reduce(0) { $0 + $1.entries.count }
        guard historyCount == ScreenshotFixture.entryCount else {
            throw ScreenshotRequestError(code: "totals-invalid", detail: "History shows \(historyCount), expected 55.")
        }
        let insightsVM = InsightsViewModel(store: container.localStore, now: validationClock.now)
        await insightsVM.load()
        let week = insightsVM.breakdown(period: .week, lens: .category, calendar: validationClock.calendar)
        guard week.totalSeconds == expected.weekSeconds else {
            throw ScreenshotRequestError(code: "totals-invalid", detail: "Insights week \(week.totalSeconds) != \(expected.weekSeconds).")
        }
        let all = insightsVM.breakdown(period: .all, lens: .activity, calendar: validationClock.calendar)
        guard all.totalSeconds == expected.allSeconds else {
            throw ScreenshotRequestError(code: "totals-invalid", detail: "Insights all-time \(all.totalSeconds) != \(expected.allSeconds).")
        }
        if activeFrameWantsAddEntryValidation(request: request) {
            try ScreenshotAddEntry.validate(request: request, container: container)
        }
    }

    private func activeFrameWantsAddEntryValidation(request: ScreenshotCaptureRequest) -> Bool {
        request.frame == .addEntry
    }

    // MARK: - State

    @discardableResult
    private func writeState(
        status: String,
        totals: CaptureExpectedTotals?,
        liveActivity: CaptureStateLiveActivity?,
        error: ScreenshotRequestError?
    ) -> CaptureState {
        let envelope = session?.validator.initial
        let last = transcript.last
        let state = CaptureState(
            status: status,
            requestSHA256: last?.requestSHA256,
            deckVersion: envelope?.request.deckVersion,
            frame: last.map { $0.frame } ?? envelope?.frame.rawValue,
            mode: envelope?.mode.rawValue,
            runID: envelope?.runID,
            counts: status == "ready" ? CaptureStateCounts(entries: ScreenshotFixture.entryCount) : nil,
            expectedTotals: totals,
            build: CaptureStateBuild(
                configuration: "Screenshot",
                bundleID: Bundle.main.bundleIdentifier ?? "unknown",
                commit: ScreenshotApp.commitSHA()
            ),
            clocks: envelope.map {
                CaptureStateClocks(
                    referenceLocalISO: ScreenshotCaptureRequest.pinnedReferenceISO,
                    referenceDate: ScreenshotApp.iso8601($0.request.referenceDate, timeZone: $0.request.timeZone),
                    timeZone: $0.request.timeZone.identifier
                )
            },
            liveActivity: liveActivity,
            error: error.map { CaptureStateFailure(code: $0.code, detail: $0.detail) },
            sessionNonce: envelope?.nonce,
            sessionDomain: envelope?.domain.rawValue,
            seq: last?.seq ?? envelope?.seq,
            transcript: transcript.isEmpty ? nil : transcript,
            appDurationsMS: appDurations()
        )
        do {
            try CaptureStateWriter.write(state, to: documents)
        } catch {
            NSLog("screenshot-session: state write failed (status=%@): %@", status, "\(error)")
        }
        return state
    }

    /// App-clock phase durations for the ack (`app_durations_ms`). Opaque
    /// values keyed by phase; the runner records them separately and never
    /// subtracts them from its own monotonic phases.
    private func appDurations() -> [String: Double]? {
        guard !timings.samples.isEmpty else { return nil }
        var durations: [String: Double] = [:]
        for sample in timings.samples {
            durations[sample.phase] = sample.milliseconds
        }
        return durations
    }

    @discardableResult
    private func terminal(status: String, error: ScreenshotRequestError) -> CaptureState {
        terminalCode = error.code
        phase = .terminal(message: error.detail)
        writeSessionEndedMarker()
        if session == nil {
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
                error: CaptureStateFailure(code: error.code, detail: error.detail),
                sessionNonce: nil,
                sessionDomain: nil,
                seq: nil,
                transcript: nil,
                appDurationsMS: nil
            )
            try? CaptureStateWriter.write(state, to: documents)
            return state
        }
        return writeState(status: status, totals: nil, liveActivity: session?.liveActivity, error: error)
    }

    private static func terminalStatus(for code: String) -> String {
        let invalidCodes: Set<String> = [
            "missing-file", "invalid-json", "missing-field", "unsupported-schema",
            "unknown-deck", "unsupported-locale", "unsupported-calendar",
            "unsupported-week-rule", "unsupported-reference", "unsupported-elapsed",
            "unknown-frame", "unknown-mode", "unknown-domain", "frame-not-listed",
            "mode-mismatch", "bad-filename", "invalid-run-id", "unsupported-nonce",
            "outer-inner-mismatch", "sha-mismatch",
        ]
        return invalidCodes.contains(code) ? "invalid" : "failure"
    }

    /// End-of-session marker (`session-ended.json`, runner `mark_session_ended`
    /// shape): later queue publications are stale and rejected by the runner
    /// without a new launch. Best-effort; never fails the terminal ack.
    private func writeSessionEndedMarker() {
        guard let initial = session?.validator.initial, let last = transcript.last else { return }
        do {
            let dir = try ScreenshotSessionPaths.sessionDirectory(documents: documents, nonce: initial.nonce)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let marker: [String: Any] = ["final_seq": last.seq, "session_nonce": initial.nonce]
            let bytes = try JSONSerialization.data(withJSONObject: marker, options: [.sortedKeys])
            try (bytes + Data("\n".utf8)).write(to: dir.appendingPathComponent("session-ended.json"), options: .atomic)
        } catch {
            NSLog("screenshot-session: session-ended write failed: %@", "\(error)")
        }
    }

    /// Realtime anchor (task 4.5 Swift): started ONCE per real-time session
    /// and shared by its three LA states. The historical reference is NEVER
    /// passed to the system timer.
    private static func defaultActivityStarter(
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
}

/// Session root: a blank hold while idle, then the REAL app shell for the
/// active revision — no substitute views, no overlays in exported images.
/// The revision-tagged identity recreates the subtree per command, so stale
/// presentation state cannot leak between frames.
struct ScreenshotSessionRootView: View {
    @ObservedObject var controller: ScreenshotSessionController

    var body: some View {
        Group {
            switch controller.phase {
        case .idle:
            Theme.backgroundPrimary
                .ignoresSafeArea()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityHidden(true)
        case .presenting:
            if let shellVM = controller.shellVM,
               let container = controller.sessionContainer,
               let snapshot = controller.snapshot,
               let clock = controller.viewClock,
               let frame = controller.activeFrame,
               let revision = controller.revision {
                AppShellView(
                    vm: shellVM,
                    container: container,
                    trackSnapshot: snapshot,
                    clock: clock
                )
                .environmentObject(container)
                .environmentObject(container.sessionStore)
                .environmentObject(container.navigation)
                .environmentObject(container.syncController)
                .environment(
                    \.locale,
                    clock.calendar.locale ?? Locale(identifier: controller.sessionLocaleIdentifier)
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .id(revision.id)
                // Mount proof rides `.task(id:)` — not `.onAppear` alone:
                // on same-branch identity changes the re-render fires but
                // the appear event is not delivered (device finding), so a
                // mount callback through appear alone would never run and
                // the command would time out. `.task(id:)` restarts on the
                // identity value change by construction. Both signals are
                // idempotent via noteMounted.
                .onAppear { controller.noteMounted(revision: revision) }
                .task(id: revision.id) {
                    controller.noteMounted(revision: revision)
                }
                .sheet(isPresented: .constant(frame == .addEntry)) {
                    ScreenshotAddEntrySheet(clock: clock, localeIdentifier: controller.sessionLocaleIdentifier)
                        .environmentObject(container)
                }
            } else {
                Theme.backgroundPrimary
                    .ignoresSafeArea()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityHidden(true)
            }
        case let .terminal(message):
            // Dev-only diagnostic (never ships): intentional English, no L10n.
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
}

extension ScreenshotSessionController {
    var sessionContainer: AppContainer? { session?.container }
    var sessionLocaleIdentifier: String { session?.validator.initial.request.localeIdentifier ?? "en" }
}

/// Entry routing: a v2 session envelope starts the batched controller;
/// anything else is rejected explicitly with an invalid terminal state —
/// there is no legacy fallback path. The schema-1 inner request payload is
/// still the envelope content (by design), but a bare v1 root file is never
/// accepted as a runtime request.
enum ScreenshotSessionRoute: Equatable {
    case session(ScreenshotSessionEnvelope)
    case invalid(ScreenshotRequestError)

    static func == (lhs: ScreenshotSessionRoute, rhs: ScreenshotSessionRoute) -> Bool {
        switch (lhs, rhs) {
        case let (.session(a), .session(b)): return a == b
        case let (.invalid(a), .invalid(b)): return a == b
        default: return false
        }
    }

    /// Testable routing decision over an explicit documents directory.
    static func resolve(documents: URL?) -> ScreenshotSessionRoute {
        guard let documents else {
            return .invalid(ScreenshotRequestError(code: "session-unavailable", detail: "No documents directory."))
        }
        let url = documents.appendingPathComponent(ScreenshotCaptureRequest.requestFilename)
        guard let data = try? Data(contentsOf: url) else {
            return .invalid(ScreenshotRequestError(code: "missing-file", detail: "No capture request at Documents/\(ScreenshotCaptureRequest.requestFilename)."))
        }
        do {
            return .session(try ScreenshotSessionEnvelopeLoader.parse(data: data))
        } catch let error as ScreenshotRequestError {
            return .invalid(error)
        } catch {
            return .invalid(ScreenshotRequestError(code: "unexpected", detail: "\(error)"))
        }
    }
}

struct ScreenshotSessionEntryView: View {
    @StateObject private var controller: ScreenshotSessionController
    @State private var route: ScreenshotSessionRoute?
    private let documents: URL?

    init() {
        let documents = try? ScreenshotApp.documentsDirectory()
        self.documents = documents
        let controller = ScreenshotSessionController(
            documents: documents ?? URL(fileURLWithPath: NSTemporaryDirectory())
        )
        _controller = StateObject(wrappedValue: controller)
    }

    var body: some View {
        Group {
            switch route {
            case nil:
                Theme.backgroundPrimary
                    .ignoresSafeArea()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityHidden(true)
                    .task {
                        let started = ScreenshotSessionClock.nowNanos()
                        let resolved = ScreenshotSessionRoute.resolve(documents: documents)
                        controller.recordRequestParse(nanos: ScreenshotSessionClock.nowNanos() - started)
                        switch resolved {
                        case let .session(envelope):
                            route = .session(envelope)
                        case let .invalid(error):
                            writeInvalidState(error: error)
                            route = .invalid(error)
                        }
                    }
            case let .session(envelope):
                ScreenshotSessionRootView(controller: controller)
                    .task { await controller.runUntilTerminal(initial: envelope) }
            case let .invalid(error):
                // Dev-only diagnostic (never ships): intentional English, no L10n.
                VStack(spacing: 12) {
                    Text("Screenshot capture unavailable")
                        .font(.headline)
                    Text(error.detail)
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

    /// Explicit rejection evidence: a no-context invalid state for the
    /// runner, written once without clobbering a prior session's evidence.
    private func writeInvalidState(error: ScreenshotRequestError) {
        guard let documents else { return }
        let existing = documents.appendingPathComponent(CaptureStateWriter.filename)
        guard !FileManager.default.fileExists(atPath: existing.path) else { return }
        let state = CaptureState(
            status: "invalid",
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
            error: CaptureStateFailure(code: error.code, detail: error.detail),
            sessionNonce: nil,
            sessionDomain: nil,
            seq: nil,
            transcript: nil,
            appDurationsMS: nil
        )
        try? CaptureStateWriter.write(state, to: documents)
    }
}
#endif
