## MODIFIED Requirements

### Requirement: Stop saves with stable feedback
Stopping a running timer SHALL save the completed entry locally, communicate success without a blocking loader, and retain the entered text in the ready state for an optional later restart. While the saved confirmation is showing, the Start button SHALL render disabled (dimmed, non-interactive) since starting is not possible until the state settles back to ready; it SHALL re-enable with the return to ready. When the persisted running draft is gone but Track still holds a `.running` state (the timer was stopped from the compact timer on another destination), Track SHALL reconcile on next load: stop the elapsed ticker, re-enable the idle timer, reset elapsed to zero, and return to `.ready` for the same text — or `.idle` when nothing was entered — instead of counting elapsed time forever.

#### Scenario: Successful stop
- **WHEN** the user activates Stop on a running timer
- **THEN** the app persists the completed entry, clears running state, emits a success haptic, briefly confirms the saved duration, and returns to the ready numeric timer for the same text

#### Scenario: Save failure
- **WHEN** the local store cannot save the completed entry
- **THEN** the app preserves recoverable running state and presents a localized non-field error without silently losing elapsed time

#### Scenario: External stop reconciles Track
- **WHEN** Track holds a running state whose persisted draft no longer exists (stopped from the compact timer elsewhere)
- **THEN** Track leaves the running state on next load: the ticker stops, elapsed resets to zero, and the screen shows the ready timer for the same text (or idle when empty)

#### Scenario: Stop after the activity was deleted elsewhere
- **WHEN** the user stops a timer (no deletable parent exists; entries and drafts cannot be deleted out from under a run)
- **THEN** the entry always saves normally; this scenario is retained as a no-op for archive continuity

#### Scenario: Start is disabled during the saved confirmation
- **WHEN** the saved confirmation is showing after a stop
- **THEN** the Start button renders dimmed and ignores taps; it re-enables when the state settles back to ready
