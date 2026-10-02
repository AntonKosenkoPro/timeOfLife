## MODIFIED Requirements

### Requirement: Entry delete needs confirmation and enters the undo buffer
EDIT and LOCKED modes SHALL offer a destructive Delete action at the bottom of the form (below the input cards, red destructive styling). Activating it SHALL present a destructive confirmation alert titled "Delete this entry?" with an entry-focused message naming the entry's text (never an activity — no activity entity exists); confirming SHALL remove the entry from all lists immediately, enter the durable undo buffer (full snapshot, no outbox row yet — the relay is never notified of an undone deletion), dismiss the form, and refresh the underlying lists. No UndoToast SHALL be shown in this change. The deletion SHALL stay restorable through the DEFAULT system Undo confirmation until the app restarts (no wall-clock window): shaking the device surfaces the system Undo prompt, and confirming restores exactly one entry — the most recent buffered deletion (the registration is cleared-then-single, so one shake+confirm can never restore two). Cold launch SHALL commit the deletion (outbox delete row) with no restore path afterwards. Only the most recent buffer row SHALL be restorable (supersession, including across surfaces — an entry delete followed by a category delete leaves only the category undoable on this surface). Dismissing the confirm alert SHALL leave the entry and the draft unchanged.

#### Scenario: Confirmed delete removes the entry
- **WHEN** the user confirms deletion of an entry
- **THEN** the form dismisses and History no longer shows the entry

#### Scenario: Delete confirmation cancels cleanly
- **WHEN** the user dismisses the delete confirmation without confirming
- **THEN** the entry is unchanged and the form draft is intact

#### Scenario: Shake offers the system Undo confirmation, confirm restores one entry
- **WHEN** the user shakes the device after confirming an entry deletion while the process is still alive
- **THEN** the system Undo confirmation is offered, and confirming restores the entry with its text and values back into its day group, with nothing synced (one shake+confirm restores at most one deletion — the most recent one)

#### Scenario: Expired deletion commits on foreground
- **WHEN** the buffered deletion is still present at restart (no wall-clock window — restorable until restart)
- **THEN** the deletion commits and syncs as a hard delete with no restore path
