import Testing
import Foundation
@testable import TimeOfLife

@Suite("Natural duration formatter")
struct NaturalDurationTests {
    private static let en = Locale(identifier: "en")
    private static let ru = Locale(identifier: "ru")

    @Test("zero and seconds")
    func secondsOnly() {
        #expect(HistoryViewModel.naturalDuration(0, locale: Self.en) == "0s")
        #expect(HistoryViewModel.naturalDuration(33, locale: Self.en) == "33s")
        #expect(HistoryViewModel.naturalDuration(59, locale: Self.en) == "59s")
    }

    @Test("minutes with and without seconds")
    func minutes() {
        #expect(HistoryViewModel.naturalDuration(60, locale: Self.en) == "1m")
        #expect(HistoryViewModel.naturalDuration(80, locale: Self.en) == "1m 20s")
        #expect(HistoryViewModel.naturalDuration(3320, locale: Self.en) == "55m 20s")
    }

    @Test("hours with and without minutes")
    func hours() {
        #expect(HistoryViewModel.naturalDuration(3600, locale: Self.en) == "1h")
        #expect(HistoryViewModel.naturalDuration(4320, locale: Self.en) == "1h 12m")
        #expect(HistoryViewModel.naturalDuration(43_200, locale: Self.en) == "12h")
    }

    @Test("days with and without hours")
    func days() {
        #expect(HistoryViewModel.naturalDuration(86_400, locale: Self.en) == "1d")
        #expect(HistoryViewModel.naturalDuration(129_600, locale: Self.en) == "1d 12h")
        #expect(HistoryViewModel.naturalDuration(86_400 * 3, locale: Self.en) == "3d")
    }

    @Test("negative clamps to zero")
    func negativeClamps() {
        #expect(HistoryViewModel.naturalDuration(-5, locale: Self.en) == "0s")
    }

    @Test("Russian locale uses Russian abbreviations")
    func russianUnits() {
        #expect(HistoryViewModel.naturalDuration(0, locale: Self.ru) == "0 с")
        #expect(HistoryViewModel.naturalDuration(33, locale: Self.ru) == "33 с")
        #expect(HistoryViewModel.naturalDuration(60, locale: Self.ru) == "1 мин")
        #expect(HistoryViewModel.naturalDuration(80, locale: Self.ru) == "1 мин 20 с")
        #expect(HistoryViewModel.naturalDuration(3320, locale: Self.ru) == "55 мин 20 с")
        #expect(HistoryViewModel.naturalDuration(3600, locale: Self.ru) == "1 ч")
        #expect(HistoryViewModel.naturalDuration(4320, locale: Self.ru) == "1 ч 12 мин")
        #expect(HistoryViewModel.naturalDuration(43_200, locale: Self.ru) == "12 ч")
        #expect(HistoryViewModel.naturalDuration(86_400, locale: Self.ru) == "1 д.")
        #expect(HistoryViewModel.naturalDuration(129_600, locale: Self.ru) == "1 д. 12 ч")
        #expect(HistoryViewModel.naturalDuration(86_400 * 3, locale: Self.ru) == "3 д.")
        #expect(HistoryViewModel.naturalDuration(-5, locale: Self.ru) == "0 с")
    }
}
