## Why

The running "Categories" label sits 4 pt above its chips while the structurally identical "Recent" block uses 8 pt. Per `Design/TOKENS.md`, label-to-content is the grouped-elements case (8 pt); 4 pt is the tight-gaps token. The Categories block is the outlier.

## What Changes

- `TrackContent.runningTagSelector`: label-to-`TagSelector` `VStack` spacing `Theme.spacingExtraSmall` → `Theme.spacingSmall`, matching `recentActivities`.
- Non-goals: any other spacing, any behavior or state change, new tokens or components.

## Capabilities

### New Capabilities

(none)

### Modified Capabilities

(none — visual token alignment only; no requirement changes, so this change sets `skip_specs: true`.)

## Impact

- `ios/TimeOfLife/TimeOfLife/Features/TimeTracking/Views/TrackContent.swift` (`runningTagSelector` only). No store, sync, API, or localization changes.
