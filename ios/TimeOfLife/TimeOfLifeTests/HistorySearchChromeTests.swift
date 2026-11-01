import Testing
import Foundation
@testable import TimeOfLife

/// Pins the on-device corrections for History search chrome
/// (`add-history-search` change, section 8): the no-results clear action
/// keeps the retired compact-timer slot as bottom keyboard clearance.
@Suite("HistorySearchChrome")
struct HistorySearchChromeTests {
    @Test("clear action keeps the retired compact-timer slot clearance")
    @MainActor
    func clearActionClearanceMatchesCompactTimer() {
        // The clearance composes the named surface with the theme gaps —
        // not an independent restatement of the formula — so production and
        // test cannot drift apart through duplicated literals.
        #expect(
            NoMatchingEntriesState.timerAbsentClearance
                == NoMatchingEntriesState.retiredCompactTimerSurface + Theme.spacingExtraSmall * 2
        )
        // The retired surface is pinned explicitly: 62pt, two 4pt gaps.
        #expect(NoMatchingEntriesState.retiredCompactTimerSurface == 62)
        #expect(NoMatchingEntriesState.timerAbsentClearance == 70)
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
