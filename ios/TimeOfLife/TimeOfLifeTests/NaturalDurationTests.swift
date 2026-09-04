import Testing
import Foundation
@testable import TimeOfLife

@Suite("Natural duration formatter")
struct NaturalDurationTests {

    @Test("zero and seconds")
    func secondsOnly() {
        #expect(HistoryViewModel.naturalDuration(0) == "0s")
        #expect(HistoryViewModel.naturalDuration(33) == "33s")
        #expect(HistoryViewModel.naturalDuration(59) == "59s")
    }

    @Test("minutes with and without seconds")
    func minutes() {
        #expect(HistoryViewModel.naturalDuration(60) == "1m")
        #expect(HistoryViewModel.naturalDuration(80) == "1m 20s")
        #expect(HistoryViewModel.naturalDuration(3320) == "55m 20s")
    }

    @Test("hours with and without minutes")
    func hours() {
        #expect(HistoryViewModel.naturalDuration(3600) == "1h")
        #expect(HistoryViewModel.naturalDuration(4320) == "1h 12m")
        #expect(HistoryViewModel.naturalDuration(43_200) == "12h")
    }

    @Test("days with and without hours")
    func days() {
        #expect(HistoryViewModel.naturalDuration(86_400) == "1d")
        #expect(HistoryViewModel.naturalDuration(129_600) == "1d 12h")
        #expect(HistoryViewModel.naturalDuration(86_400 * 3) == "3d")
    }

    @Test("negative clamps to zero")
    func negativeClamps() {
        #expect(HistoryViewModel.naturalDuration(-5) == "0s")
    }
}
