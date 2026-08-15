import Testing
import Foundation
import SwiftUI
@testable import TimeOfLife

@Suite("MainActionSlot")
struct MainActionSlotTests {

    @Test("slot is never below the primary button minimum")
    func slotAtLeastButtonMinimum() {
        let height = MainActionSlot.height(
            titles: ["Start", "Stop"],
            width: 372,
            at: .large
        )
        #expect(height >= PrimaryButton.minHeight)
    }

    @Test("slot is a single value for the whole title set")
    func slotIsOneValueForAllStates() {
        let titles = [L10n.timerChooseActivity.text, L10n.timerStart.text, L10n.timerStop.text]
        let a = MainActionSlot.height(titles: titles, width: 372, at: .large)
        let b = MainActionSlot.height(titles: titles, width: 372, at: .large)
        #expect(a == b)
    }

    @Test("slot never shrinks as the width shrinks (upper bound)")
    func slotIsUpperBoundAcrossWidths() {
        let titles = [L10n.timerChooseActivity.text, L10n.timerStart.text, L10n.timerStop.text]
        let wide = MainActionSlot.height(titles: titles, width: 372, at: .accessibility5)
        let narrow = MainActionSlot.height(titles: titles, width: 272, at: .accessibility5)
        #expect(narrow >= wide)
        #expect(narrow >= PrimaryButton.minHeight)
    }

    @Test("accessibility sizes never shrink the slot below the default")
    func accessibilitySlotNeverShrinks() {
        let titles = [L10n.timerChooseActivity.text, L10n.timerStart.text, L10n.timerStop.text]
        let large = MainActionSlot.height(titles: titles, width: 372, at: .large)
        let accessibility5 = MainActionSlot.height(titles: titles, width: 372, at: .accessibility5)
        #expect(accessibility5 >= large)
    }

    @Test("zero width falls back to the content width")
    func zeroWidthFallback() {
        let height = MainActionSlot.height(
            titles: [L10n.timerChooseActivity.text],
            width: 0,
            at: .large
        )
        #expect(height >= PrimaryButton.minHeight)
    }
}
