## MODIFIED Requirements

### Requirement: Stop saves with stable feedback
Stopping a running timer SHALL save the completed entry locally, communicate success without a blocking loader, and retain the activity in the ready state for an optional later restart. When the persisted running timer is gone but Track still holds a `.running` state (the timer was stopped from the compact timer on another destination), Track SHALL reconcile on next load: stop the elapsed ticker, re-enable the idle timer, reset elapsed to zero, and return to `.ready` for the same activity — or `.idle` when that activity no longer exists — instead of counting elapsed time forever. When the activity itself was deleted (on another device) while its timer was running, stopping SHALL clear the running state, discard the session (no entry is saved for a deleted activity), and settle Track to `.idle` with a localized "deleted on another device" message instead of looping a failing save.

#### Scenario: Successful stop
- **WHEN** the user activates Stop on a running timer
- **THEN** the app persists the completed entry, clears running state, emits a success haptic, briefly confirms the saved duration, and returns to the ready numeric timer for the same Activity

#### Scenario: Save failure
- **WHEN** the local store cannot save the completed entry
- **THEN** the app preserves recoverable running state and presents a localized non-field error without silently losing elapsed time

#### Scenario: External stop reconciles Track
- **WHEN** Track holds a running state for an activity whose persisted timer no longer exists (stopped from the compact timer elsewhere)
- **THEN** Track leaves the running state on next load: the ticker stops, elapsed resets to zero, and the screen shows the ready timer for the same activity (or idle when the activity is gone)

#### Scenario: Stop after the activity was deleted elsewhere
- **WHEN** the user stops a timer whose activity no longer exists locally (deleted on another device)
- **THEN** the running state clears, no entry is saved, and Track shows `.idle` with a localized message naming the deletion — never a retry loop
