import Testing
import Foundation
import SwiftUI
import UIKit
@testable import TimeOfLife

/// Day-planner §18: sheet subheader + bottom delete, reorder-only control,
/// composer dismiss + empty-Return dismiss, outside-run nav subtitle.
/// Pins VM helpers + one structural tripwire; haptics via the seam.
@MainActor
@Suite("Planner section 18 (sheet subheader, reorder, dismiss, outside subtitle)", .serialized)
struct PlannerSection18Tests {
    // MARK: - Sheet subheader + delete (18.1)

    @Test("subheader flag reads true only for the running task")
    func editingRunningTaskFlag() async throws {
        let (vm, _, _, _) = await makeContext()
        #expect(vm.isEditingRunningTask == false)
        await vm.loadIfNeeded()
        vm.draft = "A"
        await vm.submit()
        let task = try #require(vm.snapshot.tasks.first)
        vm.beginEdit(task)
        #expect(vm.isEditingRunningTask == false)
        vm.cancelEdit()
        #expect(await vm.startTask(task))
        vm.invalidate()
        await vm.loadIfNeeded()
        vm.beginEdit(try #require(vm.snapshot.tasks.first))
        #expect(vm.isEditingRunningTask)
        vm.cancelEdit()
        #expect(vm.isEditingRunningTask == false)
    }

    @Test("tapping the running task's disabled delete rejects with no deletion")
    func disabledDeleteTapRejects() async throws {
        let (vm, _, undoBuffer, recorded) = await makeContext()
        await vm.loadIfNeeded()
        vm.draft = "A"
        await vm.submit()
        let task = try #require(vm.snapshot.tasks.first)
        #expect(await vm.startTask(task))
        vm.invalidate()
        await vm.loadIfNeeded()
        vm.beginEdit(try #require(vm.snapshot.tasks.first))
        #expect(vm.isEditingRunningTask)
        #expect(await vm.attemptDeleteEditingTask() == false)
        #expect(recorded.events == [.success, .reject])
        // Deletes nothing: the row stays, the sheet stays open, and no
        // undo row is buffered.
        #expect(vm.snapshot.tasks.map(\.id) == [task.id])
        #expect(vm.editingTask?.id == task.id)
        #expect(try await undoBuffer.mostRecent() == nil)
    }

    @Test("the normal sheet delete enters the durable undo buffer and pops the sheet")
    func normalSheetDeleteIntoUndoBuffer() async throws {
        let (vm, _, _, recorded) = await makeContext()
        await vm.loadIfNeeded()
        vm.draft = "A"
        await vm.submit()
        let task = try #require(vm.snapshot.tasks.first)
        vm.beginEdit(task)
        #expect(await vm.attemptDeleteEditingTask())
        #expect(recorded.events == [.success])
        #expect(vm.snapshot.tasks.isEmpty)
        // Pops the sheet (the `.sheet(item:)` binding clears).
        #expect(vm.editingTask == nil)
        // Restorable through the system Undo path.
        await vm.performUndo()
        #expect(vm.snapshot.tasks.map(\.id) == [task.id])
    }

    @Test("sheet delete with no open sheet deletes nothing and plays nothing")
    func deleteWithClosedSheetIsNoOp() async throws {
        let (vm, _, undoBuffer, recorded) = await makeContext()
        await vm.loadIfNeeded()
        vm.draft = "A"
        await vm.submit()
        #expect(vm.editingTask == nil)
        #expect(await vm.attemptDeleteEditingTask() == false)
        #expect(recorded.events == [.success])
        #expect(vm.snapshot.tasks.count == 1)
        #expect(try await undoBuffer.mostRecent() == nil)
    }

    // MARK: - Reorder control (18.2)

    @Test("reorder moves rows with no edit-mode state involved")
    func moveReordersWithoutEditState() async throws {
        let (vm, _, _, _) = await makeContext()
        await vm.loadIfNeeded()
        // Prepend order: the second submit lands first.
        vm.draft = "A"
        await vm.submit()
        vm.draft = "B"
        await vm.submit()
        #expect(vm.snapshot.tasks.map(\.name) == ["B", "A"])
        // The view model owns no edit-mode flag — `move` is the whole
        // reorder contract; the reorder control only surfaces handles.
        await vm.move(from: IndexSet(integer: 0), to: 2)
        #expect(vm.snapshot.tasks.map(\.name) == ["A", "B"])
    }

    @Test("the planner list carries reorder without an Edit button or edit-mode delete")
    func noEditButtonOrEditModeDelete() throws {
        // Structural tripwire (SwiftUI rendering is not unit-testable):
        // a reintroduction of any banned token fails loudly here.
        let source = try featureSource(named: "PlannerView.swift")
        #expect(!source.contains("EditButton()"), "the Edit button must not come back")
        #expect(!source.contains(".onDelete"), "edit-mode delete must not come back")
        #expect(!source.contains(".deleteDisabled"), "edit-mode delete gating must not come back")
        #expect(source.contains("PlannerReorderButton"), "the dedicated reorder control is missing")
        #expect(source.contains(".onMove"), "reorder lost its `onMove` handles")
    }

    // MARK: - Composer dismiss (18.3)

    @Test("Return resigns only on an empty draft")
    func returnResignVerdict() {
        #expect(PlannerComposerField.shouldResignOnReturn(text: ""))
        #expect(PlannerComposerField.shouldResignOnReturn(text: "   "))
        #expect(PlannerComposerField.shouldResignOnReturn(text: " \n\t "))
        #expect(!PlannerComposerField.shouldResignOnReturn(text: "Read"))
        #expect(!PlannerComposerField.shouldResignOnReturn(text: "  Read  "))
    }

    @Test("Return on an empty draft takes the default resign")
    func emptyReturnDispatchResigns() async throws {
        let ctx = try await makeHostedPlanner()
        // Empty draft: `true` lets the system resign — the ONLY
        // submit-path resign allowed (day-planner 18.3). Calling the
        // delegate directly exercises the verdict; the resign itself is
        // UIKit default behavior (no custom code to pin).
        let verdict = ctx.field.delegate?.textFieldShouldReturn?(ctx.field) ?? false
        #expect(verdict == true, "empty-draft Return must allow the default resign")
        // The resign after a `true` verdict fires end-editing (the 7.1
        // suite proves valid submits never do).
        await confirmation("empty Return dismisses the keyboard", expectedCount: 1) { confirm in
            let token = NotificationCenter.default.addObserver(
                forName: UITextField.textDidEndEditingNotification,
                object: ctx.field,
                queue: nil
            ) { _ in confirm() }
            defer { NotificationCenter.default.removeObserver(token) }
            _ = ctx.field.resignFirstResponder()
        }
    }

    @Test("the dismiss control shows while editing, even for an empty draft")
    func dismissVisibilityRule() {
        // Editing-only (the `ClearButtonVisibility` precedent): unlike the
        // clear button the rule is text-independent — an empty draft must
        // still offer the explicit way off the keyboard.
        #expect(ComposerDismissVisibility.shouldShow(isEditing: true))
        #expect(!ComposerDismissVisibility.shouldShow(isEditing: false))
    }

    @Test("the composer row carries the dismiss control")
    func composerRowCarriesDismissControl() throws {
        // Structural tripwire: the dismiss control SHALL stay mounted.
        let source = try featureSource(named: "PlannerComposerRow.swift")
        #expect(source.contains("PlannerComposerDismiss"))
        #expect(source.contains("keyboard.chevron.compact.down"))
        #expect(source.contains("plannerDismissKeyboard"))
    }

    // MARK: - Outside-run subtitle + disabled Start (18.4)

    @Test("no subheader while idle")
    func noSubtitleWhenIdle() async throws {
        let (vm, _, _, _) = await makeContext()
        await vm.loadIfNeeded()
        #expect(vm.outsideRunSubtitle == nil)
    }

    @Test("no subheader while the run is planner-linked")
    func noSubtitleWhenLinked() async throws {
        let (vm, _, _, _) = await makeContext()
        await vm.loadIfNeeded()
        vm.draft = "A"
        await vm.submit()
        #expect(await vm.startTask(try #require(vm.snapshot.tasks.first)))
        vm.invalidate()
        await vm.loadIfNeeded()
        #expect(vm.timerActive)
        #expect(vm.linkedTaskID != nil)
        #expect(vm.outsideRunSubtitle == nil)
    }

    @Test("an ordinary run names itself in the subheader")
    func ordinaryRunNamesSubheader() async throws {
        let (vm, store, _, _) = await makeContext()
        await vm.loadIfNeeded()
        try await store.saveTimerDraft(activityText: "Read docs", categoryIDs: [], startedAt: Date())
        vm.invalidate()
        await vm.loadIfNeeded()
        #expect(vm.timerActive)
        #expect(vm.linkedTaskID == nil)
        // The en copy is pinned through the explicit bundle (locale-proof,
        // the `notesPlaceholders` precedent); the VM threads the live name
        // through it.
        let format = try enString(for: "planner.outsideRun")
        #expect(format == "%1$@ is in progress now")
        #expect(vm.outsideRunSubtitle == String(format: format, "Read docs"))
    }

    @Test("the preload + adopt path carries the outside-run name")
    func preloadAdoptCarriesOutsideName() async throws {
        let (vm, store, _, _) = await makeContext()
        try await store.saveTimerDraft(activityText: "Read docs", categoryIDs: [], startedAt: Date())
        let preloaded = try await PlannerViewModel.preload(store: store)
        vm.adopt(preloaded)
        let format = try enString(for: "planner.outsideRun")
        #expect(vm.outsideRunSubtitle == String(format: format, "Read docs"))
    }

    @Test("a disabled Start tap rejects with the haptic and starts nothing")
    func disabledStartRejects() async throws {
        let (vm, store, _, recorded) = await makeContext()
        await vm.loadIfNeeded()
        vm.draft = "A"
        await vm.submit()
        let task = try #require(vm.snapshot.tasks.first)
        // Idle: Start fires normally (no reject gate).
        #expect(vm.startShouldReject(task) == false)
        // An ordinary run activates the reject gate.
        try await store.saveTimerDraft(activityText: "Read docs", categoryIDs: [], startedAt: Date())
        vm.invalidate()
        await vm.loadIfNeeded()
        #expect(vm.startShouldReject(task))
        vm.rejectDisabledStart()
        #expect(recorded.events == [.success, .reject])
        // Starts nothing: the stored draft is untouched and `startTask`
        // still refuses the replacement at the store boundary.
        #expect(try await store.timerDraft()?.activityText == "Read docs")
        #expect(await vm.startTask(task) == false)
    }

    @Test("completed tasks never take the reject path")
    func completedTasksSkipReject() async throws {
        let (vm, _, _, recorded) = await makeContext()
        await vm.loadIfNeeded()
        vm.draft = "A"
        await vm.submit()
        // Completing plays the success haptic (day-planner 18.1 spec) —
        // the reject gate below only asserts no REJECT was recorded.
        await vm.toggleComplete(try #require(vm.snapshot.tasks.first))
        let completed = try #require(vm.snapshot.tasks.first)
        #expect(vm.startShouldReject(completed) == false)
        #expect(!recorded.events.contains(.reject))
    }

    @Test("completing a task plays success; reopening stays silent")
    func completePlaysSuccessReopenSilent() async throws {
        let (vm, _, _, recorded) = await makeContext()
        await vm.loadIfNeeded()
        vm.draft = "A"
        await vm.submit()
        await vm.toggleComplete(try #require(vm.snapshot.tasks.first))
        #expect(recorded.events == [.success, .success])
        #expect(vm.snapshot.tasks.first?.completedOn != nil)
        await vm.toggleComplete(try #require(vm.snapshot.tasks.first))
        #expect(recorded.events == [.success, .success])
        #expect(vm.snapshot.tasks.first?.completedOn == nil)
    }

    // MARK: - Helpers

    /// A haptic recorder standing in for the generators (day-planner 17.3
    /// precedent): the injected `playHaptic` seam appends here instead of
    /// firing.
    private final class HapticRecorder {
        var events: [PlannerHaptic] = []
    }

    private func makeContext() async -> (
        vm: PlannerViewModel, store: LocalStore, undoBuffer: UndoBufferStore, recorded: HapticRecorder
    ) {
        // swiftlint:disable:next force_try
        let store = try! LocalStore(url: temporaryStoreURL())
        let undoBuffer = UndoBufferStore(store: store)
        let recorded = HapticRecorder()
        let vm = PlannerViewModel(
            store: store,
            undoBuffer: undoBuffer,
            timer: TimerService(store: store)
        ) { recorded.events.append($0) }
        return (vm, store, undoBuffer, recorded)
    }

    private func temporaryStoreURL() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent(LocalStore.databaseFileName(userID: "planner-s18"))
    }

    /// Reads a view source file for the structural tripwires (see the
    /// tests). Resolved from this file's own path, so a move of any file
    /// fails loudly instead of passing vacuously.
    private func featureSource(named file: String) throws -> String {
        let testsDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let url = testsDir
            .deletingLastPathComponent()
            .appendingPathComponent("TimeOfLife/Features/Planner/Views/\(file)")
        return try String(contentsOf: url, encoding: .utf8)
    }

    /// Windows retired by earlier hosted tests, hidden before a new host
    /// goes key (pool-drain timing outlives `HostedPlanner`).
    private static var retiredWindows: [UIWindow] = []

    /// A hosted composer: the REAL `PlannerView` in a key window, field
    /// focused, so dispatch and mounting run the true paths (7.1 probe).
    private func makeHostedPlanner() async throws -> HostedPlanner {
        let (vm, store, _, _) = await makeContext()
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

    /// Polls the hosted hierarchy for the composer `UITextField` (day-planner
    /// 7.1 probe precedent): SwiftUI materializes it asynchronously after
    /// the window goes key.
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

    /// Recursive accessibility-identifier lookup for the composer field
    /// (a real `UITextField`, so its identifier IS in the UIKit hierarchy —
    /// SwiftUI-rendered identifiers live in the AX tree instead and must
    /// never be asserted through a UIView walk).
    private func findView(withIdentifier identifier: String, in view: UIView) -> UIView? {
        if view.accessibilityIdentifier == identifier { return view }
        for subview in view.subviews {
            if let found = findView(withIdentifier: identifier, in: subview) { return found }
        }
        return nil
    }

    /// Resolves a key through the explicit `en` bundle (the
    /// `notesPlaceholders` precedent): exact-copy assertions that hold in
    /// any test-runner locale.
    private func enString(for key: String) throws -> String {
        let path = try #require(
            Bundle.main.path(forResource: "en", ofType: "lproj"),
            "en.lproj missing in main bundle"
        )
        let bundle = try #require(Bundle(path: path))
        return NSLocalizedString(key, bundle: bundle, comment: "")
    }
}

/// Hosted composer keeping its window alive for the test's duration.
private struct HostedPlanner {
    var vm: PlannerViewModel
    var field: UITextField
    var window: UIWindow
    var host: UIViewController
}
