import Testing
import Foundation
@testable import TimeOfLife

@Suite("AdaptiveSpacing")
struct AdaptiveSpacingTests {

    @Test("negative slack yields zero spacing everywhere")
    func negativeSlack() {
        let spacing = AdaptiveSpacing(slack: -50, cap: 48)
        #expect(spacing.top == 0)
        #expect(spacing.bottom == 0)
        #expect(spacing.central == 0)
    }

    @Test("zero slack yields zero spacing everywhere")
    func zeroSlack() {
        let spacing = AdaptiveSpacing(slack: 0, cap: 48)
        #expect(spacing.top == 0)
        #expect(spacing.bottom == 0)
        #expect(spacing.central == 0)
    }

    @Test("slack below twice the cap splits evenly between top and bottom")
    func slackBelowDoubleCap() {
        let spacing = AdaptiveSpacing(slack: 60, cap: 48)
        #expect(spacing.top == 30)
        #expect(spacing.bottom == 30)
        #expect(spacing.central == 0)
    }

    @Test("slack equal to twice the cap saturates both spacers")
    func slackEqualDoubleCap() {
        let spacing = AdaptiveSpacing(slack: 96, cap: 48)
        #expect(spacing.top == 48)
        #expect(spacing.bottom == 48)
        #expect(spacing.central == 0)
    }

    @Test("slack above twice the cap spills the remainder into the central separator")
    func slackAboveDoubleCap() {
        let spacing = AdaptiveSpacing(slack: 300, cap: 48)
        #expect(spacing.top == 48)
        #expect(spacing.bottom == 48)
        #expect(spacing.central == 204)
    }

    @Test("odd slack splits evenly as fractional spacing")
    func oddSlackSplit() {
        let spacing = AdaptiveSpacing(slack: 5, cap: 48)
        #expect(abs(spacing.top - 2.5) < 0.0001)
        #expect(abs(spacing.bottom - 2.5) < 0.0001)
        #expect(spacing.central == 0)
    }

    // MARK: - D10 pinned distribution

    @Test("no top overflow keeps the D1 equal split exactly")
    func pinnedWithoutOverflow() {
        let baseline = AdaptiveSpacing(slack: 300, cap: 48)
        let pinned = AdaptiveSpacing.pinned(
            baseline: baseline,
            topOverflow: 0,
            slack: 300
        )
        #expect(pinned == baseline)
    }

    @Test("top spacer yields before the central separator")
    func pinnedYieldsTopFirst() {
        let baseline = AdaptiveSpacing(slack: 300, cap: 48)
        let pinned = AdaptiveSpacing.pinned(
            baseline: baseline,
            topOverflow: 30,
            slack: 270
        )
        #expect(pinned.top == 18)
        #expect(pinned.central == 204)
        #expect(pinned.bottom == 48)
    }

    @Test("central separator yields after the top spacer is exhausted")
    func pinnedYieldsCentralAfterTop() {
        let baseline = AdaptiveSpacing(slack: 300, cap: 48)
        let pinned = AdaptiveSpacing.pinned(
            baseline: baseline,
            topOverflow: 60,
            slack: 240
        )
        #expect(pinned.top == 0)
        #expect(pinned.central == 192)
        #expect(pinned.bottom == 48)
    }

    @Test("bottom spacer collapses once the space above the action is exhausted")
    func pinnedCollapsesBottomLast() {
        let baseline = AdaptiveSpacing(slack: 300, cap: 48)
        let pinned = AdaptiveSpacing.pinned(
            baseline: baseline,
            topOverflow: 300,
            slack: 0
        )
        #expect(pinned.top == 0)
        #expect(pinned.central == 0)
        #expect(pinned.bottom == 0)
    }

    @Test("pinned distribution never exceeds the actual slack")
    func pinnedFitsSlack() {
        for slack in stride(from: -40.0, through: 400.0, by: 20.0) {
            let baseline = AdaptiveSpacing(slack: slack + 120, cap: 48)
            let pinned = AdaptiveSpacing.pinned(
                baseline: baseline,
                topOverflow: 120,
                slack: slack
            )
            #expect(pinned.top + pinned.central + pinned.bottom <= max(0, slack) + 0.0001)
            #expect(pinned.top >= 0)
            #expect(pinned.central >= 0)
            #expect(pinned.bottom >= 0)
        }
    }
}
