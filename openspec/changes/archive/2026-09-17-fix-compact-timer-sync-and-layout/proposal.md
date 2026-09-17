## Why

Three user-reported defects break trust in the timer and the entry form: (1) stopping the timer from the compact timer on History leaves Track showing a running timer that never stops — the capture screen lies about reality; (2) expanding a time wheel picker in the entry form on a 320 pt screen (iPhone SE 1st gen, iOS 15) blows the form out to full-bleed with content clipped at the screen edges; (3) the compact timer sits 1–2 px over the tab bar instead of clearing it. All three are small, UI-only, and independently verifiable — one change with three task groups.

## What Changes

- **Track reconciles external stops**: `TrackViewModel.load()` — which today only ever transitions *into* `.running` — leaves `.running` when the persisted `timer_state` is gone (timer stopped from the compact timer on History/Insights): stops the elapsed ticker, re-enables the idle timer, and returns to `.ready` for the same activity (or `.idle` if the activity no longer exists), resetting elapsed to zero.
- **Entry form constrains inline pickers to card width**: the expanded graphical/wheel `DatePicker`s in `LogTimeView` no longer propose a width wider than the card on 320 pt screens — the form keeps its horizontal margins and nothing clips at the screen edges, in CREATE, EDIT, and LOCKED modes.
- **Compact timer clears the tab bar**: bottom spacing is added inside the `.safeAreaInset(edge: .bottom)` container so the surface floats above the tab bar instead of overlapping it by 1–2 px, on History and Insights alike.

Non-goals: no timer-state model changes (the `timer_state` singleton and `TimerService` API are untouched — this is view-model reconciliation, not a sync/persistence fix); no LogTime visual redesign (same Calendar grammar, same pickers, only width constraint); no new strings (reuse existing copy; no `L10n` additions); no backend or OpenAPI changes.

## Capabilities

### New Capabilities
(none — all three fixes tighten existing behavior)

### Modified Capabilities
- `app-shell`: "Stop outside Track" gains Track-side reconciliation visibility (returning to Track after a compact stop shows the settled state, not a ghost running timer); the compact timer placement gains a no-overlap rule above the tab bar.
- `timer-capture-experience`: the Track running state reflects external stops — a `.running` Track with no persisted timer reconciles instead of counting forever.
- `entry-editor`: the unified entry form keeps its card margins with an expanded inline picker on 320 pt screens (no edge-to-edge bleed, no clipped content).

## Impact

- iOS only: `TrackViewModel.load()` (+ tests), `LogTimeView` picker containment (+ layout verification), `CompactTimer`/`AppShellView` bottom spacing. No store, sync, outbox, timer-service, or History/Insights data changes.
- Verification needs a 320 pt simulator (iPhone SE 1st gen class) pass for the picker fix and a cross-tab stop→return-to-Track pass for the desync fix; both are expressible as view-model unit tests plus manual simulator checks (no snapshot tests in repo).
