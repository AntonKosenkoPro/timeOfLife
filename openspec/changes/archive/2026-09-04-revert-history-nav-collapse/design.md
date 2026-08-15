## Context

`history-entry-list` shipped the D9 collapsing nav bar driven by a hidden `ScrollViewTracker` (UIViewRepresentable) that KVO-observes the underlying `UIScrollView.contentOffset` from the window, because SwiftUI preference probes do not re-fire during scroll on the current SwiftUI/iOS 26.4 runtime. User testing found the behavior unreliable (collapse only evaluates during an active drag, so inertial scrolls that pass the threshold before tracking ends — or end short of it — miss) and jarring (the hide/show is instantaneous, no animation), and the hide/show cycle re-bases the scroll view's geometry (contentOffset.y and adjustedContentInset.top both shift by the bar height), which is the hazard the drag-distance metric was built to avoid. D8 (elevated header total) is independent: it is driven by `HeaderFramePreferenceKey` from the pinned headers and works with the bar always visible.

## Goals / Non-Goals

**Goals:**
- History's navigation bar (inline title + Profile button) is permanently visible at every scroll position.
- Remove the scroll-tracking machinery built solely for the collapse (`ScrollViewTracker`/`TrackerView`, `isScrolledToTop`, thresholds, `.navigationBarHidden` wiring) — no dead code remains.
- Keep D8 elevated header totals and the compact timer exactly as they are.

**Non-Goals:**
- No re-implementation of scroll-aware chrome (a future change may use a system-driven collapsing behavior instead of a state-flip on `.navigationBarHidden`).
- No changes to `HistoryViewModel`, `LocalStore`, L10n, or any other screen.

## Decisions

- **D1: Full revert of the D9 mechanism, not a polish pass.** Making the collapse reliable + animated would mean either animating the `.navigationBarHidden` flip (known to fight `NavigationView` on this runtime: the state flip detaches/reattaches the destination, firing lifecycle modifiers) or moving to UIKit-delegate-driven bar transitions — significant machinery for a behavior the user has already rejected once. Reverting returns History to the same chrome model as Track/Insights (persistent `navigationRoot` bar from `AppShellView`), which is the baseline the app-shell spec already describes. *Alternative considered*: keep the tracker and animate the bar transition — rejected; effort/risk outweighs the ~57 pt of extra list height, and the user asked for the revert.
- **D2: D8 stays untouched.** The elevated total is computed from pinned-header frames (`HeaderFramePreferenceKey`), independent of nav-bar visibility; reverting D9 neither breaks it nor needs its thresholds retuned. Its "elevated at rest" quirk (total visible at the top of the list) is pre-existing accepted behavior from user testing of `history-entry-list`.
- **D3: The tracker's drag-distance insight is recorded, not kept in code.** The geometry re-basing hazard (bar hide shifts contentOffset and adjustedContentInset together) is documented here so any future scroll-aware-chrome change starts from the working approach instead of rediscovering the feedback loop.

## Risks / Trade-offs

- [List loses ~57 pt of vertical space while scrolled compared to the collapsed state] → Accepted; consistency with the other tabs and a reliable, animated-feeling (no) chrome beat the extra height. The list is short for v1 data sizes.
- [`HistoryView` doc comments reference the tracker's rationale] → Remove/rewrite the comments with the code so no stale justifications remain.
- [`Design/` docs and `docs/project-context.md` describe the collapsing bar] → Update them in the same change so docs match behavior.

## Migration Plan

Single PR: delete the tracker + state from `HistoryView.swift`, update the delta spec, docs, and the `history-entry-list` change's design note if it references D9 behavior as current. Rollback = revert the PR; no data, schema, or API involvement.

## Open Questions

(none)