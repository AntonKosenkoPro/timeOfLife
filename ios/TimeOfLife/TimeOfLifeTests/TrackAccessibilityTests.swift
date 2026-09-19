import Testing
import Foundation
@testable import TimeOfLife

@MainActor
@Suite("Track Accessibility")
struct TrackAccessibilityTests {

    private let draft = TrackState.Draft(text: "Deep work", categoryIDs: ["c1"])

    @Test("idle readout announces the idle prompt")
    func idleReadoutLabel() {
        let state = TrackState.idle
        #expect(state.readoutAccessibilityLabel == L10n.timerIdlePrompt.text)
        #expect(state.elapsed(at: Date()) == 0)
    }

    @Test("ready readout announces name and ready state")
    func readyReadoutLabel() {
        let state = TrackState.ready(draft)
        #expect(state.readoutAccessibilityLabel.contains(draft.text))
        #expect(state.readoutAccessibilityLabel.contains(L10n.timerReady.text))
        #expect(state.elapsed(at: Date()) == 0)
    }

    @Test("running readout announces name and live elapsed")
    func runningReadoutLabel() {
        let startedAt = Date().addingTimeInterval(-125)
        let state = TrackState.running(draft, startedAt: startedAt)
        #expect(state.readoutAccessibilityLabel.contains(draft.text))
        #expect(state.isRunning)
        #expect(state.elapsed(at: startedAt.addingTimeInterval(125)) >= 125)
    }

    @Test("saved readout announces saved state and duration")
    func savedReadoutLabel() {
        let state = TrackState.saved(draft, duration: 90)
        #expect(state.readoutAccessibilityLabel.contains(L10n.timerSaved.text))
        #expect(state.elapsed(at: Date()) == 90)
        #expect(!state.isRunning)
    }

    @Test("error state preserves running semantics")
    func errorPreservesRunning() {
        let startedAt = Date().addingTimeInterval(-60)
        let state = TrackState.error(draft, startedAt: startedAt)
        #expect(state.isRunning)
        #expect(state.elapsed(at: startedAt.addingTimeInterval(60)) >= 60)
    }

    @Test("compact label announces name and running state")
    func compactLabel() {
        let state = TrackState.running(draft, startedAt: Date())
        #expect(state.compactAccessibilityLabel == String(format: L10n.timerCompactRunning.text, draft.text))
        #expect(state.compactAccessibilityLabel.contains(draft.text))
    }

    @Test("saving state is not running and reports saving")
    func savingState() {
        let state = TrackState.saving(draft, startedAt: Date())
        #expect(state.isSaving)
        #expect(!state.isRunning)
    }

    @Test("non-idle states expose a draft")
    func nonIdleStatesHaveDraft() {
        #expect(TrackState.ready(draft).draft != nil)
        #expect(TrackState.running(draft, startedAt: Date()).draft != nil)
        #expect(TrackState.saving(draft, startedAt: Date()).draft != nil)
        #expect(TrackState.saved(draft, duration: 60).draft != nil)
        #expect(TrackState.error(draft, startedAt: Date()).draft != nil)
    }

    @Test("idle state exposes no draft")
    func idleStateHasNoDraft() {
        #expect(TrackState.idle.draft == nil)
    }

    @Test("exact-text identity is case-sensitive")
    func exactTextIdentity() {
        #expect(TrackState.Draft(text: "Gym") != TrackState.Draft(text: "GYM"))
        #expect(TrackState.ready(TrackState.Draft(text: "Gym")) != TrackState.ready(TrackState.Draft(text: "GYM")))
    }
}
