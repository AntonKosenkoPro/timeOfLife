import Testing
import Foundation
@testable import TimeOfLife

/// Pure-rule tests for the running-start editor: every picked time resolves
/// through these rules, so the midnight rule, the minute floor, and the
/// caption copy are pinned once, here.
@Suite("RunningStartTimeResolver")
struct RunningStartTimeResolverTests {
    private var calendar: Calendar { Calendar(identifier: .gregorian) }
    private func timeText(_ date: Date) -> String { "T" }

    @Test("picked times at or before now resolve floored to the minute")
    func resolveFloorsToMinute() {
        var comps = DateComponents()
        comps.year = 2026; comps.month = 10; comps.day = 25
        comps.hour = 14; comps.minute = 20; comps.second = 45
        let picked = calendar.date(from: comps)!
        let now = picked.addingTimeInterval(60)

        let resolved = RunningStartTimeResolver.resolve(picked: picked, now: now, calendar: calendar)

        #expect(calendar.component(.second, from: resolved) == 0)
        #expect(calendar.component(.minute, from: resolved) == 20)
        #expect(resolved <= now)
    }

    @Test("future picked times fold to yesterday")
    func resolveFutureFoldsToYesterday() {
        var comps = DateComponents()
        comps.year = 2026; comps.month = 10; comps.day = 25
        comps.hour = 14; comps.minute = 20
        let now = calendar.date(from: comps)!
        let picked = now.addingTimeInterval(60)

        let resolved = RunningStartTimeResolver.resolve(picked: picked, now: now, calendar: calendar)

        #expect(resolved <= now)
        #expect(!calendar.isDate(resolved, inSameDayAs: now))
    }

    @Test("same-day starts are not yesterday")
    func sameDayIsNotYesterday() {
        let now = Date()
        #expect(!RunningStartTimeResolver.isYesterday(now, now: now, calendar: calendar))
        let yesterday = calendar.date(byAdding: .day, value: -1, to: now)!
        #expect(RunningStartTimeResolver.isYesterday(yesterday, now: now, calendar: calendar))
    }

    @Test("caption uses the today form for same-day starts")
    func captionTodayForm() {
        let now = Date()
        let caption = RunningStartTimeResolver.caption(
            for: now, now: now, calendar: calendar, timeText: timeText
        )
        #expect(caption == String(format: L10n.timerStartedAt.text, locale: .current, "T"))
    }

    @Test("caption uses the yesterday form for prior-day starts")
    func captionYesterdayForm() {
        let now = Date()
        let yesterday = calendar.date(byAdding: .day, value: -1, to: now)!
        let caption = RunningStartTimeResolver.caption(
            for: yesterday, now: now, calendar: calendar, timeText: timeText
        )
        #expect(caption == String(format: L10n.timerStartedYesterday.text, locale: .current, "T"))
    }
}
