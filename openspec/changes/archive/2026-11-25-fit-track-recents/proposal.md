## Why

[Issue #247](https://github.com/AntonKosenkoPro/timeOfLife/issues/247) reports competing page and section scrolling on Track. Complete the Recents portion first by fitting shortcuts into the space below the main action, with a small scrolling fallback instead of letting Recents overflow move the page.

## What Changes

- Replace the 12-item, up-to-four-visible-row Recents policy with a maximum of 10 newest distinct exact-text candidates and a measured, newest-first fitting prefix.
- If five or more candidates fit completely, show the fitting prefix, capped at 10, without Recents scrolling. Count chips, not rows; do not skip newer names to pack in older, shorter names.
- If fewer than five fit, offer only the newest five (or all available candidates when fewer exist) through internal scrolling when they overflow. If all available items fit, do not enable scrolling, even when there are fewer than five.
- Bound Recents by the actual remaining space between the main action and tab bar, accounting for its caption, spacing, safe area, and active text size. Recents overflow alone must not cause page scrolling.
- Preserve stationary Start/Stop positioning, the existing empty state, chip selection, icons, exact-text identity, and the accessibility page-scroll fallback when core controls plus one usable chip row cannot fit. The minimum row uses the active text size and existing border clearance; do not hide Recents to avoid that fallback.
- **Non-goals:** running categories/TagSelector behavior (a separate work item), globally removing Track scrolling in every state, name-picker limits or navigation, new overflow buttons/copy, backend/API/storage-schema changes, Live Activities, or unrelated layout refactoring. This change addresses part of #247; it must not auto-close the issue.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `timer-capture-experience`: change the Recents candidate cap, fit-driven display count, internal-scroll threshold, and Recents overflow behavior while preserving primary-action and running-category contracts.

## Impact

- iOS: `TrackViewModel.recentsLimit`, `RecentActivitiesChips`, Track's finite height-budget plumbing, and a testable wrapping/fit policy reusing existing `FlowLayout` measurements where appropriate. Shared `ChipViewport` changes must be isolated from running tags.
- Verification: chip-count boundary/packing tests, current-tree reproduction before implementation, compact/roomy/large-text UI checks, error growth and Start/Stop anchor regressions, and unchanged running-category/name-picker behavior.
- Implementation-time documentation: `Design/COMPONENTS.md`, `Design/SCREENS/TimeTracking.md`, relevant decisions/interactions, and `docs/project-context.md`. Baseline OpenSpec specs remain untouched until archive. No new dependencies or strings are planned.
- Research: see `design.md` for the fetched ctx7 IDs, exact queries, iOS 18 SDK via Xcode 16+ pin, and inapplicable-library waiver. The topic/API layout measurement and HIG Dynamic Type guidance constrain fitting; framework details must be reconfirmed at apply time.
- Proposal stage only: no current-tree runtime reproduction, application changes, lint/build, or application test runs are claimed.
