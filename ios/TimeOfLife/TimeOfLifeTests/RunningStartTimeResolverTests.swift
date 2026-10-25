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

    @Test("future picked times fold to yesterday, preserving the wall time")
    func resolveFutureFoldsToYesterday() {
        var comps = DateComponents()
        comps.year = 2026; comps.month = 10; comps.day = 25
        comps.hour = 14; comps.minute = 20
        let now = calendar.date(from: comps)!
        let picked = now.addingTimeInterval(60)

        let resolved = RunningStartTimeResolver.resolve(picked: picked, now: now, calendar: calendar)

        #expect(resolved <= now)
        #expect(!calendar.isDate(resolved, inSameDayAs: now))
        #expect(calendar.component(.hour, from: resolved) == 14)
        #expect(calendar.component(.minute, from: resolved) == 21)
        #expect(calendar.component(.second, from: resolved) == 0)
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
        let format = L10n.timerStartedAt.text
        #expect(format.contains("%@"))
        #expect(caption == format.replacingOccurrences(of: "%@", with: "T"))
    }

    @Test("caption uses the yesterday form for prior-day starts")
    func captionYesterdayForm() {
        let now = Date()
        let yesterday = calendar.date(byAdding: .day, value: -1, to: now)!
        let caption = RunningStartTimeResolver.caption(
            for: yesterday, now: now, calendar: calendar, timeText: timeText
        )
        let format = L10n.timerStartedYesterday.text
        #expect(format.contains("%@"))
        #expect(caption == format.replacingOccurrences(of: "%@", with: "T"))
    }

    @Test("resolveForDay rebuilds Today picks on today's date")
    func resolveForDayRebuildsToday() {
        var comps = DateComponents()
        comps.year = 2026; comps.month = 10; comps.day = 25
        comps.hour = 14; comps.minute = 20
        let now = calendar.date(from: comps)!
        // An overnight draft (yesterday 08:00) with the Today segment: the
        // wheel shows 08:00, and the applied start must be today 08:00 — a
        // resolver that took the wall time from `now` (14:20) or ignored the
        // pick would fail these.
        var pickedComps = comps
        pickedComps.day = 24
        pickedComps.hour = 8
        pickedComps.minute = 0
        let picked = calendar.date(from: pickedComps)!

        let resolved = RunningStartTimeResolver.resolveForDay(
            picked: picked, yesterday: false, now: now, calendar: calendar
        )

        #expect(resolved != nil)
        #expect(calendar.isDate(resolved!, inSameDayAs: now))
        #expect(calendar.component(.hour, from: resolved!) == 8)
        #expect(calendar.component(.minute, from: resolved!) == 0)
    }

    @Test("resolveForDay rejects future Today picks")
    func resolveForDayRejectsFutureToday() {
        var comps = DateComponents()
        comps.year = 2026; comps.month = 10; comps.day = 25
        comps.hour = 14; comps.minute = 20
        let now = calendar.date(from: comps)!

        let resolved = RunningStartTimeResolver.resolveForDay(
            picked: now.addingTimeInterval(3_600), yesterday: false, now: now, calendar: calendar
        )

        #expect(resolved == nil)
    }

    @Test("resolveForDay always resolves Yesterday picks")
    func resolveForDayResolvesYesterday() {
        var comps = DateComponents()
        comps.year = 2026; comps.month = 10; comps.day = 25
        comps.hour = 14; comps.minute = 20
        let now = calendar.date(from: comps)!
        // A picked wall time differing from now's proves the result carries
        // the pick, not the clock.
        var pickedComps = comps
        pickedComps.hour = 8
        pickedComps.minute = 5
        let picked = calendar.date(from: pickedComps)!

        let resolved = RunningStartTimeResolver.resolveForDay(
            picked: picked, yesterday: true, now: now, calendar: calendar
        )

        #expect(resolved != nil)
        #expect(resolved! <= now)
        #expect(!calendar.isDate(resolved!, inSameDayAs: now))
        #expect(calendar.component(.hour, from: resolved!) == 8)
        #expect(calendar.component(.minute, from: resolved!) == 5)
    }
}
