import Testing
import Foundation
@testable import TimeOfLife

/// Pins the on-device corrections for History search chrome
/// (`add-history-search` change, section 8): the no-results clear action
/// keeps compact-timer-equivalent bottom keyboard clearance with and
/// without a running timer.
@Suite("HistorySearchChrome")
struct HistorySearchChromeTests {
    @Test("clear action reserves the compact-timer slot only when the timer is absent")
    @MainActor
    func clearActionClearanceMatchesCompactTimer() {
        #expect(NoMatchingEntriesState.bottomClearance(hasCompactTimer: true) == 0)
        #expect(
            NoMatchingEntriesState.bottomClearance(hasCompactTimer: false)
                == NoMatchingEntriesState.timerAbsentClearance
        )
        // Floor: the reserved slot covers at least the retired compact-timer
        // surface (62pt; remove-compact-timer deleted the view).
        #expect(NoMatchingEntriesState.timerAbsentClearance >= 62)
    }

    @Test("blank queries keep the tab bar, including a focused-but-empty field")
    func blankQueryKeepsTabBar() {
        #expect(HistoryViewModel.hidesTabBar(for: "") == false)
        #expect(HistoryViewModel.hidesTabBar(for: "   ") == false)
        #expect(HistoryViewModel.hidesTabBar(for: " \n\t ") == false)
    }

    @Test("any non-blank query hides the tab bar: results, no-matches, and diagnostics alike")
    func nonBlankQueryHidesTabBar() {
        #expect(HistoryViewModel.hidesTabBar(for: "gym") == true)
        #expect(HistoryViewModel.hidesTabBar(for: "  gym  ") == true)
        // Syntax-diagnostic states hide the bar too: visibility follows
        // blank vs non-blank text, not validity.
        #expect(HistoryViewModel.hidesTabBar(for: "in:") == true)
        #expect(HistoryViewModel.hidesTabBar(for: "started:2026-02-30") == true)
        #expect(HistoryViewModel.hidesTabBar(for: "started:2026-10-01") == true)
        #expect(HistoryViewModel.hidesTabBar(for: "g") == true)
    }
}
