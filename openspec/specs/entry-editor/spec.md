# Entry Editor Specification

## Purpose

Lets users correct and remove logged time with one shared surface: the entry form used for manual creation also edits a committed entry's activity and interval, or deletes it with confirmation and shake-to-undo — while imported entries stay read-only except for delete.

## Requirements

### Requirement: Unified entry form with CREATE, EDIT, and LOCKED modes
The app SHALL provide a single entry form with three modes sharing one Calendar-grammar layout (Activity row opening the shared searchable activity picker; Starts and Ends rows with date + time pills and inline single-open pickers; device locale and calendar) and one validity gate (the confirm action is enabled only when an activity is chosen AND the end is strictly after the start; otherwise disabled with no error text). CREATE mode SHALL behave per the manual-entry capability (Log Time copy, Cancel/Add, sheet presentation). EDIT mode SHALL be titled "Edit entry" (localized) with Cancel/Save actions in the navigation bar. LOCKED mode SHALL show the entry read-only with a Cancel action and no confirm action. The form SHALL use Theme semantic colors only, with all user-facing strings localized (EN + RU).

#### Scenario: Edit mode titles and actions
- **WHEN** the form opens for an existing `manual` entry
- **THEN** the title reads "Edit entry" (localized) with Cancel and Save actions — the same Activity/Starts/Ends layout as creation

#### Scenario: Validity gate applies in edit mode
- **WHEN** the form holds an end equal to or before the start in EDIT mode
- **THEN** Save is disabled with no error text, matching creation behavior

#### Scenario: Locked mode titles and actions
- **WHEN** the form opens for an entry with a non-`manual` source
- **THEN** the title identifies the entry as imported with a Cancel action and no Save action

### Requirement: EDIT mode saves through last-write-wins update
EDIT mode SHALL prefill the Activity row and Starts/Ends pills from the entry. Activating Save on a valid form SHALL persist the changes through the local store's last-write-wins entry update (bumping `updated_at`, enqueuing the sync outbox row in the same transaction), dismiss the form, and refresh the underlying lists so the entry appears with its new values in the correct day group. Overlapping entries and future end-times SHALL be allowed, matching creation. Reassigning the activity SHALL move the entry to the new activity. When the record changed underneath (stale write), the app SHALL show a localized error with the draft intact and the form open.

#### Scenario: Successful edit
- **WHEN** the user changes the end time of a `manual` entry and activates Save
- **THEN** the form dismisses and the entry shows the new interval and derived duration in its day group

#### Scenario: Stale write keeps the draft
- **WHEN** Save loses the last-write-wins race (the entry changed underneath, e.g. by sync)
- **THEN** a localized error is shown, the draft is preserved, and the form stays open

#### Scenario: Reassignment moves the entry
- **WHEN** the user reassigns an entry to another activity and saves
- **THEN** the entry leaves the previous activity's list and appears under the new activity

#### Scenario: Overlap is allowed in edit mode
- **WHEN** the edited interval overlaps another entry
- **THEN** Save stays enabled and saving succeeds

### Requirement: Entry delete needs confirmation and enters the undo buffer
EDIT and LOCKED modes SHALL offer a destructive Delete action at the bottom of the form (below the input cards, red destructive styling). Activating it SHALL present a destructive confirmation alert titled "Delete this entry?" with an entry-focused message naming no activity (naming the activity reads as deleting the activity); confirming SHALL remove the entry from all lists immediately, enter the durable undo buffer (full snapshot, no outbox row yet — the relay is never notified of an undone deletion), dismiss the form, and refresh the underlying lists. No UndoToast SHALL be shown in this change. Within the 30 s wall-clock window the deletion SHALL be restorable through the DEFAULT system Undo confirmation: shaking the device surfaces the system Undo prompt, and confirming restores exactly one entry — the most recent buffered deletion (the registration is cleared-then-single, so one shake+confirm can never restore two). Expiry SHALL commit the deletion (outbox delete row) on the next foreground via the existing global reconciliation, never in the background. Only the most recent buffer row SHALL be restorable (U7 supersession, including across surfaces — an entry delete followed by a category delete leaves only the category undoable on this surface). Dismissing the confirm alert SHALL leave the entry and the draft unchanged.

#### Scenario: Confirmed delete removes the entry
- **WHEN** the user confirms deletion of an entry
- **THEN** the form dismisses and the entry is gone from the activity detail list, its total is recomputed, and History no longer shows it

#### Scenario: Delete confirmation cancels cleanly
- **WHEN** the user dismisses the delete confirmation without confirming
- **THEN** the entry is unchanged and the form draft is intact

#### Scenario: Shake offers the system Undo confirmation, confirm restores one entry
- **WHEN** the user shakes the device within 30 s of confirming an entry deletion
- **THEN** the system Undo confirmation is offered, and confirming restores the entry with its identity and values back into its day group, with nothing synced (one shake+confirm restores at most one deletion — the most recent one)

#### Scenario: Expired deletion commits on foreground
- **WHEN** the 30 s window elapses (including across suspension, kill, or cold launch) and the app foregrounds
- **THEN** the deletion commits and syncs as a hard delete with no restore path

### Requirement: Imported entries are read-only except delete
Entries with a non-`manual` source SHALL open in LOCKED mode: the Activity row, Starts/Ends pills, and pickers SHALL be disabled (dimmed, non-interactive) and no Save action SHALL be present. The form SHALL show a read-only provenance note with the localized source name explaining that editing is disabled to avoid conflicts with the external source of truth. Delete (with confirmation, into the undo buffer) SHALL remain available in LOCKED mode.

#### Scenario: Locked controls cannot be changed
- **WHEN** the form opens for an entry with `source='garmin'`
- **THEN** Activity, Starts, and Ends are disabled and dimmed, no Save is offered, and a note names the source and states editing is disabled

#### Scenario: Imported entry can still be deleted
- **WHEN** the user deletes an imported entry and confirms
- **THEN** the entry enters the undo buffer exactly like a manual entry (restorable by shake within 30 s)
