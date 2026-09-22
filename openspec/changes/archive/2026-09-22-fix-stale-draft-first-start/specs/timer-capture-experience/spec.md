## MODIFIED Requirements

### Requirement: Starting always requires explicit confirmation
Selecting a recent or typing a name SHALL prepare it without starting a timer; the timer SHALL begin only after the user activates Start. Unconfirmed typed input SHALL NOT start a timer or create an entry. A focused Start tap SHALL resign the field immediately (selection haptic fires and `started_at` is captured at tap time) and delay the running swap until the keyboard finishes dismissing (real `didHide`, bounded fallback for hardware keyboards); the swap SHALL then render instantly with no animation of its own. A Start tap SHALL start timing on the first tap using the field's current text, even when the committed preparation went stale (for example edited after a stop): the tap SHALL bring the preparation up to date before the swap is scheduled, so the resign that follows finds nothing to cancel. Any other field edit or chip tap before the swap fires SHALL cancel the deferred start.

#### Scenario: Select recent activity
- **WHEN** the user taps a recent chip
- **THEN** the app fills the exact text plus that recent's full ordered categories and shows the ready numeric timer without creating an entry

#### Scenario: Select or create through search
- **WHEN** the user types a trimmed non-empty name, whether or not it exactly matches a recent (no search sheet exists; typing is the only input)
- **THEN** the app shows the ready numeric timer without starting timing; an exact-recent match prefills that recent's categories, otherwise categories start empty

#### Scenario: Search input remains unresolved
- **WHEN** the user has typed text but has not activated Start
- **THEN** nothing starts, no entry is created, and the typed text stays editable in the name field

#### Scenario: Start selected activity
- **WHEN** a name is prepared and the user activates Start
- **THEN** the app persists the running draft immediately, begins elapsed-time presentation, and emits a subtle selection haptic

#### Scenario: Focused Start waits for keyboard dismissal
- **WHEN** the user activates Start while the name field is focused
- **THEN** the field resigns at once with haptic feedback and tap-time `started_at`, and the running swap fires only after the keyboard finishes dismissing (bounded fallback when no dismissal notifies)

#### Scenario: Deferred start cancels on edit
- **WHEN** the user edits the field or taps a chip after a focused Start tap but before the swap fires
- **THEN** the deferred start is cancelled and no timer starts with the stale draft

#### Scenario: Start after a post-stop edit starts on the first tap
- **WHEN** the user edits the name after a stop (the committed preparation is stale for the field's current text) and activates Start with the field focused
- **THEN** the timer starts on that first tap with the field's current text once the keyboard dismisses; no second tap is needed

#### Scenario: Running swap renders instantly
- **WHEN** the running swap fires
- **THEN** Stop appears in place with no fade, slide, or spring of its own; the keyboard's own slide moves the whole layout together

### Requirement: Stop saves with stable feedback
Stopping a running timer SHALL save the completed entry locally, communicate success without a blocking loader, and retain the entered text in the ready state for an optional later restart. While the saved confirmation is showing, the Start button SHALL render disabled (dimmed, non-interactive) since starting is not possible until the state settles back to ready; it SHALL re-enable with the return to ready. Editing the name while the saved confirmation is showing SHALL return to ready for the new text at once, ending the confirmation early. When the persisted running draft is gone but Track still holds a `.running` state (the timer was stopped from the compact timer on another destination), Track SHALL reconcile on next load: stop the elapsed ticker, re-enable the idle timer, reset elapsed to zero, and return to `.ready` for the same text — or `.idle` when nothing was entered — instead of counting elapsed time forever.

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

#### Scenario: Edit during the saved confirmation returns to ready
- **WHEN** the user edits the name while the saved confirmation is showing
- **THEN** the screen returns to ready for the new text at once, ending the confirmation early instead of waiting out the window
