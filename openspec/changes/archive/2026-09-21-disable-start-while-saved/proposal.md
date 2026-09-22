## Why

After Stop, Track shows a ~1.6 s saved confirmation during which the Start
button renders fully enabled — but tapping it does nothing (`start()`
only starts from `.ready`, and the state is `.saved` until the reset timer
fires). An active-looking button that swallows taps is a dishonest signal;
the one other non-startable configuration (idle with empty text) already
renders dimmed, so the fix reuses that established language.

## What Changes

- The Start button renders **disabled** (dimmed, non-interactive) while
  Track is in the `.saved` confirmation state, and re-enables when the
  state settles back to `.ready`. No timing, navigation, or persistence
  changes: the 1.6 s window, the confirmation mark, and the auto-return to
  ready are untouched.
- Non-goals: making a saved-state tap start immediately (rejected in
  exploration — accidental restarts), changing the confirmation duration,
  touching any other state's enablement.

## Capabilities

### New Capabilities

(none)

### Modified Capabilities

- `timer-capture-experience`: the "Stop saves with stable feedback"
  requirement gains the saved-state Start-button enablement (new scenario;
  requirement text extended by one sentence).

## Impact

- `TrackContent.primaryDisabled` (one case arm); no ViewModel, store, sync,
  or API changes.
- Existing `TrackViewModelTests`/view tests asserting saved-state button
  state may need updating to the dimmed expectation.
