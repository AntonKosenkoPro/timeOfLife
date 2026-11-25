## Context

See `proposal.md` for motivation and `specs/timer-capture-experience/spec.md` for the count/scroll contract. A design is needed because fit-driven content interacts with the shared Start/Stop anchor and hidden running-category layout.

Currently `TrackViewModel.recentsLimit` is 12. `RecentActivitiesChips` always uses a vertical `ScrollView` around `FlowLayout`; shared `ChipViewport` clamps to four rows with a one-row floor. `TrackContent.chipAvailableHeight` already measures a finite viewport outside the outer `AdaptiveVerticalLayout` scroll view and subtracts fixed content. Recents and tags remain mounted in a max-height `ZStack`, with the inactive branch inaccessible and not hit-testable.

Preserve the baseline main-action invariant and Design D10/D34: state-independent action height, both below-action branches mounted, adaptive spacing yielding before content. The running-category requirement stays unchanged. The active `preserve-running-notes-on-live-stop` change modifies a different requirement in the same capability; do not copy or overwrite that delta.

## Goals / Non-Goals

**Goals:** deterministic, testable measurement of a contiguous newest-first prefix; one geometry source for fitting and placement; stable main-action frames across state transitions; no page growth from extra shortcut rows.

**Non-Goals:** a general-purpose layout rewrite, changing category packing or scroll policy, persisting fit state, a new picker/overflow affordance, or new dependencies. Do not turn the ten-item shortcut cap into a name-picker or history-data limit.

## Decisions

### 1. Separate candidate selection, packing, and offered content

Keep the existing exact-text query/order and category inheritance; change only Track's candidate limit to 10. Do not change `allActivityNames()` or a repository-wide default merely to alter Track.

Measure up to ten chips using actual rendered dimensions at the current width, text size, icon and selected presentation. Reuse/extract the existing greedy `FlowLayout` packing arithmetic as a pure calculation rather than estimating capacity from an average width or a fixed row count. Row height is the largest item height on that row; width clamping and spacing must match placement.

Let `N <= 10` be the candidate count and `C` the largest prefix whose complete wrapping layout fits the finite remaining chip budget, before applying the minimum-row accessibility floor:

| Condition | Offered set | Internal scrolling |
| --- | --- | --- |
| `C == N` | All `N` | Off |
| `C >= 5` | First `C` | Off |
| Otherwise | First `min(5, N)` | Only if that set overflows |

Measure prefix layouts consistently, including a taller chip increasing an existing row's height. Do not skip a long newer name to pack an older short one. Do not merely clip ten mounted chips: omitted items must not remain tappable or discoverable by VoiceOver. An off-screen measurement pass, if needed, must be non-interactive and accessibility-hidden.

**Alternatives rejected:** counting rows (not the agreed unit), always retaining all ten in a scroller (violates the newest-five fallback), and rendering all ten then masking overflow (leaves unreachable shortcuts and can leak accessibility elements).

### 2. Keep a finite budget and an explicit minimum-row fallback

Use Track's measured viewport and existing safe-area/tab-bar treatment, not screen dimensions or an unbounded height offered by a vertical scroll view. Include the caption, actual wrapped-error growth, required gaps, and 1 pt border clearance on each edge once. Fit calculations and displayed viewport must share those deductions.

The current budget already assumes adaptive spacers can yield to zero. If less than one accessible chip row remains, there is no spare space to reclaim: the owner explicitly chose to keep one usable row and permit the accessibility page-scroll fallback. Its minimum height follows the active text size and is at least the existing 44 pt tap-target height plus 2 pt border clearance. Choose the offered set against the finite remaining budget first, then apply the minimum viewport floor and scroll the offered set only if it actually overflows that viewport. Do not let the artificial floor promote the offered set beyond five, or treat all five offered chips as required page height. Empty Recents retains its existing hint rather than manufacturing a chip row.

Missing/invalid initial geometry is a measurement state, not a user error: retain a bounded provisional one-row layout, do not publish a banner or mutate entries, and resolve from finite measurements. Never infer that ten chips fit from an infinite/unknown offer. Keep complete-first-paint data and verify that geometry convergence does not introduce visible post-settle jumps.

**Alternatives rejected:** hiding Recents when no full row fits (owner rejected), shrinking targets (accessibility regression), and using a multi-row minimum to trigger page scroll (defeats the overflow rule).

### 3. Isolate Recents without breaking the shared anchor

Introduce a Recents-specific policy beside the shared row-clamp policy; do not change `ChipViewport.maxVisibleRows` globally. Leave running `TagSelector`'s four-row clamp, one-row floor, category order, and dividers unchanged. Preserve the mounted max-height lower slot, fixed-height main-action slot, shared caption reservation, and inactive-branch accessibility/hit-testing exclusion.

Constrain Recents' measured height to its offered content/budget before the lower-slot max is taken. Both mounted branches must remain finite; a hidden full chip flow must not determine page height. Cover the hidden tags' one-row floor in the minimum-row fallback predicate. Keep `AdaptiveVerticalLayout` available for the explicit accessibility fallback rather than branching the entire page into different idle/running layouts.

Use a plain flow for the non-scrolling presentation, or isolate any scroll disabling to Recents. Do not apply `.scrollDisabled(true)` to the outer page: Apple documents that it propagates through the environment to nested scroll views. Preserve edge-aware dividers only for actual internal overflow, and reset/clamp offsets when geometry or offered content changes.

**Alternatives rejected:** separate state-specific outer containers (can remeasure the anchor on Start/Stop), globally disabling the page scroller (also disables descendants), and changing shared limits (silently changes categories).

### 4. Research bundle and requirement alignment

Fetched in this explore/propose session on 2026-11-20; Apple API target: **iOS 18 SDK via Xcode 16+**. ctx7 supplied unversioned Apple documentation, not a frozen SDK snapshot; implementation must recheck API availability at apply time.

- **Topic + Apple API:** resolved SwiftUI with `library "SwiftUI" "iOS 18 size-aware chip layout fitting available height custom Layout and scrollDisabled environment propagation"` to `/websites/developer_apple_swiftui`. Latest proposal fetch: `docs /websites/developer_apple_swiftui "iOS 18 SDK via Xcode 16+: custom Layout measuring wrapping chip subviews with sizeThatFits proposals and finite available height"`. Apple explains zero/infinite/unspecified proposals and subview measurement: [Layout sizing](https://developer.apple.com/documentation/swiftui/layout/sizethatfits(proposal:subviews:cache:)), [dimensions](https://developer.apple.com/documentation/swiftui/layoutsubview/dimensions(in:)).
- **Nested-scroll API:** exploration fetch on the same resolved ID: `docs /websites/developer_apple_swiftui "scrollDisabled isScrollEnabled environment ancestor disables descendant ScrollViews"`; [Apple source](https://developer.apple.com/documentation/swiftui/view/scrolldisabled(_:)) establishes inherited disabling.
- **HIG:** resolved `library "Apple Human Interface Guidelines" "Adaptive layouts and accessibility Dynamic Type large text scrolling without clipping primary controls"` to `/websites/developer_apple_design_human-interface-guidelines`, then fetched `docs /websites/developer_apple_design_human-interface-guidelines "Supporting Dynamic Type adaptive layouts large text sizes while keeping primary controls accessible"`. [Typography](https://developer.apple.com/design/human-interface-guidelines/typography) and [layout](https://developer.apple.com/design/human-interface-guidelines/layout) require adapting to large text, preserving hierarchy, and avoiding cropped content.
- **External-library setup/best-practice waiver:** no new external library/service or configuration is involved; only existing native SwiftUI layout and repo-local helpers change. HIG/API sources above supply applicable layout best practices.
- **FURPS:** rechecked `Common.md` U1–U5, S2–S7 and +2; `Activity_Catalog_and_Categories.md` F1/F3–F5, U3/U8/U9, P1; `Timetracking.md` F13. Implementation must revise the conflicting 12-cap/fixed-scroll F5/U3 rows, not quietly leave them stale. Exact text, inherited categories, all five locales, Theme, 44 pt targets, and uncapped picker remain intact.

## Risks / Trade-offs

- [Fewer visible shortcuts] → Intended: a seven-chip fit hides candidates eight through ten; the existing picker still exposes all names. No new strings or buttons.
- [Threshold flicker or stale layout cache] → Share packing inputs/results; invalidate for width, dimensions, Dynamic Type and changed candidates, not only width; test boundaries at four/five/ten and selection.
- [Error growth or hidden categories forces page overflow] → Subtract the full required content once; test the max-height slot and minimum-row case before/after state transitions.
- [Large text still requires page scrolling] → Explicitly accepted only for required content plus a usable minimum row; never clip essential content or shrink controls to claim “no scroll.”
- [Code inspection mistaken for reproduction] → Proposal research is not runtime proof. Current-tree reproduction plus research reconfirmation jointly gate implementation; stop if the issue cannot be reproduced.

## Migration Plan

No data, API, or on-disk migration. After proposal approval, reproduce first, implement on this branch, update design/FURPS/context docs, then run the planned verification. Rollback is a normal code revert restoring the previous shortcut policy; account data and picker content are unchanged. Keep #247 open for the separate categories work item. Do not archive or merge without the later human approval gates.
