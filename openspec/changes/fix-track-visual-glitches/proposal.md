## Why

The Track screen has three small visual defects that break alignment consistency, section legibility, and recents usefulness: the running locked-name card centers its text while every other name row is leading-aligned, the Categories/Recents section headers sit directly on their chips with no visual separation, and Recents is capped at 6 so frequently-used names fall off with no way to reach them.

## What Changes

- Locked running name (`runningNameRow`, also applied to the `saving` locked label if it diverges) aligns its text to the leading edge, matching the idle/ready `nameRow` and the `lockedNameLabel` grammar (icon + text + `Spacer`, leading alignment).
- A `Divider` separator is rendered between the section header (`Categories` / `Recents` caption) and its chips in both below-action branches (`recentActivities` and `runningTagSelector`), using existing `Theme` tokens only.
- Recents cap grows from 6 to 12 (`TrackViewModel.storeRecents`, `RecentActivitiesChips.recents(from:limit:)`); the chip area keeps its current on-screen footprint and gains its own internal vertical scroll when 12 chips overflow, without making the whole Track page scroll.

## Capabilities

### New Capabilities

- None.

### Modified Capabilities

- `timer-capture-experience`: running locked-name alignment rule, header-to-chips separator rule, Recents cap 12 + fixed-footprint internal scroll rule.

## Impact

- iOS Track UI only: `TrackContent.swift` (`runningNameRow`, `recentActivities`, `runningTagSelector`, below-action slot sizing), `RecentActivitiesChips.swift` (limit + scroll container), `TrackViewModel.swift` (`storeRecents(limit:)`).
- No backend, OpenAPI, store schema, or navigation changes. No new strings (reuse existing `L10n` captions); no `Theme` token changes.
- Tests: existing Track/Recents SwiftTesting suites updated for the new cap and scroll/separator/alignment assertions; previews for running + 12-chip overflow.
- Implementation worktree: `../timeOfLife.wt/fix-track-visual-glitches` on branch `opsx/fix-track-visual-glitches` (isolated from the main checkout).
