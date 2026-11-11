## MODIFIED Requirements

### Requirement: Running Track offers a recording-only notes button
While a timer is running, the locked name row SHALL be paired with a trailing notes button that opens the shared Notes editor page bound to the running draft. The button SHALL be visible only while recording (running/error states with a persisted draft) and SHALL sit OUTSIDE the locked-name row as a standalone 44 pt `note.text` control at the screen's trailing padding beside the locked-name `FieldCard` — without changing the row height or moving the main action. The button's tint SHALL signal draft-notes presence (accent when non-empty, secondary when empty); no notes preview SHALL appear on Track. Saving on the editor page while recording SHALL rewrite only the running draft notes snapshot (persisted `timer_state`); cancelling SHALL leave the draft untouched. Notes edits SHALL never touch history until Stop.

If Live Activity Stop arrives while this running-notes editor contains changes from its last confirmed notes, the app SHALL retain the edited text without delaying timer completion. Changes SHALL include clearing previous notes and SHALL exclude edits reverted to the confirmed text. Stop SHALL first save the completed entry using the confirmed notes. Only after successful completion SHALL the app explain that the timer has stopped and offer **Save Changes** and **Discard Changes** for the retained text. Save SHALL update only the notes of that exact completed entry, with an ordinary transactional sync update; discard SHALL leave its confirmed notes unchanged. Neither choice SHALL alter the entry's name, ordered categories, start, end, or duration, create a second entry, or restart the timer.

The retained text SHALL remain available across the normal saved-state reset, background/foreground transitions, and recoverable notes-save failures. Starting another run SHALL remain unavailable until this running-notes resolution is completed or invalidated. Implicit prompt dismissal SHALL NOT discard text or undo Stop. Notes validation SHALL retain the existing 2000-scalar bound without truncation and allow correction/retry against the completed entry. A missing/deleted target SHALL NOT be recreated. Account teardown SHALL invalidate the pending session; an old callback SHALL NOT write to another account, store generation, or replacement timer. Unconfirmed text SHALL remain process-local; termination SHALL NOT imply durable recovery. Ordinary running-editor cancel/save behavior and History/manual-entry notes editing SHALL otherwise remain unchanged.

#### Scenario: Notes button visible only while recording
- **WHEN** a timer is running
- **THEN** the locked name row shows the trailing notes button at full tap target

#### Scenario: Notes button hidden when not recording
- **WHEN** Track is idle, ready, or saved (no running draft)
- **THEN** no notes button is shown

#### Scenario: Opening notes mid-run
- **WHEN** the user taps the notes button while running
- **THEN** the Notes editor page pushes prefilled with the current draft notes

#### Scenario: Saving running notes updates the draft only
- **WHEN** the user saves on the editor page while running
- **THEN** the running draft notes update, the persisted snapshot updates, and no entry or history row changes

#### Scenario: Cancelling running notes keeps the draft
- **WHEN** the user cancels on the editor page while running
- **THEN** the page pops and the running draft notes are unchanged

#### Scenario: Dirty running notes are offered only after successful Stop
- **WHEN** Live Activity Stop is handled while the running-notes editor contains unconfirmed text different from its confirmed notes
- **THEN** the entry first completes with its confirmed notes, the edited text remains available, and only then the app offers to save or discard those changes while stating that the timer has stopped

#### Scenario: Saving changes targets only the completed entry
- **WHEN** the user chooses Save Changes with valid retained text after Stop succeeds
- **THEN** that exact completed entry's notes are updated locally and queued for sync, even if its original create has already synced
- **AND** no other field, entry, or running draft changes, and the recorded end time is independent of the decision delay

#### Scenario: Discarding changes retains confirmed notes
- **WHEN** the user chooses Discard Changes after the completed entry was saved with previously confirmed notes
- **THEN** only the unconfirmed edits are abandoned, the entry keeps those confirmed notes, and the timer remains stopped

#### Scenario: Clearing notes is an unconfirmed change
- **WHEN** the user clears non-empty confirmed notes without confirming the edit before Live Activity Stop
- **THEN** the app still offers the post-stop decision, Save Changes clears the completed entry's notes, and Discard Changes preserves its prior confirmed notes

#### Scenario: Clean or already confirmed notes do not prompt
- **WHEN** Live Activity Stop succeeds and the editor text is unchanged, was edited then reverted, or was confirmed with ✓ before Stop
- **THEN** there is no unsaved-notes decision, including when confirmed notes are non-empty

#### Scenario: Stop failure preserves the editor without claiming completion
- **WHEN** the initial Stop cannot successfully save and clear the running draft
- **THEN** the unconfirmed editor text remains available with the existing recoverable error behavior and no post-stop notes decision or false success is presented

#### Scenario: Notes validation or persistence failure retains text
- **WHEN** Save Changes encounters over-limit text or a failed/stale local update
- **THEN** the edited text is not truncated or discarded, the timer stays stopped at its original end time, and correction/retry or explicit discard remains available
- **AND** a missing or deleted target is not recreated and no replacement entry is chosen

#### Scenario: Presentation and lifecycle do not silently discard pending changes
- **WHEN** the saved-state confirmation resets, the prompt is implicitly dismissed, or the app backgrounds and returns while resolution is pending
- **THEN** the text remains available for that same completed entry, starting another run remains unavailable, and resuming the decision does not stop or save the timer again

#### Scenario: Account teardown invalidates deferred actions
- **WHEN** the pending session's account or active-store generation is torn down before a notes action completes
- **THEN** stale actions cannot mutate the new account/store or a replacement run, and no pending notes are shown in another account

#### Scenario: Other notes editing retains its existing behavior
- **WHEN** the user edits notes in History or Log Time, or cancels the running-notes page without an external Stop
- **THEN** the existing copy-on-open save/cancel behavior applies without this post-stop decision

### Requirement: Stop saves with stable local feedback
Stopping a running timer SHALL save the completed entry locally, communicate success without a blocking loader, and retain the entered text in the ready state for an optional later restart. While the saved confirmation is showing, the Start button SHALL render disabled (dimmed, non-interactive) since starting is not possible until the state settles back to ready; it SHALL re-enable with the return to ready unless the running-notes post-stop resolution remains pending. In that scoped case, Start SHALL remain unavailable until the resolution is completed or invalidated; the confirmation's normal reset schedule SHALL NOT be prolonged by the notes decision. Editing the name while the saved confirmation is showing SHALL return to ready for the new text at once, ending the confirmation early, without discarding any pending notes resolution. When the persisted running draft is gone but Track still holds a `.running` state (the timer ended through another existing path, including an external stop), Track SHALL reconcile on next load: stop the elapsed ticker, re-enable the idle timer, reset elapsed to zero, and return to `.ready` for the same text — or `.idle` when nothing was entered — instead of counting elapsed time forever.

#### Scenario: Successful stop
- **WHEN** the user activates Stop on a running timer
- **THEN** the app persists the completed entry, clears running state, emits a success haptic, briefly confirms the saved duration, and returns to the ready numeric timer for the same text

#### Scenario: Save failure
- **WHEN** the local store cannot save the completed entry
- **THEN** the app preserves recoverable running state and presents a localized non-field error without silently losing elapsed time

#### Scenario: External stop reconciles Track
- **WHEN** Track holds a running state whose persisted draft no longer exists because the timer ended through another existing path
- **THEN** Track leaves the running state on next load: the ticker stops, elapsed resets to zero, and the screen shows the ready timer for the same text (or idle when empty)

#### Scenario: Start is disabled during the saved confirmation
- **WHEN** the saved confirmation is showing after a stop
- **THEN** the Start button renders dimmed and ignores taps; it re-enables when the state settles back to ready unless a running-notes post-stop resolution is still pending

#### Scenario: Edit during the saved confirmation returns to ready
- **WHEN** the user edits the name while the saved confirmation is showing
- **THEN** the screen returns to ready for the new text at once, ending the confirmation early instead of waiting out the window, without losing any pending notes resolution

#### Scenario: Notes resolution does not extend the Saved confirmation
- **WHEN** the normal Saved confirmation finishes before the running-notes decision is answered
- **THEN** Track reaches ready on its normal schedule but Start remains unavailable until the notes resolution is completed or invalidated
