import Testing
import Foundation
import SwiftUI
import UIKit
@testable import TimeOfLife

/// Focus-lifetime probe for the Today composer (day-planner 7.1): the spec
/// demands the field NEVER resign first responder across a submit — the
/// Return resign is suppressed at dispatch (custom submit handling that
/// never resigns), never repaired by refocusing afterwards. This suite
/// hosts the REAL `PlannerView` in a key window and dispatches the REAL
/// Return path (`UITextFieldDelegate.textFieldShouldReturn`, the same
/// selector the keyboard's return key invokes), then observes the complete
/// async round-trip (draft-clear → section mount/unmount → snapshot reload)
/// with continuous first-responder sampling: ANY end-editing event — however
/// brief, at ANY round-trip latency — fails. The 6.1 next-tick re-assertion
/// fails this suite (it resigns at dispatch, then refocuses); the
/// UIKit-backed composer passes with zero events and a `false` dispatch
/// verdict. The full UIKit return-key dispatch additionally needs a
/// foreground scene, so the real keyboard path stays owned by the XCUITest
/// stillness probe (`PlannerKeyboardStillnessTests`).
@MainActor
@Suite("Planner composer focus lifetime (day-planner 7.1)")
struct PlannerComposerFocusTests {
    @Test("probe observes a genuine resign")
    func probeObservesRealResigns() async throws {
        let ctx = try await makeHostedComposer()
        let endCounter = EventCounter()
        let tokens = observe(ctx.field, end: { endCounter.increment() }, begin: {})
        defer { tokens.forEach { NotificationCenter.default.removeObserver($0) } }
        _ = ctx.field.resignFirstResponder()
        await pump()
        #expect(endCounter.resigns == 1, "probe blind: forced resign produced no end-editing event")
    }

    @Test("keystroke-equivalent refresh never resigns the composer")
    func typingNeverResignsComposer() async throws {
        let ctx = try await makeHostedComposer()
        let endCounter = EventCounter()
        let tokens = observe(ctx.field, end: { endCounter.increment() }, begin: {})
        defer { tokens.forEach { NotificationCenter.default.removeObserver($0) } }
        ctx.field.insertText("Read")
        await pump()
        #expect(ctx.vm.draft == "Read", "typing through the field must sync the draft")
        #expect(ctx.vm.suggestions.map(\.activityText) == ["Read docs"])
        #expect(ctx.field.isFirstResponder, "keystroke-equivalent refresh stole focus")
        #expect(endCounter.resigns == 0, "refresh resigned the composer \(endCounter.resigns)x")
    }

    @Test("Return dispatch declines the default resign")
    func returnDispatchDeclinesResign() async throws {
        let ctx = try await makeHostedComposer()
        ctx.field.insertText("Read")
        await pump()
        // The keyboard's return key invokes this selector: `false` runs the
        // custom submit without the default resign; `true` (or an absent
        // delegate) resigns first — the 6.1 flicker.
        let verdict = ctx.field.delegate?.textFieldShouldReturn?(ctx.field) ?? true
        await pump()
        #expect(verdict == false, "Return dispatch did not suppress the default resign")
    }

    @Test("submit round-trip never resigns the composer at any latency")
    func submitNeverResignsComposer() async throws {
        let ctx = try await makeHostedComposer()
        let endCounter = EventCounter()
        let beginCounter = EventCounter()
        let tokens = observe(
            ctx.field,
            end: { endCounter.increment() },
            begin: { beginCounter.increment() }
        )
        defer { tokens.forEach { NotificationCenter.default.removeObserver($0) } }
        ctx.field.insertText("Read")
        await pump()
        endCounter.reset()
        beginCounter.reset()
        // Real Return dispatch (same selector the keyboard invokes), then
        // observe CONTINUOUSLY across the whole async round-trip: sampling
        // only at settle would blind the probe to latency-dependent gaps.
        _ = ctx.field.delegate?.textFieldShouldReturn?(ctx.field)
        var missedFocusSamples = 0
        var samples = 0
        let deadline = Date().addingTimeInterval(10)
        while ctx.vm.snapshot.tasks.isEmpty, Date() < deadline {
            samples += 1
            if !ctx.field.isFirstResponder { missedFocusSamples += 1 }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        // Settle: delayed resigns (async focus races) arrive after the task
        // lands, so assertions must wait them out, not race them.
        let settleUntil = Date().addingTimeInterval(1)
        while Date() < settleUntil {
            samples += 1
            if !ctx.field.isFirstResponder { missedFocusSamples += 1 }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        #expect(ctx.vm.snapshot.tasks.map(\.name) == ["Read"], "submit round-trip never completed")
        #expect(ctx.vm.draft.isEmpty, "submit must clear the draft")
        #expect(
            missedFocusSamples == 0,
            "composer lost first responder in \(missedFocusSamples)/\(samples) samples across submit"
        )
        #expect(endCounter.resigns == 0, "submit resigned the composer \(endCounter.resigns)x")
        #expect(beginCounter.resigns == 0, "submit refocused the composer \(beginCounter.resigns)x (resign + reopen)")
        #expect(ctx.field.isFirstResponder, "composer lost focus across submit")
    }

    // MARK: - Helpers

    /// A hosted composer holding its window alive, with one seeded entry so
    /// a draft shows the suggestions section that submit later unmounts.
    private func makeHostedComposer() async throws -> HostedComposer {
        let (vm, store) = makeContext()
        _ = try await store.createEntry(TimeEntry(
            id: "e1", activityText: "Read docs",
            startedAt: Date(timeIntervalSinceReferenceDate: 1_000),
            endedAt: Date(timeIntervalSinceReferenceDate: 1_600), durationSeconds: 600
        ))
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
            "composer UITextField never materialized: \(describeTextFields(in: host.view))"
        )
        // Settle: the shake-to-undo host (`ShakeFirstResponderHost`)
        // becomes first responder once when it enters the window — on
        // device this fires at appear, long before the first tap. Let that
        // attach-grab land BEFORE focusing, so setup observes the steady
        // state the user meets rather than racing it.
        await pump(300_000_000)
        #expect(field.becomeFirstResponder())
        await pump()
        #expect(field.isFirstResponder, "composer must hold focus")
        return HostedComposer(vm: vm, field: field, window: window, host: host)
    }

    private func makeContext() -> (vm: PlannerViewModel, store: LocalStore) {
        // swiftlint:disable:next force_try
        let store = try! LocalStore(url: temporaryStoreURL())
        let vm = PlannerViewModel(
            store: store,
            undoBuffer: UndoBufferStore(store: store),
            timer: TimerService(store: store)
        )
        return (vm, store)
    }

    private func temporaryStoreURL() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent(LocalStore.databaseFileName(userID: "planner-focus"))
    }

    /// Yields to the main runloop so SwiftUI applies pending state updates.
    private func pump(_ nanoseconds: UInt64 = 100_000_000) async {
        try? await Task.sleep(nanoseconds: nanoseconds)
    }

    /// Installs begin/end-editing observers on a composer field; the caller
    /// owns the returned tokens and removes them when done.
    private func observe(
        _ field: UITextField,
        end: @escaping @Sendable () -> Void,
        begin: @escaping @Sendable () -> Void
    ) -> [NSObjectProtocol] {
        let center = NotificationCenter.default
        return [
            center.addObserver(
                forName: UITextField.textDidEndEditingNotification,
                object: field, queue: .main
            ) { _ in end() },
            center.addObserver(
                forName: UITextField.textDidBeginEditingNotification,
                object: field, queue: .main
            ) { _ in begin() },
        ]
    }

    /// Polls the hosted hierarchy for the composer `UITextField`: SwiftUI
    /// materializes it asynchronously after the window goes key.
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
        // The composer carries its test identifier directly on the field;
        // otherwise match the localized placeholder (resolved in the same
        // locale the host renders, so this holds in all five locales).
        // While no rename is active the composer is the only TextField
        // mounted, so either signal identifies it.
        let placeholder = L10n.plannerComposerPlaceholder.text
        if let field = view as? UITextField,
           field.accessibilityIdentifier == "PlannerComposerField"
            || field.placeholder == placeholder {
            return field
        }
        for subview in view.subviews {
            if let found = findComposerField(in: subview) { return found }
        }
        return nil
    }

    /// Diagnostic for a missing composer: every mounted text input plus the
    /// raw hierarchy shape, so a lookup miss names the cause.
    private func describeTextFields(in view: UIView) -> String {
        var lines: [String] = []
        collectTextFields(in: view, into: &lines)
        if lines.isEmpty {
            lines.append("no UITextField/UITextView mounted; root=\(type(of: view)) subviews=\(view.subviews.count)")
        }
        return lines.joined(separator: "; ")
    }

    private func collectTextFields(in view: UIView, into lines: inout [String]) {
        if let field = view as? UITextField {
            lines.append("UITextField id=\(field.accessibilityIdentifier ?? "nil") placeholder=\(field.placeholder ?? "nil")")
        }
        if view is UITextView {
            lines.append("UITextView id=\(view.accessibilityIdentifier ?? "nil")")
        }
        for subview in view.subviews { collectTextFields(in: subview, into: &lines) }
    }
}

/// Lock-guarded event counter, so the `@Sendable` notification closures
/// stay warning-free under complete checking (MockCatalogRepository
/// precedent: `NSLock` + `@unchecked Sendable`).
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

    func reset() {
        lock.lock()
        value = 0
        lock.unlock()
    }
}

/// The hosted composer: keeps its window (and host controller) alive for
/// the test's duration (ARC removes the window at the end).
private final class HostedComposer {
    let vm: PlannerViewModel
    let field: UITextField
    let window: UIWindow
    let host: UIViewController

    init(vm: PlannerViewModel, field: UITextField, window: UIWindow, host: UIViewController) {
        self.vm = vm
        self.field = field
        self.window = window
        self.host = host
    }
}
