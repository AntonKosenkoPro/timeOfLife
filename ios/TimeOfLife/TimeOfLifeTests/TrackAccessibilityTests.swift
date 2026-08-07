import Testing
import Foundation
@testable import TimeOfLife

@MainActor
@Suite("Track Accessibility")
struct TrackAccessibilityTests {

    @Test("idle readout announces choose-activity prompt")
    func idleReadoutLabel() {
        let state = TrackState.idle
        #expect(state.readoutAccessibilityLabel == L10n.timerChooseActivityPrompt.text)
        #expect(state.elapsed(at: Date()) == 0)
    }

    @Test("ready readout announces activity and ready state")
    func readyReadoutLabel() {
        let activity = Activity(id: "a1", name: "Deep work")
        let state = TrackState.ready(activity)
        #expect(state.readoutAccessibilityLabel.contains(activity.name))
        #expect(state.readoutAccessibilityLabel.contains(L10n.timerReady.text))
        #expect(state.elapsed(at: Date()) == 0)
    }

    @Test("running readout announces activity and live elapsed")
    func runningReadoutLabel() {
        let activity = Activity(id: "a1", name: "Reading")
        let startedAt = Date().addingTimeInterval(-125)
        let state = TrackState.running(activity, startedAt: startedAt)
        #expect(state.readoutAccessibilityLabel.contains(activity.name))
        #expect(state.isRunning)
        #expect(state.elapsed(at: Date()) >= 125)
    }

    @Test("saved readout announces saved state and duration")
    func savedReadoutLabel() {
        let activity = Activity(id: "a1", name: "Work")
        let state = TrackState.saved(activity, duration: 90)
        #expect(state.readoutAccessibilityLabel.contains(L10n.timerSaved.text))
        #expect(state.elapsed(at: Date()) == 90)
        #expect(!state.isRunning)
    }

    @Test("error state preserves running semantics")
    func errorPreservesRunning() {
        let activity = Activity(id: "a1", name: "Work")
        let startedAt = Date().addingTimeInterval(-60)
        let state = TrackState.error(activity, startedAt: startedAt)
        #expect(state.isRunning)
        #expect(state.elapsed(at: Date()) >= 60)
    }

    @Test("compact label announces activity and running state")
    func compactLabel() {
        let activity = Activity(id: "a1", name: "Deep work")
        let state = TrackState.running(activity, startedAt: Date())
        #expect(state.compactAccessibilityLabel == String(format: L10n.timerCompactRunning.text, activity.name))
        #expect(state.compactAccessibilityLabel.contains(activity.name))
    }

    @Test("saving state is not running and reports saving")
    func savingState() {
        let activity = Activity(id: "a1", name: "Work")
        let state = TrackState.saving(activity, startedAt: Date())
        #expect(state.isSaving)
        #expect(!state.isRunning)
    }
}
