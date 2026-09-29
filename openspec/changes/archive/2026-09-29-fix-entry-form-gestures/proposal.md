## Why

Two gesture bugs in the unified entry form (`LogTimeView`, opened as a full-screen cover from History): the wheel time pickers steal the pull-down-to-scroll gesture (#51), and the edge back gesture does not work (#50). Agreed rule: native gestures are always correct — the layout must stop colliding with them.

## What Changes

- Reorder the form exactly as specified: Activity name → Start time → End time → Categories → Notes (today: Name → Categories → Notes → Starts/Ends). Pickers move up so scrolling with an open picker is rarely needed.
- Make **all** native gestures work in the form: pull-down-to-scroll, swipe-down-to-dismiss the cover, edge-back where a back stack exists, tap-away keyboard dismissal. No gesture is disabled or "fixed" to accommodate the layout.
- If the full-screen-cover presentation is what kills back-dismiss, change the presentation (e.g. navigation push or interactive dismiss) rather than patching the gesture.
- Non-goals: duration display (see `feat-entry-duration-subtitle`), name-field affordances (see `feat-name-field-affordances`).

## Capabilities

### New Capabilities

(none)

### Modified Capabilities

- `entry-editor`: entry-form field order and the all-native-gestures-must-work rule.
- `manual-entry`: CREATE mode shares the same form, so the order rule applies there too.

## Impact

- `ios/TimeOfLife/TimeOfLife/Features/ManualEntry/Views/LogTimeView.swift` (card order, picker/scroll interaction).
- `ios/TimeOfLife/TimeOfLife/Features/AppShell/Views/HistoryView.swift` (cover presentation).
- Manual gesture checklist on device (scroll, dismiss, back, keyboard) — no new deps, no ctx7 fetch needed (repo-internal SwiftUI).
