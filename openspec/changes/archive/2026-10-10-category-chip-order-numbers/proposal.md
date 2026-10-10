## Why

Category selection order is semantically meaningful — entries persist an ordered category set (first position supplies chip/row icons, sync preserves order) — but the `TagSelector` UI shows only an unordered checkmark per selected chip. Users who pick 2+ categories cannot see or verify the order they just defined. Showing the selection ordinal directly on each chip closes that feedback gap at the point of decision.

## What Changes

- `TagSelector` renders the 1-based selection ordinal (1, 2, 3, …) in place of the `checkmark` on every selected chip whenever **more than one** chip is selected; a single selected chip keeps the existing `checkmark` presentation.
- Deselecting any chip renumbers the remaining selected chips to the dense sequence 1…n preserving the parent-owned tap order (deselect-then-reselect appends at the end).
- Ordinal changes (select / deselect / renumber / checkmark↔number swap) animate with a fade.
- **BREAKING**: `TagSelector`'s `selected: Set<String>` input becomes an order-aware input (ordered ids); both call sites (Track running selector, entry-form categories row) pass their already-ordered arrays directly.
- Ordinals cap at 99 (3-digit selection is impossible); two-digit ordinals shrink their glyph to fit the existing fixed symbol slot so `FlowLayout` rows never re-pack.
- VoiceOver announces the ordinal position of selected chips (new localized strings, EN + RU).

## Capabilities

### New Capabilities

(none — this change refines existing behavior, no new capability.)

### Modified Capabilities

- `category-management`: chip rendering rule changes — single selection shows `checkmark`, multi-selection shows ordinals; selection-state announcement includes position.
- `timer-capture-experience`: the running timer's `TagSelector` section inherits the ordinal rendering (shared component, no separate requirement, but the delta notes the running-selector scope).

## Impact

- Affected code: `ios/TimeOfLife/TimeOfLife/Core/Design/Components/TagSelector.swift` (rendering + input shape); call sites `Features/TimeTracking/Views/TrackContent.swift` (running selector) and `Features/ManualEntry/Views/LogTimeView.swift` (categories card); `Localization/en.lproj` + `ru.lproj` and `String+Localized.swift`/`L10n` (ordinal announcement strings); `Design/COMPONENTS.md` TagSelector block (docs sync).
- No backend / OpenAPI / sync / persistence impact: order is already stored, synced, and owned by the parents (`LogTimeViewModel.categoryIDs`, `TrackViewModel` draft `categoryIDs`); toggle semantics (append-on-select, remove-on-deselect) are unchanged.
- No new dependencies. iOS 18+ pin unchanged; SwiftUI fade via standard opacity transitions.

### Non-goals

- Recents chips (`RecentActivitiesChips`) are out of scope — they keep icon + fill with no checkmark, unchanged.
- No reordering gesture (drag-to-reorder); order is defined purely by tap sequence.
- No change to toggle/persistence/sync semantics, no change to chip layout metrics (padding, capsule, 44 pt target, `FlowLayout` packing).
- Deferred surfaces (UndoToast/shake-to-undo, "via \<Source\>" labels, lock-screen widget) are untouched.
