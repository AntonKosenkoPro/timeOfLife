## 1. Implementation

- [x] 1.1 Categories title-to-chips spacing: `Theme.spacingExtraSmall` → `Theme.spacingSmall` in `TrackContent.runningTagSelector` (Recents already uses `spacingSmall`; no other edits)

## 2. Verification

- [x] 2.1 `swiftlint lint --strict` clean and `xcodebuild test -scheme TimeOfLife` green
- [x] 2.2 Visual check on device/simulator (running state): Categories label-to-chips gap matches the Recents gap; below-button slot geometry unchanged
- [x] 2.3 `openspec validate --all` green and archive
