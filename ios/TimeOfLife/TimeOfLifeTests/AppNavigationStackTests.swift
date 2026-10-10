import Testing
import Foundation
@testable import TimeOfLife

/// Tap-request counters (fix-terminated-stop-saved-face Spike D + AI-review
/// round 1): the shell observes both counters with `filter { $0 > 0 }`, which
/// replays the CURRENT value on every shell (re)subscription while this stack
/// outlives the shell at app scope — so sign-out must clear them, or the next
/// shell mount re-fires the last tap and can stop a run the user never
/// stopped. A fresh process starts at zero, so cold opens are unaffected.
@MainActor
@Suite("AppNavigationStackTapRequests")
struct AppNavigationStackTapRequestsTests {

    @Test("counters start at zero and bump monotonically")
    func countersBumpMonotonically() {
        let navigation = AppNavigationStack()
        #expect(navigation.trackRequestID == 0)
        #expect(navigation.islandStopRequestID == 0)

        navigation.requestTrack()
        navigation.requestTrack()
        navigation.requestIslandStop()

        #expect(navigation.trackRequestID == 2)
        #expect(navigation.islandStopRequestID == 1)
    }

    @Test("resetTapRequests clears both counters")
    func resetClearsBothCounters() {
        let navigation = AppNavigationStack()
        navigation.requestTrack()
        navigation.requestIslandStop()

        navigation.resetTapRequests()

        #expect(navigation.trackRequestID == 0)
        #expect(navigation.islandStopRequestID == 0)
    }
}
