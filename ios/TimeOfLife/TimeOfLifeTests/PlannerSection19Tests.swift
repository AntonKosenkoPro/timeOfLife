import Testing
import Foundation
@testable import TimeOfLife

/// Day-planner §19: the blocked-Start inline error, the explicit
/// running-delete error, the aligned red destructive `Delete`, the
/// read-only running name, and the detached circular dismiss.
/// Pins VM helpers + structural tripwires; haptics via the seam.
@MainActor
@Suite("Planner section 19 (explicit errors, aligned Delete, read-only name, detached dismiss)", .serialized)
struct PlannerSection19Tests {
    // MARK: - 19.1 blocked-Start error

    @Test("a blocked Start records the inline error with the reject haptic and starts nothing")
    func blockedStartSetsErrorAndRejects() async throws {
        let (vm, store, _, recorded) = await makeContext()
        await vm.loadIfNeeded()
        vm.draft = "A"
        await vm.submit()
        let task = try #require(vm.snapshot.tasks.first)
        try await store.saveTimerDraft(activityText: "Read docs", categoryIDs: [], startedAt: Date())
        vm.invalidate()
        await vm.loadIfNeeded()
        #expect(vm.blockedStartTaskID == nil)
        vm.rejectDisabledStart(for: task)
        #expect(vm.blockedStartTaskID == task.id)
        #expect(recorded.events == [.success, .reject])
        // The en copy is pinned through the explicit bundle
        // (locale-proof, the `notesPlaceholders` precedent).
        #expect(try enString(for: "planner.blockedStart") == "You can't start a task while another is running")
        // Starts nothing: the stored draft is untouched and `startTask`
        // still refuses the replacement at the store boundary.
        #expect(try await store.timerDraft()?.activityText == "Read docs")
        #expect(await vm.startTask(task) == false)
    }

    @Test("the blocked error clears when the run goes idle")
    func blockedErrorClearsWhenIdle() async throws {
        let (vm, store, _, _) = await makeContext()
        await vm.loadIfNeeded()
        vm.draft = "A"
        await vm.submit()
        let task = try #require(vm.snapshot.tasks.first)
        try await store.saveTimerDraft(activityText: "Read docs", categoryIDs: [], startedAt: Date())
        vm.invalidate()
        await vm.loadIfNeeded()
        vm.rejectDisabledStart(for: task)
        #expect(vm.blockedStartTaskID == task.id)
        try await store.clearTimerDraft()
        vm.invalidate()
        await vm.loadIfNeeded()
        #expect(vm.blockedStartTaskID == nil)
    }

    @Test("the blocked error clears on a successful Start")
    func blockedErrorClearsOnSuccessfulStart() async throws {
        let (vm, store, _, _) = await makeContext()
        await vm.loadIfNeeded()
        vm.draft = "A"
        await vm.submit()
        let task = try #require(vm.snapshot.tasks.first)
        try await store.saveTimerDraft(activityText: "Read docs", categoryIDs: [], startedAt: Date())
        vm.invalidate()
        await vm.loadIfNeeded()
        vm.rejectDisabledStart(for: task)
        #expect(vm.blockedStartTaskID == task.id)
        try await store.clearTimerDraft()
        vm.invalidate()
        await vm.loadIfNeeded()
        #expect(await vm.startTask(try #require(vm.snapshot.tasks.first)))
        #expect(vm.blockedStartTaskID == nil)
    }

    @Test("the outside-run string is gone from the contract and the sources")
    func outsideRunStringRemoved() throws {
        let l10n = try timeOfLifeSource(relativePath: "TimeOfLife/Localization/String+Localized.swift")
        #expect(!l10n.contains("\"planner.outsideRun\""), "plannerOutsideRun must not come back")
        let plannerView = try timeOfLifeSource(relativePath: "TimeOfLife/Features/Planner/Views/PlannerView.swift")
        #expect(!plannerView.contains("outsideRunSubtitle"), "the nav-bar subtitle must not come back")
        #expect(!plannerView.contains("OutsideRunSubtitle"), "the nav-bar subtitle view must not come back")
        #expect(!plannerView.contains("subtitleShakeAttempts"), "the subheader shake must not come back")
        // The key resolves to itself in the en bundle (unresolved).
        #expect(try enString(for: "planner.outsideRun") == "planner.outsideRun")
    }

    @Test("the row carries the inline blocked error with shake")
    func rowCarriesInlineBlockedError() throws {
        let row = try timeOfLifeSource(relativePath: "TimeOfLife/Features/Planner/Views/PlannerTaskRow.swift")
        #expect(row.contains("PlannerBlockedStartError"), "the inline error view is missing")
        #expect(row.contains("blockedError"), "the row must take the blocked error")
        #expect(row.contains("keyframeAnimator"), "the inline error must shake")
        let plannerView = try timeOfLifeSource(relativePath: "TimeOfLife/Features/Planner/Views/PlannerView.swift")
        #expect(plannerView.contains("L10n.plannerBlockedStart"), "the row must read the blocked-Start copy")
        #expect(plannerView.contains("blockedError:"), "the row must take the blocked error")
        #expect(plannerView.contains("shakeAttempts:"), "the row must take the shake trigger")
        #expect(plannerView.contains("rejectDisabledStart(for:"), "rejects go through the blocked task")
    }

    // MARK: - 19.2 running-delete error

    @Test("a running-delete tap shows the explicit error with the reject haptic and deletes nothing")
    func runningDeleteShowsExplicitError() async throws {
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
        // The en copy is pinned through the explicit bundle.
        #expect(try enString(for: "planner.deleteRunning") == "You can't delete the running task")
        #expect(vm.deleteBlockedMessage == "You can't delete the running task")
        // Deletes nothing: the row stays, the sheet stays open, and no
        // undo row is buffered.
        #expect(vm.snapshot.tasks.map(\.id) == [task.id])
        #expect(vm.editingTask?.id == task.id)
        #expect(try await undoBuffer.mostRecent() == nil)
    }

    @Test("the blocked-delete error clears on a fresh scope and on save")
    func deleteBlockedErrorClearsOnScopeAndSave() async throws {
        let (vm, _, _, _) = await makeContext()
        await vm.loadIfNeeded()
        vm.draft = "A"
        await vm.submit()
        let task = try #require(vm.snapshot.tasks.first)
        #expect(await vm.startTask(task))
        vm.invalidate()
        await vm.loadIfNeeded()
        vm.beginEdit(try #require(vm.snapshot.tasks.first))
        #expect(await vm.attemptDeleteEditingTask() == false)
        #expect(vm.deleteBlockedMessage != nil)
        // A fresh sheet scope clears it.
        vm.beginEdit(try #require(vm.snapshot.tasks.first))
        #expect(vm.deleteBlockedMessage == nil)
        #expect(await vm.attemptDeleteEditingTask() == false)
        #expect(vm.deleteBlockedMessage != nil)
        // A successful save clears it too.
        vm.sheetNotes = "chapter 3"
        #expect(await vm.saveSheet())
        #expect(vm.deleteBlockedMessage == nil)
    }

    @Test("the sheet carries the explicit delete error cluster")
    func sheetCarriesDeleteErrorCluster() throws {
        let sheet = try timeOfLifeSource(relativePath: "TimeOfLife/Features/Planner/Views/PlannerTaskEditorSheet.swift")
        #expect(sheet.contains("DestructiveBottomButton("), "the sheet must share the entry-form Delete control")
        #expect(sheet.contains("entryDeleteConfirm"), "the sheet Delete must read the plain Delete copy")
        #expect(!sheet.contains("buttonStyle(.bordered)"), "the bordered trash button must not come back")
        #expect(sheet.contains("PlannerEditorDeleteError"), "the explicit delete error view is missing")
        #expect(sheet.contains("deleteBlockedMessage"), "the sheet must read the blocked-delete error")
        #expect(sheet.contains("keyframeAnimator"), "the delete cluster must shake")
    }

    // MARK: - 19.3 Delete parity

    @Test("the entry form and the sheet share the red destructive Delete")
    func entryFormAndSheetSharePlainDelete() async throws {
        // HIG destructive wording: the plain `Delete` label.
        #expect(try enString(for: "entry.deleteConfirm") == "Delete")
        let entryForm = try timeOfLifeSource(relativePath: "TimeOfLife/Features/ManualEntry/Views/LogTimeView.swift")
        #expect(entryForm.contains("title: L10n.entryDeleteConfirm.text"), "the entry form must read the plain Delete copy")
        #expect(!entryForm.contains("L10n.entryDelete.text"), "the `Delete entry` title must not come back")
    }

    @Test("the entry.delete key is gone from the contract")
    func entryDeleteKeyRemoved() throws {
        let l10n = try timeOfLifeSource(relativePath: "TimeOfLife/Localization/String+Localized.swift")
        #expect(!l10n.contains("\"entry.delete\""), "entryDelete must not come back")
        #expect(try enString(for: "entry.delete") == "entry.delete")
    }

    // MARK: - 19.4 read-only name

    @Test("a running-task sheet save converges categories and notes with the locked name")
    func runningTaskSheetConvergesLiveFields() async throws {
        let (vm, store, _, _) = await makeContext(categories: [("c1", "Work"), ("c2", "Gym")])
        await vm.loadIfNeeded()
        vm.draft = "A"
        await vm.submit()
        let task = try #require(vm.snapshot.tasks.first)
        #expect(await vm.startTask(task))
        vm.invalidate()
        await vm.loadIfNeeded()
        vm.beginEdit(try #require(vm.snapshot.tasks.first))
        #expect(vm.isEditingRunningTask)
        // The name draft is prefilled and untouched (the UI locks it —
        // pinned by the tripwire below); Categories and Notes stay editable.
        #expect(vm.sheetName == "A")
        vm.sheetCategoryIDs = ["c1"]
        vm.sheetNotes = "chapter 3"
        #expect(await vm.saveSheet())
        #expect(vm.snapshot.tasks.first?.name == "A")
        #expect(vm.snapshot.tasks.first?.categoryIDs == ["c1"])
        #expect(vm.snapshot.tasks.first?.notes == "chapter 3")
        let draft = try #require(try await store.timerDraft())
        #expect(draft.activityText == "A")
        #expect(draft.categoryIDs == ["c1"])
        #expect(draft.notes == "chapter 3")
        // The unchanged name sends no rename intent.
        let intents = try await store.outboxRows().compactMap { row -> String? in
            guard let payload = row.payload?.data(using: .utf8) else { return nil }
            return try? JSONDecoder().decode(PlannerOperationPayload.self, from: payload).intent
        }.filter { $0 != PlannerIntent.create.rawValue }
        #expect(!intents.contains(PlannerIntent.rename.rawValue))
    }

    @Test("the sheet locks the Name card for the running task only")
    func sheetLocksNameForRunningTask() throws {
        let sheet = try timeOfLifeSource(relativePath: "TimeOfLife/Features/Planner/Views/PlannerTaskEditorSheet.swift")
        let nameCard = try closureBody(in: sheet, marker: "private var nameCard")
        #expect(nameCard.contains("isEditingRunningTask"), "the Name card must branch on the running task")
        #expect(nameCard.contains("EntryNameCard"), "other tasks keep the shared Name entry card")
        #expect(!nameCard.contains("NavigationLink"), "the locked Name must not push the picker")
    }

    // MARK: - 19.5 detached dismiss

    @Test("the dismiss control shows while editing, even for an empty draft")
    func dismissVisibilityRule() {
        // Editing-only (the `ClearButtonVisibility` precedent): unchanged
        // by the detach — only the placement moved.
        #expect(ComposerDismissVisibility.shouldShow(isEditing: true))
        #expect(!ComposerDismissVisibility.shouldShow(isEditing: false))
    }

    @Test("the dismiss control rides beside the card as a detached circle")
    func dismissRidesBesideTheCard() throws {
        let row = try timeOfLifeSource(relativePath: "TimeOfLife/Features/Planner/Views/PlannerComposerRow.swift")
        #expect(row.contains("PlannerComposerDismiss"), "the dismiss control is missing")
        #expect(row.contains("xmark.circle.fill"), "the dismiss must use the Mail search-clear circle")
        #expect(row.contains("dismissID += 1"), "the dismiss must resign through the dismiss request")
        #expect(!row.contains("keyboard.chevron.compact.down"), "the in-card chevron must not come back")
        let card = try closureBody(in: row, marker: "FieldCard {")
        #expect(!card.contains("PlannerComposerDismiss"), "the dismiss must not live inside the card")
    }

    // MARK: - Helpers

    /// A haptic recorder standing in for the generators (day-planner 17.3
    /// precedent): the injected `playHaptic` seam appends here instead of
    /// firing.
    private final class HapticRecorder {
        var events: [PlannerHaptic] = []
    }

    private func makeContext(categories: [(id: String, name: String)] = []) async -> (
        vm: PlannerViewModel, store: LocalStore, undoBuffer: UndoBufferStore, recorded: HapticRecorder
    ) {
        // swiftlint:disable:next force_try
        let store = try! LocalStore(url: temporaryStoreURL())
        for category in categories {
            _ = try? await store.createCategory(Category(id: category.id, name: category.name, icon: CatalogIcon.tag.rawValue))
        }
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
            .appendingPathComponent(LocalStore.databaseFileName(userID: "planner-s19"))
    }

    /// Reads a source file under `TimeOfLife/` for the structural tripwires
    /// (see the tests). Resolved from this file's own path, so a move of any
    /// file fails loudly instead of passing vacuously.
    private func timeOfLifeSource(relativePath: String) throws -> String {
        let testsDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let url = testsDir
            .deletingLastPathComponent()
            .appendingPathComponent(relativePath)
        return try String(contentsOf: url, encoding: .utf8)
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

    /// Extracts the first `{...}` closure body after `marker`. String
    /// literals and line comments are masked first, so braces inside them
    /// never unbalance the scan.
    private func closureBody(in source: String, marker: String) throws -> String {
        let markerRange = try #require(source.range(of: marker), "marker missing: \(marker)")
        let after = String(source[markerRange.upperBound...])
        guard let open = after.firstIndex(of: "{") else { throw ClosureScanError.unbalanced }
        let masked = maskLiteralsAndComments(after)
        var depth = 0
        var index = open
        while index < masked.endIndex {
            if masked[index] == "{" {
                depth += 1
            } else if masked[index] == "}" {
                depth -= 1
                if depth == 0 { return String(after[open...index]) }
            }
            index = masked.index(after: index)
        }
        throw ClosureScanError.unbalanced
    }

    /// Blanks string literals and line comments (length-preserving), so the
    /// brace scan never sees their braces. Escapes honored inside strings.
    private func maskLiteralsAndComments(_ source: String) -> String {
        var output = ""
        output.reserveCapacity(source.count)
        var index = source.startIndex
        var inString = false
        var escaped = false
        while index < source.endIndex {
            let char = source[index]
            if inString {
                output.append(" ")
                if escaped {
                    escaped = false
                } else if char == "\\" {
                    escaped = true
                } else if char == "\"" {
                    inString = false
                }
            } else if char == "\"" {
                inString = true
                output.append(" ")
            } else if char == "/", source.index(after: index) < source.endIndex,
                      source[source.index(after: index)] == "/" {
                while index < source.endIndex, source[index] != "\n" {
                    output.append(" ")
                    index = source.index(after: index)
                }
                continue
            } else {
                output.append(char)
            }
            index = source.index(after: index)
        }
        return output
    }
}

private enum ClosureScanError: Error {
    case unbalanced
}
