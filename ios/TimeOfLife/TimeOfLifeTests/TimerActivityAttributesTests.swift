import Testing
import Foundation
@testable import TimeOfLife
import LifioLiveActivityCore

@Suite("TimerActivityAttributes")
struct TimerActivityAttributesTests {

    @Test("Attributes Codable round-trip preserves exact text verbatim")
    func attributesRoundTrip() throws {
        let original = TimerActivityAttributes(entryText: "Gym", iconSymbol: "dumbbell", localeIdentifier: "en")
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(TimerActivityAttributes.self, from: data)
        #expect(decoded == original)
        #expect(decoded.entryText == "Gym")
    }

    @Test("Case-distinct texts stay distinct through Codable")
    func caseSensitiveIdentity() throws {
        let lower = TimerActivityAttributes(entryText: "gym", iconSymbol: "timer", localeIdentifier: "en")
        let upper = TimerActivityAttributes(entryText: "GYM", iconSymbol: "timer", localeIdentifier: "en")
        #expect(lower != upper)
    }

    @Test("Attributes round-trip preserves the request locale")
    func attributesLocaleRoundTrip() throws {
        let original = TimerActivityAttributes(entryText: "Corrida matinal", iconSymbol: "timer", localeIdentifier: "pt-BR")
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(TimerActivityAttributes.self, from: data)
        #expect(decoded == original)
        #expect(decoded.localeIdentifier == "pt-BR")
    }

    @Test("Same text with different request locales stays distinct")
    func attributesLocaleDistinguishes() {
        let pt = TimerActivityAttributes(entryText: "Run", iconSymbol: "timer", localeIdentifier: "pt-BR")
        let es = TimerActivityAttributes(entryText: "Run", iconSymbol: "timer", localeIdentifier: "es-419")
        #expect(pt != es)
    }

    @Test("Running ContentState round-trips with nil saved duration")
    func runningStateRoundTrip() throws {
        let startedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let original = TimerActivityAttributes.ContentState(startedAt: startedAt)
        #expect(original.savedDurationSeconds == nil)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(TimerActivityAttributes.ContentState.self, from: data)
        #expect(decoded == original)
    }

    @Test("Saved ContentState round-trips the final duration")
    func savedStateRoundTrip() throws {
        let original = TimerActivityAttributes.ContentState(
            startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            savedDurationSeconds: 2832
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(TimerActivityAttributes.ContentState.self, from: data)
        #expect(decoded == original)
        #expect(decoded.savedDurationSeconds == 2832)
    }

    @Test("liveIconSymbol follows the first ordered chip")
    func liveIconFollowsFirstChip() {
        let state = TimerActivityAttributes.ContentState(
            startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            categoryChips: [
                LiveCategoryChip(name: "Sport", iconSymbol: "dumbbell.fill"),
                LiveCategoryChip(name: "Work", iconSymbol: "briefcase.fill"),
            ]
        )
        #expect(state.liveIconSymbol == "dumbbell.fill")
    }

    @Test("liveIconSymbol changes on reorder without touching startedAt")
    func liveIconChangesOnReorder() {
        let startedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let reordered = TimerActivityAttributes.ContentState(
            startedAt: startedAt,
            categoryChips: [
                LiveCategoryChip(name: "Work", iconSymbol: "briefcase.fill"),
                LiveCategoryChip(name: "Sport", iconSymbol: "dumbbell.fill"),
            ]
        )
        #expect(reordered.liveIconSymbol == "briefcase.fill")
        #expect(reordered.startedAt == startedAt)
        #expect(reordered.categoryChips.count == 2)
    }

    @Test("liveIconSymbol falls back to timer when chips are removed")
    func liveIconFallsBackToTimerOnRemoval() {
        let emptied = TimerActivityAttributes.ContentState(
            startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            categoryChips: []
        )
        #expect(emptied.liveIconSymbol == "timer")
    }

    @Test("liveIconSymbol ignores the Saved duration (stopped face unaffected)")
    func liveIconIgnoresSavedDuration() {
        let saved = TimerActivityAttributes.ContentState(
            startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            savedDurationSeconds: 600,
            categoryChips: [LiveCategoryChip(name: "Sport", iconSymbol: "dumbbell.fill")]
        )
        #expect(saved.liveIconSymbol == "dumbbell.fill")
        let savedEmpty = TimerActivityAttributes.ContentState(
            startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            savedDurationSeconds: 600
        )
        #expect(savedEmpty.liveIconSymbol == "timer")
    }
}
