import SwiftUI

/// Deterministic spacing budget for the adaptive dual-flow Track layout
/// (refine-track-recents D1). The layout has three flexible regions: a top
/// spacer between the navigation title and the completion mark, a bottom
/// spacer between the main action and the tab bar (each capped at the shared
/// maximum), and an unbounded central separator between the error region and
/// the Activity search/refine row.
///
/// Four regimes, derived from `slack = viewportHeight - contentHeight`:
/// 1. `slack <= 0` — no adaptive spacing at all; the ordered content scrolls.
/// 2. `0 < slack <= 2 * cap` — slack is split evenly between the top and
///    bottom spacers; the central separator is zero; content is centered.
/// 3. `slack > 2 * cap` — both spacers hold at the shared cap and the
///    remaining slack goes to the central separator between the top flow
///    (title…error) and the bottom flow (search…main action).
struct AdaptiveSpacing: Equatable {
    let top: CGFloat
    let central: CGFloat
    let bottom: CGFloat

    init(top: CGFloat, central: CGFloat, bottom: CGFloat) {
        self.top = top
        self.central = central
        self.bottom = bottom
    }

    init(slack: CGFloat, cap: CGFloat) {
        let available = max(0, slack)
        let end = min(cap, available / 2)
        self.top = end
        self.bottom = end
        self.central = max(0, available - 2 * end)
    }

    /// The D10 pinned distribution: the bottom flow (search/refine → main
    /// action → Recents) holds its frame while growth of the top flow (a
    /// wrapped error) compresses the top spacer first, then the central
    /// separator — both sit above the main action, so it stays stationary.
    /// `baseline` is the D1 equal-split result for the state-invariant
    /// content (top overflow removed); `topOverflow` is the top flow's
    /// growth beyond that baseline; `slack` is the actual remaining space.
    /// When the growth exhausts both regions above the main action, the
    /// bottom spacer also collapses and the ordered content scrolls.
    static func pinned(
        baseline: AdaptiveSpacing,
        topOverflow: CGFloat,
        slack: CGFloat
    ) -> AdaptiveSpacing {
        let top = max(0, baseline.top - topOverflow)
        let remaining = max(0, topOverflow - baseline.top)
        let central = max(0, baseline.central - remaining)
        let bottom = min(baseline.bottom, max(0, slack - top - central))
        return AdaptiveSpacing(top: top, central: central, bottom: bottom)
    }
}

/// Wraps a dual-flow vertical stack in adaptive spacing (D1): the top flow
/// (completion mark…error region) and the bottom flow (search/refine…main
/// action) are measured separately, and the three flexible regions resolve
/// deterministically from the remaining space without relying on `Spacer`
/// flexibility (which cannot be capped).
///
/// D10: `topOverflow` carries the top flow's growth beyond its
/// state-invariant baseline (a wrapped error past the reserved region
/// height). The spacing model then computes the D1 equal split for the
/// baseline content and pins the bottom flow: the overflow compresses the
/// top spacer first, then the central separator, and the bottom spacer
/// collapses only when both are exhausted (the content scrolls).
struct AdaptiveVerticalLayout<TopContent: View, BottomContent: View>: View {
    /// The shared maximum height for the top and bottom spacers.
    let spacerCap: CGFloat
    /// The top flow's growth beyond its baseline height (wrapped error);
    /// zero keeps the pure D1 equal-split behavior.
    let topOverflow: CGFloat
    let topContent: TopContent
    let bottomContent: BottomContent

    @State private var viewportHeight: CGFloat = 0
    @State private var topContentHeight: CGFloat = 0
    @State private var bottomContentHeight: CGFloat = 0

    init(
        spacerCap: CGFloat,
        topOverflow: CGFloat = 0,
        @ViewBuilder topContent: () -> TopContent,
        @ViewBuilder bottomContent: () -> BottomContent
    ) {
        self.spacerCap = spacerCap
        self.topOverflow = topOverflow
        self.topContent = topContent()
        self.bottomContent = bottomContent()
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                Color.clear.frame(height: spacing.top)
                topContent
                    .background(
                        GeometryReader { geometry in
                            Color.clear.preference(
                                key: AdaptiveTopContentHeightKey.self,
                                value: geometry.size.height
                            )
                        }
                    )
                Color.clear.frame(height: spacing.central)
                bottomContent
                    .background(
                        GeometryReader { geometry in
                            Color.clear.preference(
                                key: AdaptiveBottomContentHeightKey.self,
                                value: geometry.size.height
                            )
                        }
                    )
                Color.clear.frame(height: spacing.bottom)
            }
        }
        .background(
            GeometryReader { geometry in
                Color.clear.preference(
                    key: AdaptiveViewportHeightKey.self,
                    value: geometry.size.height
                )
            }
        )
        .onPreferenceChange(AdaptiveViewportHeightKey.self) { viewportHeight = $0 }
        .onPreferenceChange(AdaptiveTopContentHeightKey.self) { topContentHeight = $0 }
        .onPreferenceChange(AdaptiveBottomContentHeightKey.self) { bottomContentHeight = $0 }
    }

    private var spacing: AdaptiveSpacing {
        let slack = viewportHeight - topContentHeight - bottomContentHeight
        let baseline = AdaptiveSpacing(slack: slack + topOverflow, cap: spacerCap)
        return AdaptiveSpacing.pinned(
            baseline: baseline,
            topOverflow: topOverflow,
            slack: slack
        )
    }
}

private struct AdaptiveTopContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct AdaptiveBottomContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct AdaptiveViewportHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
