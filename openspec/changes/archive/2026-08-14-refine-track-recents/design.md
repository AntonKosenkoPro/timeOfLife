# Design — refine-track-recents

## Context

See `proposal.md` — Why. Constraints that shape this design:

- iOS 15 deployment target; the SE 1st-gen overlap was reproduced on iOS 15.5
  (suggestion chip bottom y=0.934 vs tab bar top y=0.915 in the ready state).
  The `Layout` protocol (flow layout) is iOS 16+, so chip packing must use the
  measured-width approach already proven in `TagSelector` (category-management
  D9, iOS-15-compatible).
- The current Track stack does not distribute spare height intentionally. Its
  fixed spacing produces overlap on SE and leaves the thumb-friendly lower
  region unused on Pro Max. The revised design uses two adaptive spacers with
  one shared, spike-selected maximum.
- The baseline `category-management` spec forbids Category metadata in
  "recency suggestions" (redesign D3/D9: categories "should not compete with
  the concrete task"). This change deliberately relaxes that for an icon-only
  treatment on Recents chips; the delta spec carries the reversal.
- `LocalStore.activities()` already returns `categoryIDs` ordered by
  assignment position, and `LocalStore.categories()` exists — no schema or
  store changes are needed. `CatalogIcon(validated:).displaySymbol` provides
  the `tag` fallback for symbols unavailable on the running OS.
- LocalStore remains the single mutation chokepoint; this change is
  read-only against the store.

## Goals / Non-Goals

**Goals:**

- One ordered layout that uses spare height on large devices and collapses
  spacing before content overlaps on compact devices or at larger text sizes.
- Recents chips that are informative (icon, selected state, honest empty
  copy) without making capture require Categories.

**Non-Goals:**

- No Category names or icons anywhere else on Track (search results,
  selected-Activity row) — user decision, encoded in the delta specs.
- No chip reordering, pinning, filtering, or removal.
- No History/Insights/compact-timer changes.

## Decisions

### D1 - Track uses a dual-flow layout with one approved cap and a central separator
**Choice:** Build one vertical composition in this order: title → top adaptive
spacer → completion-mark region → timer numbers → timer status → reserved
error region → central separator → Activity search/refine →
state-specific main action → Recents → bottom adaptive spacer → tab bar.
The top and bottom spacers share one maximum-height token and resolve to
equal heights: when the free space (`slack = viewport - content`) is
positive, each spacer gets `min(cap, slack/2)`; any surplus beyond twice the
cap goes to the **central separator** between the error region and the
search/refine flow. With negative slack both spacers and the central
separator collapse to zero and the ordered content scrolls. The shared cap
is **48 pt** (selected by the user from the 24/48/72/96 Pro Max spike
comparison, then validated on SE). The main action sits above Recents so
Choose Activity / Start / Stop stays reachable without scrolling on short
screens (user-directed swap after the SE spike); it changes between those
three controls without changing its region — D10 pins that region's frame
across all timer states. The local-first screen removes
the obsolete offline hint and, for now, has **no editing affordance** — the
former beside-picker Refine (and the interim "Edit activity" spike variant)
is removed; its placement is deferred to a later change (D9 retired).

**Rationale:** Equal ends give the composition a symmetric rhythm (a "dual
flow": the timer stack hangs from the top, the control stack from the
bottom), and the central separator makes the cap visible on roomy screens:
a smaller cap pushes the flows apart, a larger cap pulls them together. A
zero minimum ensures spacing disappears before controls overlap or become
unreachable on SE or under accessibility text sizes. Putting the main action
above Recents keeps the primary CTA above the fold when Recents wraps tall.

**Alternatives considered:** (a) A pinned `.safeAreaInset` action bar — keeps
the action reachable but prevents the requested flow order; rejected. (b)
Fixed top and bottom padding — cannot respond to compact height or Dynamic
Type; rejected. (c) Bottom-first surplus distribution — user rejected it:
equal top/bottom spacing is required. (d) Main action below Recents —
user rejected it after the SE spike (required scrolling to reach the
button). (e) Separate top and bottom caps — defer unless the validated
shared cap proves inadequate.

### D2 - Recents become a capped wrapping chip flow
**Choice:** Replace the single-row horizontal `ScrollView` with a wrapping
flow of at most 6 chips, most-recently-used first, computed from
`activities.prefix(6)` (the store already sorts by `last_used_at`). Packing
reuses the measured-width greedy algorithm from `TagSelector` (icon slot +
text width + uniform padding, equal `spacingSmall` gaps, container width via
`GeometryReader` + preference key) in a new `RecentActivitiesChips` view.

**Rationale:** Horizontal scrolling hides chips and needs a cut-off hint;
icons widen chips, making single-row worse. A cap of 6 keeps Recents from
dominating the screen (≈2 rows typical, 3 on narrow devices) while covering
the realistic "what do I usually track" set. Multiline growth consumes
adaptive spacing first; scrolling remains the final fallback when both
spacers reach zero.

**Alternatives considered:** Keep 5 in one scrollable row (status quo) —
rejected for the discoverability reasons above; reuse `TagSelector` directly
— rejected, it is selection-toggle semantics over `Category` objects; a new
generic `FlowChips` container extracted from `TagSelector` — deferred: the
refactor would touch the category editor inside this change for little gain;
the ~40-line packing block is acceptable duplication, noted as future
cleanup.

### D3 - Chips show the first assigned Category's icon only
**Choice:** A chip renders `CatalogIcon(validated:).displaySymbol` for
`activity.categoryIDs.first` (first by assignment position, already
position-ordered by the store) in a fixed symbol slot; Activities without
Categories render name-only chips with no icon and no placeholder glyph.

**Rationale:** The icon is a recognition anchor, not metadata competition —
no Category name appears, preserving the D9 "task stays concrete" rationale
while adding scannability. No icon for categoryless Activities is a user
decision: a neutral glyph would falsely imply a Category exists.

**Alternatives considered:** Show the icon for all Categories or the Category
name — rejected (noise + spec reversal goes further than needed). Neutral
`tag`/dot placeholder for categoryless — rejected by the user.

### D4 - Selected chip keeps its icon and switches to a filled accent presentation
**Choice:** The prepared Activity's chip switches to a filled accent
presentation while keeping the Category icon: accent background, on-accent
text, and an accent border. No checkmark — the fill/contrast swap is the
same non-color-only selected treatment `TagSelector` uses
(category-management D9) and keeps chips compact on narrow screens.
Accessibility: `.isSelected` trait plus `accessibilityValue` "Selected" on
the matching chip. Highlighting derives from
`state.activity?.id == chipActivity.id`, so it survives the saved→ready
reset and Refine in-place replacement automatically.

**Rationale:** A trailing checkmark was spike-tested and rejected by the
user: it widens every chip (reserved slot) and reads as noise on SE where
chips wrap one-per-row; the filled-vs-outlined contrast is perceivable
without color alone (category-management accessibility requirement analog)
and leaves the icon untouched.

**Alternatives considered:** Checkmark-in-place-of-icon — rejected (hides the
icon). Color-only tint — rejected (fails non-color-only requirement).
Trailing checkmark + tint — user-rejected after the SE spike.

### D5 - Dedicated empty-Recents copy
**Choice:** New key `timer.recentsEmptyHint` = "Activities you track will
appear here." (EN) / "Здесь появятся активности, которые вы отслеживаете."
(RU), added to both `.lproj` files and the `L10n` enum. The search sheet
keeps its own empty-catalog string.

**Rationale:** The current reuse of `timer.searchEmptyCatalogSubtitle` is
search-context ("enter a name in the search field") and reads wrong under a
"Recent" header.

### D6 - TrackViewModel resolves chip icons from a Categories map
**Choice:** `TrackViewModel.load()` fetches `store.categories()` into a
`[String: Category]` map alongside `activities()`; `saveRefinement` refreshes
both (assignment edits change icons). Recents renders icons from this map;
no Category is required and no failure path blocks rendering (a missing
Category simply renders a name-only chip).

**Rationale:** `Activity` carries only ids; the VM already owns the catalog
load pattern. A map lookup is O(1) per chip with ≤6 chips.

### D7 - Four Pro Max cap spikes require explicit approval before implementation
**Choice:** Before production work, build the adaptive layout behind a DEBUG
spike using one shared spacer cap. Run four iPhone 17 Pro Max variants in
this order: 24, 48, 72, and 96 pt. For every variant capture screenshots and
normalized frames for the completion mark, timer numbers/status, error
region, search/refine, Recents, main action, and tab bar in representative
idle, ready, running, saved, and error states. Present the four variants
together; do not select or implement a production value until the user
explicitly approves one. Then run only the approved value on iPhone SE (1st
generation, iOS 15.5) with six icon-bearing Activities at both default and
Large Dynamic Type. If it clips or overlaps, return to the Pro Max
comparison with revised candidates rather than silently changing the cap.
Production implementation is blocked until the user explicitly approves the
final Pro Max + SE result.

**Outcome:** the user selected **48 pt**. SE validation (default + Large
Dynamic Type) passed with user-requested revisions folded into the harness:
(1) the selected chip keeps a filled accent presentation without a
checkmark (D4), (2) the error text wraps instead of being cut — the region
keeps its reserved height when empty and grows past it when the wrapped
error is taller, with the adaptive spacers yielding first (D8),
(3) the editing affordance was removed from Track entirely (its placement is
deferred; the interim "Edit activity" variant was also rejected as excessive
— D9 retired), (4) the main action moved above Recents so Choose/Start/Stop
is reachable without scrolling, (5) Large Dynamic Type is exercised through the simulator's real
content-size setting (SE) and a `.dynamicTypeSize(.accessibility5)`
environment override (Pro Max); chip-width measurement uses a trait
collection matching the effective environment size so packing never overruns
and chip text is never cropped.

**Rationale:** The cap is a visual rhythm decision, not an implementation
detail. Sequential variants make the trade-off visible on the roomy target;
SE validation proves the zero-minimum compression before the chosen value is
committed to production.

### D8 - Error space is reserved above the central separator; text wraps
**Choice:** A reserved-height non-field-error region sits immediately above
the central separator (i.e. directly above the Activity search/refine flow).
When no error exists it preserves geometry but is absent from the
accessibility tree. When an error is shown, the text wraps fully and is
never cut: the region grows past the reserved height only if the wrapped
error is taller, and the growth yields from the top spacer first, then the
central separator — both above the main action, keeping it stationary (D10)
— falling back to the screen's scrolling behavior only when both are
already zero.

**Rationale:** Errors remain near the controls they affect while state
transitions do not move search/refine, Recents, or the main action; the
user rejected truncated error text during the SE spike.

### D9 - Retired: editing affordance on Track
The beside-picker "Refine" action was first replaced by a full-width
"Edit activity" secondary action below the picker, then **removed entirely**
after the SE spike: the user found the extra action excessive and will
decide its placement later. Track shows no editing affordance until a
follow-up change; the Activity editor sheet and its view-model presentation
machinery remain wired but unreachable from Track (they serve Manage
Activities and are reused by the future placement).

**Rationale:** Keep the capture surface minimal; editing placement deserves
its own design pass rather than a stop-gap position on Track.

**Alternatives considered:** Full-width "Edit activity" below the picker —
user-rejected after the SE spike. Keeping Refine beside the picker —
superseded by the removal decision.

### D10 - The main action holds one frame across all timer states
**Choice:** Make the content height around the main action state-invariant,
then pin the bottom flow:

1. The preparation-row slot is reserved in every state: idle renders the
   slot empty (transparent, excluded from the accessibility tree) at the
   picker/label height.
2. While Recents is hidden during running and error states, the chips keep
   their occupied height (hidden but layout-preserving); saving and saved
   show the chips in the same place.
3. The main action renders in a fixed-height slot whose height equals the
   tallest of its state titles (Choose an activity / Start / Stop) at the
   active Dynamic Type size, so title changes never resize the control.
4. The spacing model pins the bottom flow: the bottom spacer is computed
   once from the state-invariant content using the D1 equal split and held
   fixed; growth of the top flow (a wrapped error) compresses the top
   spacer first, then the central separator. Only when both are exhausted
   does the ordered content scroll (the accepted fallback where the button
   may move).

**Rationale:** With identical content heights, the D1 equal-split algorithm
runs on identical input in every non-error state and yields identical
frames; the four reservations do all the work. Error growth is the only
state-driven height change left, and it is absorbed entirely above the main
action (top spacer, then central separator) — the same reserve-first
pattern as the completion-mark and error regions. The resulting empty band
below Stop while running is inherent to hiding Recents under a pinned
button; the chips reappear in place on stop.

**Alternatives considered:** (a) Bottom-residual asymmetric distribution —
pins the button on roomy screens but on SE the idle state's slack cannot
absorb the full preparation-row height, and it discards D1's equal-split
symmetry; rejected. (b) A fixed three-row chip reservation in every state —
wastes space with few Activities; rejected. (c) Accepting movement and
animating it — contradicts the requirement.

## Risks / Trade-offs

- [A shared cap may create an unbalanced composition]
  → Resolved: equal top/bottom ends plus the central separator; the user
  selected 48 pt from the 24/48/72/96 Pro Max comparison.
- [The category-management reversal invites scope creep toward names/icons
  in search] → Specs now explicitly scope icons to Recents chips only; the
  selected-Activity row and search stay category-free.
- [Duplicate flow-packing logic diverges from TagSelector]
  → Acceptable duplication for now; extraction to a shared component is a
  listed cleanup, not part of this change.
- [Dynamic Type XL on SE could exhaust both adaptive spacers]
  → Spacers collapse independently to zero, then the ordered content scrolls;
  validated on SE at cap 48 for default and Large Dynamic Type.
- [Refine changing Categories must repaint chip icons immediately]
  → `saveRefinement` already reloads activities; D6 adds the Categories
  reload to the same path.
- [A wrapped error could grow the reserved region and shift content]
  → Resolved by D10: the top spacer yields first, then the central
  separator, keeping the main action stationary; scrolling only when both
  are zero.
- [Hiding Recents while running leaves an empty band below Stop]
  → Accepted: the pinning requirement makes the space inherent; chips
  reappear in place on stop. The reserved height is captured from the last
  visible Recents state and stays valid because the activity set is
  read-only during a run.

## Migration Plan

1. Run all four Pro Max cap spikes (D7), present the comparison, and stop for
   explicit user selection.
2. Validate the selected cap on SE at default and Large Dynamic Type, present
   both results, and stop again for explicit production approval.
3. Only after approval, implement the adaptive Track restructure,
   `RecentActivitiesChips`, editing-affordance removal (D9), offline-hint
   removal, and VM changes.
4. Implement the state-invariant main-action frame (D10): reserved idle
   preparation slot, hidden-but-reserved Recents, fixed-height action slot,
   bottom-flow pinning with top-first error yield.
5. Update `Design/SCREENS/TimeTracking.md`, `Design/DECISIONS.md`,
   `Design/COMPONENTS.md` to match the shipped layout and the
   icon-in-recents reversal; add the localization keys (U4).
6. Full test pass (both suites), SwiftLint strict, manual SE + Pro Max
   verification across idle/ready/running/saving/saved/error and both
   locales.

Rollback is a source-level revert; no schema, backend, or OpenAPI changes.
