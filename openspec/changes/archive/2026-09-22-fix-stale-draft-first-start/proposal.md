## Why

After stopping an activity, editing the name and tapping Start does nothing on the first tap — the timer only starts on the second tap. The committed `.ready` draft goes stale relative to the field, and the focus-resign recompute cancels the deferred start without re-issuing it. Found while verifying `disable-start-while-saved`; that change only made the dead tap visible, the race predates it.

## What Changes

- A Start tap SHALL start the timer on the **first** tap using the field's current text, including when the name was edited after a stop while the field stayed focused (no silent cancel-without-retry).
- Pin down edits made while the saved confirmation is showing (today they flip to `.ready` early and cut the confirmation short): specs SHALL define whether the confirmation is kept or the early return stands.
- Non-goals: changing the 1.6 s confirmation window, idle/empty-text disablement, any other state's enablement, persistence or sync behavior.

## Capabilities

### New Capabilities

(none)

### Modified Capabilities

- `timer-capture-experience`: Start responsiveness after post-stop edits (first-tap scenario on the explicit-confirmation requirement) and the saved-window edit behavior.

## Impact

- `TrackViewModel.start()` / `syncReadyFromDraft()` interplay (`ios/TimeOfLife/TimeOfLife/Features/TimeTracking/ViewModels/TrackViewModel.swift`); no store, sync, or API changes.
- Test additions in `TimeOfLifeTests/TrackViewModelTests.swift` (focused Start with a stale committed draft; edit-during-saved case).
