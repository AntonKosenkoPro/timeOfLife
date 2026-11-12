## MODIFIED Requirements

### Requirement: Running Track offers a recording-only notes button
While a timer is running, the locked name row SHALL be paired with a trailing notes button that opens the shared Notes editor page bound to the running draft. The button SHALL be visible only while recording (running/error states with a persisted draft) and SHALL sit OUTSIDE the locked-name row as a standalone 44 pt `note.text` control at the screen's trailing padding beside the locked-name `FieldCard` — without changing the row height or moving the main action. The button's tint SHALL signal draft-notes presence (accent when non-empty, secondary when empty); no notes preview SHALL appear on Track. Saving on the editor page while recording SHALL rewrite only the running draft notes snapshot (persisted `timer_state`); cancelling SHALL leave the draft untouched. Notes edits SHALL never touch history until Stop.

If Live Activity Stop arrives while this running-notes editor contains changes from its last confirmed notes, the app SHALL retain the edited text without delaying timer completion. Changes SHALL include clearing previous notes and SHALL exclude edits reverted to the confirmed text. Stop SHALL first save the completed entry using the confirmed notes. Only after successful completion SHALL the app explain that the timer has stopped and offer **Review Notes** and **Discard Changes** for the retained text. Review SHALL show the retained, editable text without validating or writing it. Only ✓ in that editor SHALL validate and save the reviewed notes to that exact completed entry, with an ordinary transactional sync update. X or normal back navigation from review, or Discard Changes in the prompt, SHALL abandon the unconfirmed edits and leave the entry's confirmed notes unchanged. Reviewing, saving, or discarding SHALL NOT alter the entry's name, ordered categories, start, end, or duration, create a second entry, or restart the timer.

Discard Changes SHALL use the native destructive role and its system-red presentation. Action placement and adaptive layout SHALL follow Apple's Human Interface Guidelines and native alert conventions, including layout direction and accessibility text sizing. The implementation SHALL NOT impose a fixed left/right position or replace the native alert to force custom action ordering.

The retained text SHALL remain available across the normal saved-state reset, background/foreground transitions, and recoverable notes-save failures. Starting another run through Track SHALL remain inaccessible while the post-stop alert or its notes review editor is presented, relying only on existing alert modality and notes-editor navigation. The implementation MUST NOT introduce additional Start-disable flags, start guards, locks, timer-state transitions, or custom gesture/navigation interception solely to enforce this UI outcome. Existing Saved-confirmation timing and Start-button enablement SHALL remain unchanged. Implicit prompt dismissal SHALL NOT discard text or undo Stop. The review editor SHALL reuse the existing 2000-scalar bound and validation on ✓ without truncation, allowing correction/retry against the completed entry rather than introducing a separate prompt-save path. A missing/deleted target SHALL NOT be recreated. Account teardown SHALL invalidate the pending session; an old callback SHALL NOT write to another account, store generation, or replacement timer. Unconfirmed text SHALL remain process-local; termination SHALL NOT imply durable recovery. Ordinary running-editor cancel/save behavior and History/manual-entry notes editing SHALL otherwise remain unchanged.

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
- **THEN** the entry first completes with its confirmed notes, the edited text remains available, and only then the app offers Review Notes or Discard Changes while stating that the timer has stopped

#### Scenario: Review opens retained text without saving
- **WHEN** the user chooses Review Notes after Stop succeeds
- **THEN** the editor shows the unconfirmed text for review and further editing, no notes are validated or written by opening review, and the timer remains stopped

#### Scenario: Confirming reviewed notes targets only the completed entry
- **WHEN** the user taps ✓ with valid text in the post-stop review editor
- **THEN** that exact completed entry's notes are updated locally and queued for sync, even if its original create has already synced
- **AND** no other field, entry, or running draft changes, and the recorded end time is independent of the decision delay

#### Scenario: Discarding changes retains confirmed notes
- **WHEN** the user chooses Discard Changes after the completed entry was saved with previously confirmed notes
- **THEN** only the unconfirmed edits are abandoned, the entry keeps those confirmed notes, and the timer remains stopped

#### Scenario: Discard is visibly destructive with platform-standard placement
- **WHEN** the post-stop notes alert presents its actions
- **THEN** Discard Changes uses the native destructive/system-red presentation, Review Notes is non-destructive, and placement follows HIG/native conventions without a fixed left/right override
- **AND** localized labels, layout direction, and larger text retain the native adaptive layout without losing the destructive semantics

#### Scenario: Leaving review discards only unconfirmed changes
- **WHEN** the user taps X or uses normal back navigation from the post-stop review editor
- **THEN** the reviewed changes are discarded, the completed entry keeps its previously confirmed notes, and Track returns without restarting the timer

#### Scenario: Clearing notes is an unconfirmed change
- **WHEN** the user clears non-empty confirmed notes without confirming the edit before Live Activity Stop
- **THEN** the app still offers the post-stop decision, reviewing then confirming the empty text with ✓ clears the completed entry's notes, and discarding preserves its prior confirmed notes

#### Scenario: Clean or already confirmed notes do not prompt
- **WHEN** Live Activity Stop succeeds and the editor text is unchanged, was edited then reverted, or was confirmed with ✓ before Stop
- **THEN** there is no unsaved-notes decision, including when confirmed notes are non-empty

#### Scenario: Stop failure preserves the editor without claiming completion
- **WHEN** the initial Stop cannot successfully save and clear the running draft
- **THEN** the unconfirmed editor text remains available with the existing recoverable error behavior and no post-stop notes decision or false success is presented

#### Scenario: Review reuses existing notes validation and retains failed saves
- **WHEN** ✓ in the post-stop review editor encounters over-limit text or a failed/stale local update
- **THEN** the existing editor validation applies, the edited text is not truncated or discarded, the timer stays stopped at its original end time, and correction/retry via ✓ or explicit discard via X/back remains available
- **AND** a missing or deleted target is not recreated and no replacement entry is chosen

#### Scenario: Presentation and lifecycle do not silently discard pending changes
- **WHEN** the saved-state confirmation resets, the prompt is implicitly dismissed, or the app backgrounds and returns while resolution is pending
- **THEN** the text remains available for that same completed entry, ordinary alert/editor presentation boundaries apply without an additional Start lock, and resuming the decision does not stop or save the timer again

#### Scenario: Existing presentation provides the Start restriction
- **WHEN** the post-stop alert or its notes review editor is presented over Track
- **THEN** Start is inaccessible through the normal modal/navigation UI, without additional Start-disable state, guards, locks, or timer-state transitions
- **AND** the underlying Saved confirmation and Start-button enablement follow their existing behavior rather than waiting for notes resolution

#### Scenario: Account teardown invalidates deferred actions
- **WHEN** the pending session's account or active-store generation is torn down before a notes action completes
- **THEN** stale actions cannot mutate the new account/store or a replacement run, and no pending notes are shown in another account

#### Scenario: Other notes editing retains its existing behavior
- **WHEN** the user edits notes in History or Log Time, or cancels the running-notes page without an external Stop
- **THEN** the existing copy-on-open save/cancel behavior applies without this post-stop decision
