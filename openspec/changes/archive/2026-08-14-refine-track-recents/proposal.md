# Refine Track Recents

## Why

The Recents section on Track is under-informative (name-only chips, no
selected-state feedback, misleading empty copy) and its layout is broken on
small iPhones: on iPhone SE (1st generation, iOS 15) the suggestion row sits
partially under the tab bar in every non-idle state, and on large iPhones the
interactive controls cluster in the upper-middle of the screen while the
thumb-friendly bottom third is empty. This change refines Recents and gives
Track an adaptive two-ended layout whose flexible spacing collapses before
content clips on short screens or at larger accessibility text sizes.

## What Changes

- Track adopts a dual-flow top-to-bottom order: title, top adaptive spacing,
  completion mark, timer numbers, timer status, a reserved non-field-error
  region, a central separator, Activity search/refine, the state-specific
  main action, Recents, bottom adaptive spacing, then the tab bar. Placing
  the main action above Recents keeps Choose Activity / Start / Stop
  reachable without scrolling on short screens.
- The two adaptive spacing regions share one maximum height (48 pt, selected
  through four sequential iPhone 17 Pro Max spikes and validated on iPhone
  SE) and resolve to equal heights; surplus beyond twice the cap goes to the
  central separator between the error region and the search/refine flow.
  All three flexible regions shrink down to zero before content clips or
  overlaps, then the content scrolls.
- The main action remains in content above Recents and the bottom adaptive
  spacing and changes between Choose Activity, Start, and Stop without
  changing its frame: the layout reserves the preparation-row slot while
  idle, keeps Recents' occupied height while running (hidden but
  layout-preserving), renders the action in a fixed-height slot, and lets
  wrapped-error growth yield from the top spacer before the central
  separator, so the action's frame is identical in idle, ready, running,
  saving, saved, and error. The obsolete offline hint is removed because
  capture is local-first.
- The non-field error region stays above the central separator and reserves
  its space even when no error is visible; error text wraps fully (never
  cut) and may grow past the reservation, with the flexible spacing yielding
  first.
- The editing affordance (the former beside-picker Refine action) is
  **removed from Track**; its placement is deferred to a later change.
- Recents chips become a wrapping multiline flow (max 6, most-recently-used
  first) instead of a single horizontal scrolling row.
- Recents chips display the icon of the first assigned Category (by position);
  activities without Categories render without an icon.
- The prepared (selected) Activity's chip is highlighted with a filled accent
  presentation (accent background, on-accent text, accent border) — the same
  non-color-only treatment as TagSelector — and announced as selected to
  assistive technologies.
- The empty-Recents placeholder gets its own dedicated copy ("Activities you
  track will appear here") instead of reusing the search sheet's empty-catalog
  string.
- The selected-Activity row (picker/label) does **not** gain Category icons;
  search results remain category-free.

## Capabilities

### New Capabilities

<!-- none -->

### Modified Capabilities

- `timer-capture-experience`: Recents presentation (count cap, multiline flow,
  selected-state highlight, empty-state copy) and the primary action's
  placement within the adaptive two-ended Track layout.
- `category-management`: the "Category assignment SHALL NOT be shown in …
  recency suggestions" requirement is relaxed to allow the icon (not the name)
  of the first assigned Category on Recents chips only; search results and the
  selected-Activity row remain category-free.

## Impact

- `TrackView.swift` (dual-flow adaptive layout, central separator, reserved
  error region, recents flow, chip highlight, editing-affordance removal,
  offline-hint removal, state-invariant main-action frame: reserved idle
  preparation slot, hidden-but-reserved Recents while running, fixed-height
  action slot), `TrackViewModel.swift` (loads Categories to resolve chip
  icons; refresh after Refine save), a shared flow-layout component
  (`RecentActivitiesChips`) with the TagSelector packing algorithm for iOS 15
  compatibility, and an adaptive vertical layout container with a testable
  spacing model (D1 equal split on the state-invariant content, bottom flow
  pinned, top-flow growth yielding top spacer first then central separator —
  D10).
- `Design/SCREENS/TimeTracking.md`, `Design/DECISIONS.md`,
  `Design/COMPONENTS.md` (documented layout catches up with implementation and
  the category-icon-in-recents reversal).
- Localization: new key(s) in `en.lproj` and `ru.lproj` + `L10n` cases.
- No backend, OpenAPI, or persistence-schema changes; no new dependencies.

## Non-Goals

- Category names or icons in search results, the selected-Activity row, or
  elsewhere on Track.
- Reordering, pinning, or removing individual recents; changing the recency
  ranking (`last_used_at`).
- History/Insights, compact-timer, or other tabs.
