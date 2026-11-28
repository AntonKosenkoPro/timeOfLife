// swiftlint:disable file_length
// (four hosted probes plus two hosts and their helpers live together so
// the device-window synthesis reads in one place; splitting the file
// would scatter the failing-first narrative, not clarify it.)
import Testing
import Foundation
import SwiftUI
import UIKit
@testable import TimeOfLife

/// Day-planner §24: the end-echo (§24.1) + drag dismiss (§24.2). Supersedes
/// §22/§23's intent-clear approach (their tests stay green; the approach is
/// kept as defense in depth but no longer carries the device).
///
/// Proven mechanism: a `FocusState` write is a focus-engine request, not a
/// synchronous store set. The §22 dispatch write (`focused = false`) has
/// not flushed when the resign-triggered update storm runs `updateUIView`;
/// the become-only recovery reads the still-true intent and re-grabs, and
/// the begin-echo re-locks `true` — the keyboard never visibly closes. The
/// sim always reconciles first, so every sim-hosted resign test stayed
/// green while the owner's device failed every time. The §23 cascade probe
/// confirmed the sim/sim split (it passes on §22 code) and its propagation
/// half failed on parallel key windows (a harness bug — the suite was not
/// `.serialized`), not on product behavior; both halves are deleted with
/// the §23 file. The end-echo observes ACTUAL first-responder state
/// instead: `textFieldDidEndEditing` latches a coordinator-owned gate and
/// `updateUIView` honors it, so no update pass can re-acquire after ANY
/// genuine resign (empty Return, drag, system) until a genuine begin
/// unlatches it. A second, load-bearing finding: UITextField performs NO
/// default resign on Return — the dispatch itself must resign explicitly
/// (the Hold dismiss probe proved a bare `true` verdict leaves the
/// keyboard up on sim and device). The unit probes below synthesize the
/// device window deterministically (genuine resign + update pass while
/// the intent still reads true); the real-path verdict lives in the Hold
/// dismiss probe, which is red without the explicit resign + gate and
/// green with them.
@MainActor
@Suite("Planner section 24 (end-echo resign-sticks, drag dismiss)", .serialized)
struct PlannerSection24Tests {
    // MARK: - End-echo (24.1)

    @Test("a genuine resign sticks through a stale-intent update pass")
    func endEchoSticksThroughStaleIntentUpdate() async throws {
        let control = HarnessControl()
        control.intent = true
        let ctx = try await makeHostedHarness(control: control)
        #expect(ctx.field.isFirstResponder, "harness field must hold focus")
        let beginCounter = EventCounter()
        let endCounter = EventCounter()
        let tokens = [
            observe(ctx.field, UITextField.textDidBeginEditingNotification) { beginCounter.increment() },
            observe(ctx.field, UITextField.textDidEndEditingNotification) { endCounter.increment() },
        ]
        defer { tokens.forEach { NotificationCenter.default.removeObserver($0) } }
        // Real empty-Return dispatch through the REAL delegate: the field
        // resigns ITSELF and reports handled (no UIKit default resign
        // exists — a bare `true` verdict leaves the keyboard up), and
        // submits nothing.
        let verdict = ctx.field.delegate?.textFieldShouldReturn?(ctx.field) ?? false
        #expect(verdict == false, "empty-draft Return resigns explicitly (handled, no default)")
        #expect(control.returnCount == 0, "empty Return must not submit")
        // The resign itself fired INSIDE the dispatch (explicit resign at
        // dispatch — there is no UIKit default to wait for); this already
        // fired the end-echo (`textFieldDidEndEditing`) for real. The
        // manual resign below is a no-op that documents the old shape.
        _ = ctx.field.resignFirstResponder()
        #expect(!ctx.field.isFirstResponder, "empty Return must resign")
        #expect(endCounter.resigns == 1, "the resign must echo end-editing exactly once")
        #expect(control.editingLog.last == false, "the end-echo must report not-focused")
        // THE DEVICE WINDOW, synthesized deterministically (no yield — the
        // whole point): the intent still reads true while the field is
        // genuinely resigned (the unflushed §22 write on device), and an
        // update pass runs behind the view (the draft publish /
        // keyboard-notification storm). Without the gate the become-only
        // recovery re-grabs here — the device symptom.
        await runStaleIntentStorm(
            Storm(field: ctx.field, host: ctx.host, control: control, begun: beginCounter, ended: endCounter),
            beginsBefore: 0, endsBefore: 1
        )
        // The other half of the contract: a genuine begin (the user-tap
        // equivalent) unlatches the gate, so refocus works again.
        _ = ctx.field.becomeFirstResponder()
        #expect(ctx.field.isFirstResponder, "user refocus must re-acquire")
        #expect(control.editingLog.last == true, "the begin-echo must report focused")
        // ...and a later genuine resign re-latches (the gate is not one-shot).
        control.prose = ""
        try? await Task.sleep(nanoseconds: 100_000_000)
        let relatchVerdict = ctx.field.delegate?.textFieldShouldReturn?(ctx.field) ?? true
        #expect(relatchVerdict == false, "empty Return resigns explicitly again (handled, no default)")
        _ = ctx.field.resignFirstResponder()
        #expect(endCounter.resigns == 2, "the re-latch resign must echo end-editing again")
        await runStaleIntentStorm(
            Storm(field: ctx.field, host: ctx.host, control: control, begun: beginCounter, ended: endCounter),
            beginsBefore: 1, endsBefore: 2
        )
    }

    /// Runs one synthesized device-window storm behind the view (stale-true
    /// intent + draft publish + keyboard notification + layout pass, no
    /// yield first) and pins the resigned end state, including a 1s
    /// no-re-grab settle. `beginsBefore`/`endsBefore` are the expected echo
    /// counts entering the storm (the gate re-latch path reuses this with
    /// the refocus begin + second resign already counted).
    private struct Storm {
        var field: UITextField
        var host: UIViewController
        var control: HarnessControl
        var begun: EventCounter
        var ended: EventCounter
    }

    private func runStaleIntentStorm(_ storm: Storm, beginsBefore: Int, endsBefore: Int) async {
        storm.control.intent = true
        storm.control.prose = "storm"
        NotificationCenter.default.post(name: UIResponder.keyboardWillHideNotification, object: nil)
        storm.host.view.setNeedsLayout()
        storm.host.view.layoutIfNeeded()
        try? await Task.sleep(nanoseconds: 300_000_000)
        #expect(
            !storm.field.isFirstResponder,
            "stale-intent update re-grabbed first responder (device: keyboard never dismisses)"
        )
        #expect(storm.begun.resigns == beginsBefore, "stale-intent update re-began editing")
        #expect(storm.ended.resigns == endsBefore, "no focus churn across the storm")
        // ...and it must STAY resigned (no delayed re-grab either).
        let settleUntil = Date().addingTimeInterval(1)
        var regrabbedSamples = 0
        var samples = 0
        while Date() < settleUntil {
            samples += 1
            if storm.field.isFirstResponder { regrabbedSamples += 1 }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        #expect(regrabbedSamples == 0, "re-grabbed focus in \(regrabbedSamples)/\(samples) settle samples")
        #expect(!storm.field.isFirstResponder, "field must stay resigned after a genuine resign")
    }

    // MARK: - Drag dismiss (24.2)

    @Test("real-view empty Return resigns and stays resigned through the real storm")
    func realViewEmptyReturnStaysResigned() async throws {
        let ctx = try await makeHostedPlanner()
        #expect(ctx.field.isFirstResponder, "composer must hold focus")
        #expect(ctx.vm.draft.isEmpty, "precondition: empty draft (no chip staged)")
        let beginCounter = EventCounter()
        let endCounter = EventCounter()
        let tokens = [
            observe(ctx.field, UITextField.textDidBeginEditingNotification) { beginCounter.increment() },
            observe(ctx.field, UITextField.textDidEndEditingNotification) { endCounter.increment() },
        ]
        defer { tokens.forEach { NotificationCenter.default.removeObserver($0) } }
        // Real empty-Return dispatch through the REAL delegate: the field
        // resigns ITSELF and reports handled (see the harness test), which
        // rules out a false-verdict path for the programmatic empty draft.
        let verdict = ctx.field.delegate?.textFieldShouldReturn?(ctx.field) ?? true
        #expect(verdict == false, "empty-draft Return resigns explicitly (handled, no default)")
        _ = ctx.field.resignFirstResponder()
        #expect(!ctx.field.isFirstResponder, "empty Return must resign")
        #expect(endCounter.resigns == 1, "the resign must echo end-editing exactly once")
        // THE REAL STORM (real PlannerView, not the minimal harness): the
        // exact notification pair the dismissal posts, plus a draft
        // republish driving a genuine update pass (chips line unmounts
        // behind the view), then a 1s no-re-grab settle.
        NotificationCenter.default.post(name: UIResponder.keyboardWillShowNotification, object: nil)
        try? await Task.sleep(nanoseconds: 200_000_000)
        NotificationCenter.default.post(name: UIResponder.keyboardWillHideNotification, object: nil)
        let draft = ctx.vm.draft
        ctx.vm.draft = draft
        try? await Task.sleep(nanoseconds: 300_000_000)
        let settleUntil = Date().addingTimeInterval(1)
        var regrabbedSamples = 0
        var samples = 0
        while Date() < settleUntil {
            samples += 1
            if ctx.field.isFirstResponder { regrabbedSamples += 1 }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        #expect(regrabbedSamples == 0, "real-view resign re-grabbed focus in \(regrabbedSamples)/\(samples) samples")
        #expect(!ctx.field.isFirstResponder, "real-view empty Return must stay resigned")
        #expect(beginCounter.resigns == 0, "real-view empty Return re-began editing \(beginCounter.resigns)x")
    }

    @Test("drag-dismiss resign keeps draft, chips, and selection with nothing submitted")
    func dragDismissKeepsContentAndStaysResigned() async throws {
        let ctx = try await makeHostedPlanner()
        #expect(ctx.field.isFirstResponder, "composer must hold focus")
        // Stage a chip (selected-only display): the exact text fills the
        // composer and the Recent's full set is staged for the next submit.
        let chip = try #require(ctx.vm.chips.first, "seeded Recent must offer a chip")
        ctx.vm.fillFromChip(chip)
        #expect(ctx.vm.draft == chip.activityText)
        #expect(ctx.vm.stagedChip?.text == chip.activityText)
        #expect(ctx.vm.isSelectedChip(chip))
        let tasksBefore = ctx.vm.snapshot.tasks.count
        let beginCounter = EventCounter()
        let tokens = [observe(ctx.field, UITextField.textDidBeginEditingNotification) { beginCounter.increment() }]
        defer { tokens.forEach { NotificationCenter.default.removeObserver($0) } }
        // The exact resign a scroll-view interactive dismiss performs (the
        // drag gesture itself is UIKit touch delivery — not unit-testable;
        // the gesture path is pinned structurally below). In sim the flush
        // wins, so this half stays green with or without the gate; the
        // device window is pinned by the harness test above.
        _ = ctx.field.resignFirstResponder()
        #expect(!ctx.field.isFirstResponder, "drag dismiss must resign the composer")
        // The drag storm: the real keyboard notifications plus two real
        // update passes, then a 1s settle sample.
        NotificationCenter.default.post(name: UIResponder.keyboardWillShowNotification, object: nil)
        try? await Task.sleep(nanoseconds: 200_000_000)
        NotificationCenter.default.post(name: UIResponder.keyboardWillHideNotification, object: nil)
        ctx.vm.draft = ctx.vm.draft
        let settleUntil = Date().addingTimeInterval(1)
        var regrabbedSamples = 0
        var samples = 0
        while Date() < settleUntil {
            samples += 1
            if ctx.field.isFirstResponder { regrabbedSamples += 1 }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        // Content untouched: draft, staged set, selection, chips, rows.
        #expect(ctx.vm.draft == chip.activityText, "drag dismiss must not touch the draft")
        #expect(ctx.vm.stagedChip?.text == chip.activityText, "drag dismiss must not touch the staged set")
        #expect(ctx.vm.isSelectedChip(chip), "drag dismiss must not touch the selection")
        #expect(
            ctx.vm.chips.map(\.activityText).contains(chip.activityText),
            "drag dismiss must not touch the chips"
        )
        #expect(ctx.vm.snapshot.tasks.count == tasksBefore, "drag dismiss must submit nothing")
        // ...and it stays dismissed.
        #expect(regrabbedSamples == 0, "drag dismiss re-grabbed focus in \(regrabbedSamples)/\(samples) samples")
        #expect(!ctx.field.isFirstResponder, "composer must stay resigned after drag dismiss")
        #expect(beginCounter.resigns == 0, "drag dismiss re-began editing \(beginCounter.resigns)x")
    }

    @Test("the task list dismisses the keyboard interactively with the drag")
    func taskListDismissesKeyboardInteractively() throws {
#if targetEnvironment(simulator)
        // Structural pin (SwiftUI drag delivery is not unit-testable): the
        // list carries the Messages-grammar interactive dismiss; the resign
        // it produces latches the end-echo gate, so it sticks.
        let source = try featureSource(named: "PlannerView.swift")
        #expect(
            source.contains(".scrollDismissesKeyboard(.interactively)"),
            "the task list must dismiss the keyboard interactively with the drag"
        )
#else
        // The pin reads host source, which is not present on device; the
        // device gesture path is covered by the drag-content test above
        // plus owner finger verification (manual-testing My Day item 19).
#endif
    }

    // MARK: - End-echo harness (owns its FocusState, so the test can drive
    // the intent exactly the way the device leaves it: genuinely resigned
    // while the intent still reads true).

    /// Mutable inputs for the harness, owned by the test.
    private final class HarnessControl: ObservableObject {
        @Published var intent = false
        @Published var prose = ""
        var editingLog: [Bool] = []
        var returnCount = 0
    }

    private struct EndEchoHarness: View {
        @ObservedObject var control: HarnessControl
        @FocusState var focused: Bool
        var body: some View {
            PlannerComposerField(
                text: $control.prose,
                placeholder: "EndEcho",
                focused: $focused,
                accessibilityIdentifier: "PlannerComposerField",
                onReturn: { control.returnCount += 1 },
                onEditingChanged: { control.editingLog.append($0) }
            )
            .onReceive(control.$intent) { focused = $0 }
        }
    }

    private struct HostedHarness {
        var field: UITextField
        var window: UIWindow
        var host: UIViewController
    }

    /// Windows retired by earlier hosted tests, hidden before a new host
    /// goes key (pool-drain timing outlives the context; the §18 precedent).
    private static var retiredWindows: [UIWindow] = []

    private func makeHostedHarness(control: HarnessControl) async throws -> HostedHarness {
        for window in Self.retiredWindows { window.isHidden = true }
        let host = UIHostingController(rootView: EndEchoHarness(control: control))
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        let field = try #require(
            await composerField(in: host.view),
            "harness UITextField never materialized"
        )
        try? await Task.sleep(nanoseconds: 300_000_000)
        #expect(field.becomeFirstResponder())
        try? await Task.sleep(nanoseconds: 100_000_000)
        #expect(field.isFirstResponder, "harness field must hold focus")
        Self.retiredWindows.append(window)
        return HostedHarness(field: field, window: window, host: host)
    }

    // MARK: - Real PlannerView host (drag-dismiss half)

    private func makeHostedPlanner() async throws -> HostedPlanner {
        // swiftlint:disable:next force_try
        let store = try! LocalStore(url: temporaryStoreURL())
        _ = try await store.createEntry(TimeEntry(
            id: "e1", activityText: "Read docs",
            startedAt: Date(timeIntervalSinceReferenceDate: 1_000),
            endedAt: Date(timeIntervalSinceReferenceDate: 1_600), durationSeconds: 600
        ))
        let vm = PlannerViewModel(
            store: store,
            undoBuffer: UndoBufferStore(store: store),
            timer: TimerService(store: store)
        )
        for window in Self.retiredWindows { window.isHidden = true }
        let sync = SyncController(
            store: store,
            remote: MockCatalogRepository(),
            connectivity: MockConnectivity(connected: true)
        ) { "u1" }
        await vm.loadIfNeeded()
        let host = UIHostingController(rootView: PlannerView(vm: vm).environmentObject(sync))
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        let field = try #require(
            await composerField(in: host.view),
            "composer UITextField never materialized"
        )
        try? await Task.sleep(nanoseconds: 300_000_000)
        #expect(field.becomeFirstResponder())
        try? await Task.sleep(nanoseconds: 100_000_000)
        #expect(field.isFirstResponder, "composer must hold focus")
        Self.retiredWindows.append(window)
        return HostedPlanner(vm: vm, field: field, window: window, host: host)
    }

    private func temporaryStoreURL() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent(LocalStore.databaseFileName(userID: "planner-s24"))
    }

    private func composerField(in root: UIView) async -> UITextField? {
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            if let found = findComposerField(in: root) { return found }
            try? await Task.sleep(nanoseconds: 50_000_000)
            root.setNeedsLayout()
            root.layoutIfNeeded()
        }
        return nil
    }

    private func findComposerField(in view: UIView) -> UITextField? {
        if let field = view as? UITextField,
           field.accessibilityIdentifier == "PlannerComposerField" {
            return field
        }
        for subview in view.subviews {
            if let found = findComposerField(in: subview) { return found }
        }
        return nil
    }

    /// Installs one editing-echo observer on a composer field; the caller
    /// owns the returned token and removes it when done.
    private func observe(
        _ field: UITextField,
        _ name: Notification.Name,
        count: @escaping @Sendable () -> Void
    ) -> NSObjectProtocol {
        NotificationCenter.default.addObserver(
            forName: name, object: field, queue: nil
        ) { _ in count() }
    }

    /// Reads a view source file for the structural tripwire (the §18
    /// precedent): resolved from this file's own path, so a move of any
    /// file fails loudly instead of passing vacuously.
    private func featureSource(named file: String) throws -> String {
        let testsDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let url = testsDir
            .deletingLastPathComponent()
            .appendingPathComponent("TimeOfLife/Features/Planner/Views/\(file)")
        return try String(contentsOf: url, encoding: .utf8)
    }
}

/// Lock-guarded event counter (the 7.1 probe precedent: `NSLock` +
/// `@unchecked Sendable` stays warning-free under complete checking).
private final class EventCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    func increment() {
        lock.lock()
        value += 1
        lock.unlock()
    }

    var resigns: Int {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}

/// Hosted planner keeping its window alive for the test's duration.
private struct HostedPlanner {
    var vm: PlannerViewModel
    var field: UITextField
    var window: UIWindow
    var host: UIViewController
}
