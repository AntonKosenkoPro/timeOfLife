import Testing
import Foundation
@testable import TimeOfLife

/// Day-planner §20: the blocked-Start error never appeared on device
/// (owner report 2026-11-27 — reject haptic plays, no message).
/// Root cause: the inline error lived INSIDE the chips/notes gate in
/// `PlannerTaskRow`, so a bare task (no categories, no notes) could never
/// render it even though `rejectDisabledStart` set the state and played the
/// haptic. The instant-clearing and stale-`timerActive` suspects are pinned
/// below as excluded: a reload while the run is active keeps the error, and
/// the stale path is silent (no haptic) — a different symptom.
@MainActor
@Suite("Planner section 20 (blocked-Start error shows for bare tasks)", .serialized)
struct PlannerSection20Tests {
    // MARK: - 20.1 bare-task repro (owner shape)

    @Test("a rejected tap on a bare task keeps the error visible across reloads until idle")
    func bareTaskRejectKeepsErrorVisible() async throws {
        let (vm, store, _, recorded) = await makeContext()
        await vm.loadIfNeeded()
        vm.draft = "A"
        await vm.submit()
        let task = try #require(vm.snapshot.tasks.first)
        // The owner's shape: no categories, no notes.
        #expect(task.categoryIDs.isEmpty)
        #expect(task.notes.isEmpty)
        try await store.saveTimerDraft(activityText: "Read docs", categoryIDs: [], startedAt: Date())
        vm.invalidate()
        await vm.loadIfNeeded()
        // The reject path runs (not the silent stale-`timerActive`
        // `startTask` path): the view branch is `startShouldReject`, and the
        // reject haptic the owner felt only fires here.
        #expect(vm.startShouldReject(task))
        vm.rejectDisabledStart(for: task)
        #expect(vm.blockedStartTaskID == task.id)
        #expect(recorded.events == [.success, .reject])
        // Immediate reloads while the run is active must not clear it
        // (the instant-clearing suspect is excluded).
        vm.invalidate()
        await vm.loadIfNeeded()
        #expect(vm.blockedStartTaskID == task.id)
        // Cleared when the run goes idle.
        try await store.clearTimerDraft()
        vm.invalidate()
        await vm.loadIfNeeded()
        #expect(vm.blockedStartTaskID == nil)
    }

    @Test("the stale-timerActive path stays silent with no haptic (a different symptom)")
    func staleTimerActivePathIsSilent() async throws {
        let (vm, store, _, recorded) = await makeContext()
        await vm.loadIfNeeded()
        vm.draft = "A"
        await vm.submit()
        let task = try #require(vm.snapshot.tasks.first)
        // A run started elsewhere after the last planner load: the VM still
        // reads idle, so the view would take `startTask` — which refuses the
        // replacement at the store boundary with no haptic and no error.
        // (No invalidate: the VM never reloaded, still stale-idle.)
        try await store.saveTimerDraft(activityText: "Read docs", categoryIDs: [], startedAt: Date())
        #expect(!vm.startShouldReject(task))
        #expect(await vm.startTask(task) == false)
        #expect(recorded.events == [.success])
        #expect(vm.blockedStartTaskID == nil)
    }

    @Test("an ordinary Start on a bare task still starts when idle")
    func ordinaryBareStartUnregressed() async throws {
        let (vm, _, _, _) = await makeContext()
        await vm.loadIfNeeded()
        vm.draft = "A"
        await vm.submit()
        let task = try #require(vm.snapshot.tasks.first)
        #expect(await vm.startTask(task))
        #expect(vm.blockedStartTaskID == nil)
    }

    // MARK: - 20.1 render gate (the actual defect)

    @Test("the blocked-Start error is not gated on chips or notes")
    func blockedErrorNotGatedOnChipsOrNotes() throws {
        let row = try timeOfLifeSource(relativePath: "TimeOfLife/Features/Planner/Views/PlannerTaskRow.swift")
        // The chips/notes-gated region must not own the error: a bare task
        // (no categories, no notes) skips that region entirely, so an error
        // nested inside it never mounts — the owner's haptic-but-no-message.
        let chipsGate = try closureBody(in: row, marker: "if !slice.shown.isEmpty")
        #expect(!chipsGate.contains("blockedError"), "the blocked-Start error must render outside the chips/notes gate")
        #expect(row.contains("PlannerBlockedStartError"), "the inline error view is missing")
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
            .appendingPathComponent(LocalStore.databaseFileName(userID: "planner-s20"))
    }

    /// Reads a source file under `TimeOfLife/` for the structural tripwire.
    /// Resolved from this file's own path, so a move of any file fails
    /// loudly instead of passing vacuously.
    private func timeOfLifeSource(relativePath: String) throws -> String {
        let testsDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let url = testsDir
            .deletingLastPathComponent()
            .appendingPathComponent(relativePath)
        return try String(contentsOf: url, encoding: .utf8)
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
