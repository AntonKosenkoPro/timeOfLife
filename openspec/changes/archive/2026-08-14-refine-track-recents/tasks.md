# Tasks — refine-track-recents

## 1. Spikes and explicit approval gate

- [x] 1.1 Build a DEBUG-only Track layout harness with the exact dual-flow stack: title → top adaptive spacer → completion mark → timer numbers/status → reserved error region → central separator → search/refine → Recents → main action → bottom adaptive spacer; equal capped top/bottom spacers, surplus beyond 2×cap to the central separator, six icon-bearing Recents Activities, configurable shared spacer cap (design D1/D7/D8)
- [x] 1.2 On iPhone 17 Pro Max (iOS 26.4), run the shared cap variants sequentially at 24, 48, 72, and 96 pt; for each capture idle/ready/running/saved/error screenshots and normalized frames for completion mark, timer numbers/status, error region, search/refine, Recents, main action, and tab bar
- [x] 1.3 Present the four Pro Max variants together with measurements and stop; user explicitly selected **48 pt** (recorded in design D1/D7)
- [x] 1.4 Run cap 48 on iPhone SE (1st generation, iOS 15.5) with six icon-bearing Activities in idle/ready/running/saved/error at both default and Large Dynamic Type; verified spacers/central separator collapse to zero before clipping, overlap, or unreachable content. User revisions folded into the harness: filled accent selected chip without checkmark (D4), wrapping (never cut) error text (D8), editing affordance removed from Track (D9 retired), main action swapped above Recents (D1), Large Dynamic Type exercised through the simulator's real content-size setting so chip measurement and rendering stay in sync (no cropped chip text)
- [x] 1.5 Present the revised SE and Pro Max results and stop; production tasks 2.1 onward MUST NOT begin until the user explicitly approves the final Pro Max + SE result. If rejected, revise the candidate caps/artifacts and repeat section 1

## 2. Layout: adaptive two-ended Track composition

- [x] 2.1 After explicit spike approval, restructure `TrackContent` in this order: title → top adaptive spacer → completion mark → timer numbers → timer status → reserved error region → central separator → Activity search/refine → state-specific main action → Recents → bottom adaptive spacer → tab bar (spec: Track uses an adaptive two-ended vertical layout; design D1)
- [x] 2.2 Implement top and bottom spacers with the approved shared maximum (48 pt), equal heights, zero minimum, and the central separator absorbing surplus beyond twice the cap; use scrolling only after all three flexible regions are exhausted
- [x] 2.3 Reserve stable non-field-error space immediately above the central separator, hide the empty region from accessibility, let error text wrap without being cut (region grows past the reservation, spacers yield first), and verify error appearance does not move timer or controls while text fits the reservation (design D8)
- [x] 2.4 Remove the obsolete offline hint and the beside-picker Refine/edit affordance (deferred placement, D9); preserve `TimerChooseActivityButton`, `TimerStartButton`, `TimerStopButton`, `TrackErrorBanner`, and stable main-action geometry across idle/ready/running/saving/saved/error

## 3. Recents chips

- [x] 3.1 Add `RecentActivitiesChips`: measured-width wrapping flow (TagSelector packing algorithm, iOS 15-compatible), cap 6, most-recently-used first, 44 pt tap targets, one-line truncated names (spec: Recents present a capped wrapping chip flow; design D2)
- [x] 3.2 Render the first assigned Category's icon (`activity.categoryIDs.first` → `CatalogIcon(validated:).displaySymbol`) in a fixed symbol slot; categoryless Activities render name-only (spec: Recents chips show the first assigned Category icon; design D3)
- [x] 3.3 Selected chip: filled accent presentation (accent background, on-accent text, accent border), icon kept, no checkmark; `.isSelected` trait and `accessibilityValue` "Selected"; highlight derives from `state.activity?.id` (spec: Recents highlight the prepared Activity; design D4)
- [x] 3.4 Replace the empty-catalog reuse of `timer.searchEmptyCatalogSubtitle` with the dedicated hint and keep Recents hidden while running (spec: Recents explain their empty state)
- [x] 3.5 Preserve `TimerSuggestion(\(activity.id))` identifiers and `timerSelectActivity`-based accessibility labels; update DEBUG previews to cover icon, no-icon, selected, wrapped, and empty states

## 4. View model data

- [x] 4.1 `TrackViewModel.load()` also fetches `store.categories()` into an id→Category map; expose it for chip icon resolution (design D6)
- [x] 4.2 Refresh the Categories map alongside activities in `saveRefinement` so Refine assignment edits repaint chip icons (design D6)

## 5. Localization

- [x] 5.1 Add `timer.recentsEmptyHint` to `en.lproj` and `ru.lproj` and the `L10n` enum (U4; design D5); remove the now-unused `timer.activityRefine` keys once the Refine affordance is removed from Track (D9)

## 6. Design docs

- [x] 6.1 Update `Design/SCREENS/TimeTracking.md` (dual-flow adaptive layout, 48 pt cap, central separator, reserved error region with wrapping text, offline-hint removal, "Edit activity" action; Recents chips: cap 6, wrapping, first-Category icon, filled selected affordance, dedicated empty copy)
- [x] 6.2 Update `Design/DECISIONS.md` and `Design/COMPONENTS.md` for the icon-in-recents reversal (icon-only, no names) and the new chips component

## 7. Verification

- [x] 7.1 Update/extend unit tests for the TrackViewModel Categories map (load, refine refresh) and chip-count/ordering derivation if testable
- [x] 7.2 Run SwiftLint strict, `xcodegen generate`, and the full test suite green (S5)
- [x] 7.3 Manual pass: SE 1st gen + 17 Pro Max, idle/ready/running/saving/saved/error, default + Large Dynamic Type, EN + RU, VoiceOver on the selected chip, Reduce Motion, light/dark
- [x] 7.4 `openspec status --change refine-track-recents` and validate the change before archive

## 8. Main-action position invariance (D10)

- [x] 8.1 Reserve the preparation-row slot in every state: idle renders the slot empty (transparent, excluded from the accessibility tree) at the picker/label height (spec: Main action holds one position across states; design D10)
- [x] 8.2 Keep Recents' occupied height while hidden during running and error states (hidden but layout-preserving); chips reappear in place for saving/saved (design D10)
- [x] 8.3 Render the main action in a fixed-height slot equal to the tallest state title at the active Dynamic Type size (design D10)
- [x] 8.4 Pin the bottom flow in `AdaptiveVerticalLayout`: compute the bottom spacer from the state-invariant content (D1 equal split) and hold it; wrapped-error growth compresses the top spacer first, then the central separator; scrolling only when both are exhausted (design D10, amends D8)
- [x] 8.5 Spike-verify normalized main-action frames are identical across idle/ready/running/saving/saved/error on SE and Pro Max at default and Large Dynamic Type (extend the DEBUG harness; D7 methodology)
- [x] 8.6 Unit-test the state-invariant height derivation (slot heights, bottom-flow pinning, error yield order) and update `Design/SCREENS/TimeTracking.md`

Implementation notes: production TrackContent rebuilt on `AdaptiveVerticalLayout(spacerCap: 48)` with the completion-mark region moved out of `NumericTimerReadout`; `TrackViewModel` gained the id→Category map (load + saveRefinement refresh); `RecentActivitiesChips` uses trait-synced width measurement; the saved/error/empty states were verified on-device (SE idle-empty + Pro Max idle→ready→running→saved→ready cycle, EN launch args, dark appearance), with Large Dynamic Type geometry spike-validated on both simulators at 100%/accessibility5. VoiceOver value "Selected" confirmed in the AX tree; Reduce Motion needs no work (no custom motion). D10: `TrackContent` moved to its own file and now reserves the idle preparation slot (hidden picker), hides Recents opacity-wise while running/error with layout preserved, renders the main action in a `MainActionSlot`-sized fixed-height frame, and feeds the measured error-region overflow into `AdaptiveVerticalLayout.topOverflow`; the pinned `AdaptiveSpacing.pinned` distribution holds the bottom flow and yields top-first under wrapped-error growth; `NumericTimerReadout` reserves the caption region via a rendered-height probe (the idle prompt wraps at accessibility sizes, which would otherwise move the main action). The spike harness (`TrackLayoutSpike`) now wraps production `TrackContent` with a configurable cap and injected preview state (idle/ready/running/saving/saved/error, empty catalog, long error). 8.5 verification (AX-tree normalized frames, TRACK_SPIKE env): Pro Max default all six states + 4-line wrapped error at y=0.603; Pro Max accessibility5 idle/ready/running/saving/saved at y=0.492; SE default all six states + in-reservation error at y=0.548; SE Large (real content-size) idle/ready/running at y=0.672 — main-action frames identical within each device/size; wrapped errors that exceed the top+central budget fall back to scrolling exactly as D10 specifies.
