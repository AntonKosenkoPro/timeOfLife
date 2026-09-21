# Tasks — track-settle-polish (all complete; implementation verified before the change was written)

- [x] 1.1 Refresh-on-return: `TrackView.task` loads on appear; `AppShellView` reloads Track on tab-return and Profile-sheet dismiss (`timer-capture-experience` Recents return-refresh scenario)
- [x] 1.2 Seed-before-fetch in `TrackViewModel.load()` + shared `String.starterCategoryNames` (fresh-install tags never empty)
- [x] 1.3 Keyboard-deferred Start swap: resign at tap (haptic + tap-time `startedAt`), fire on real `didHide` with 600 ms fallback, cancel on draft change (`Starting` defer/cancel/instant scenarios; `TrackViewModelTests.focusedStartDefers`, `draftEditCancelsDeferredStart`)
- [x] 1.4 Both-branches-mounted below-button slot + `transaction(animation: nil)` + `PrimaryButton(animateStateChanges: false)` (`Main action` frame scenarios; frame-verified on simulator, user-verified on iPhone)
- [x] 1.5 `swiftlint lint --strict` clean, `xcodebuild test` green, device Release builds and installs
- [x] 1.6 Sync delta specs to baselines, `openspec validate --all` green, archive
