## 1. Implementation

- [x] 1.1 Disable Start while saved: return `true` for the `.saved` case in `TrackContent.primaryDisabled` (no ViewModel change; `start()`'s `.ready` guard stays as the safety net)
- [x] 1.2 Update any tests asserting saved-state button enablement to the dimmed expectation (`TrackViewModelTests`, view tests)

## 2. Verification

- [x] 2.1 `swiftlint lint --strict` clean and `xcodebuild test -scheme TimeOfLife` green
- [ ] 2.2 Manual check on device/simulator: Stop → Start renders dimmed for the confirmation window, ignores taps, re-enables with `.ready`
- [ ] 2.3 `openspec validate --all` green; sync delta to baselines and archive
