## Why

User testing of `history-entry-list` rejected the collapsing nav bar (D9): it does not trigger reliably (misses some scrolls because thresholds only evaluate during an active drag) and it snaps without animation, so the chrome change feels broken rather than intentional. The nav-bar collapse adds ongoing risk (it required a UIKit KVO tracker to work around SwiftUI scroll-tracking limitations, and its hide/show cycle re-bases scroll geometry) for little gain — the list gains ~57 pt only while the bar is away, and Profile is reachable at rest either way.

## What Changes

- Remove the scroll-driven collapsing nav bar from History: the navigation bar (inline "History" title + Profile button) stays visible on History at all times.
- Remove the `ScrollViewTracker` UIKit KVO machinery, the drag-distance thresholds, `isScrolledToTop` state, and the `.navigationBarHidden(...)` wiring — the tracker existed solely to drive the collapse.
- Keep the elevation-gated day-group header total (D8) unchanged: pinned headers still show "Xs tracked" while scrolled. This does not depend on the nav-bar collapse.
- **BREAKING** (spec-level only): the `history-entry-list` requirement "History preserves compact timer access and uses a collapsing nav bar" loses its collapse behavior; compact-timer and at-rest nav bar requirements are unchanged.

## Capabilities

### New Capabilities

(none)

### Modified Capabilities

- `history-entry-list`: the "History preserves compact timer access and uses a collapsing nav bar" requirement is modified to keep the navigation bar permanently visible (compact timer + at-rest chrome unchanged; collapse scenarios removed).

## Impact

- `ios/TimeOfLife/TimeOfLife/Features/AppShell/Views/HistoryView.swift` — delete `ScrollViewTracker`/`TrackerView`, `isScrolledToTop`, collapse/restore thresholds, `.navigationBarHidden(!isScrolledToTop)`; simplify the tracker doc comments that justified the KVO approach.
- Baseline spec `openspec/specs/history-entry-list/spec.md` — collapse scenarios fold out on archive.
- Design docs `Design/SCREENS/History.md`, `Design/README.md`, `docs/project-context.md` — drop the D9 collapse mention from the History screen description.
- No backend, no store, no L10n changes. The `history-entry-list` change (`openspec/changes/history-entry-list/`) remains the vehicle that introduced the list; this change supersedes its D9 decision.

## Non-goals

- No re-implementation of the collapse with animation (a future change may revisit scroll-aware chrome using system-driven behaviors).
- No changes to Track/Insights chrome, the compact timer, or the D8 elevated header total.