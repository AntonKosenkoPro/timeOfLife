import Testing
import Foundation
@testable import TimeOfLife
import LifioLiveActivityCore

/// Live-style duration for the expanded timer (device finding): leftmost
/// unit unpadded (`0:01`, `12:34`, `1:23:45`) — matches what
/// `Text(timerInterval:)` renders, so the hidden sizing twin and the live
/// view share one format and the bordered capsule hugs the digits.
@Suite("TimerClock live style")
struct TimerClockTests {

    @Test("live style matches the reference durations")
    func referenceDurations() {
        #expect(TimerClock.liveStyle(1) == "0:01")
        #expect(TimerClock.liveStyle(83) == "1:23")
        #expect(TimerClock.liveStyle(754) == "12:34")
        #expect(TimerClock.liveStyle(5025) == "1:23:45")
        #expect(TimerClock.liveStyle(45296) == "12:34:56")
    }

    @Test("unit boundaries switch the width")
    func boundaries() {
        #expect(TimerClock.liveStyle(59) == "0:59")
        #expect(TimerClock.liveStyle(60) == "1:00")
        #expect(TimerClock.liveStyle(599) == "9:59")
        #expect(TimerClock.liveStyle(600) == "10:00")
        #expect(TimerClock.liveStyle(3599) == "59:59")
        #expect(TimerClock.liveStyle(3600) == "1:00:00")
    }

    @Test("negative clamps to zero")
    func negativeClamps() {
        #expect(TimerClock.liveStyle(-30) == "0:00")
    }
}
