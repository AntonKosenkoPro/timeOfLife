## 1. Implementation

- [x] 1.1 First-tap Start after a post-stop edit: bring the committed preparation up to date from the field at tap time for `.ready` (extend the `.idle` pre-sync in `TrackViewModel.start()`); keep the deferred-start cancel rule for genuine concurrent edits and the `.ready` guard as the safety net
- [x] 1.2 Tests: focused Start with a stale committed draft starts on the first tap with the edited text (`TrackViewModelTests`); edit-during-saved returns to ready at once; existing `draftEditCancelsDeferredStart` / `focusedStartDefers` still green

## 2. Verification

- [x] 2.1 `swiftlint lint --strict` clean and `xcodebuild test -scheme TimeOfLife` green
- [x] 2.2 Manual check on device/simulator: stop → edit name → Start starts on the first tap with the new text; edit during the saved confirmation returns to ready at once
- [x] 2.3 `openspec validate --all` green; sync delta to baselines and archive
