import Testing
import Foundation
@testable import TimeOfLife

/// Planner Start hands off to Track (day-planner 9.2): starting an open
/// task from Today and returning to Track must present the running timer
/// at once — no extra navigation. Owner repro 2026-11-26: a planner Start
/// returned to a Track that looked unstarted until leaving for History and
/// back, because the pop performed no Track reload and the settled idle
/// snapshot stayed on screen.
@MainActor
@Suite("Planner Start hands off to Track (day-planner 9.2)")
struct PlannerTrackHandoffTests {
    @Test("planner Start then immediate Track snapshot shows running")
    func plannerStartShowsRunningImmediately() async throws {
        let store = try LocalStore(url: temporaryStoreURL())
        let timer = TimerService(store: store)
        let plannerVM = PlannerViewModel(
            store: store,
            undoBuffer: UndoBufferStore(store: store),
            timer: timer
        )
        let trackVM = TrackViewModel(service: timer, connectivity: MockConnectivity(connected: true))
        // Both settled before the handoff, as in production: Track painted
        // idle on first appear and Today loaded its rows, so neither wants
        // a reload on its own.
        await trackVM.loadIfNeeded()
        await plannerVM.loadIfNeeded()
        #expect(trackVM.state == .idle)
        plannerVM.draft = "Read"
        await plannerVM.submit()
        let task = try #require(plannerVM.snapshot.tasks.first)
        #expect(await plannerVM.startTask(task))
        // The return to Track (AppShell pops the planner route and runs
        // its serialized reload after a successful Start): Track reloads
        // the stale snapshot so the run presents immediately.
        trackVM.invalidate()
        await trackVM.loadIfNeeded()
        guard case let .running(draft, _) = trackVM.state else {
            Issue.record("Track still \(trackVM.state) immediately after a planner Start — stale idle")
            return
        }
        #expect(draft.text == "Read")
    }

    private func temporaryStoreURL() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent(LocalStore.databaseFileName(userID: "planner-handoff"))
    }
}
