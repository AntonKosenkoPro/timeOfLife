## MODIFIED Requirements

### Requirement: Category deletion is undoable until the app restarts

A confirmed category deletion SHALL remain restorable until the earlier of a successful relay push of its `DELETE` (push-then-commit) or the next app restart — there is no wall-clock undo window. The category editor (edit mode) SHALL offer the destructive Delete action at the bottom of the form; confirming the destructive confirmation (which names the category and explains that Activity tags will be removed while entries remain available, with timeless undo copy — "You can shake to undo." and no lifetime bound) SHALL enter the durable undo buffer, dismiss the editor, and refresh the list. The entry-delete confirmation SHALL carry the same timeless undo copy. Until the buffer row commits, the Manage Categories surface SHALL offer restore through the DEFAULT system Undo confirmation only: shaking the device surfaces the system Undo prompt, and confirming restores exactly one deletion — the most recent buffered one. No UndoToast SHALL be shown. No deletion SHALL be sent to the relay while it is buffered. Undo SHALL restore the same category identity, values, and Activity assignments.

#### Scenario: Undo from the visible affordance

- **WHEN** the user activates Undo from the system Undo confirmation before the buffered deletion commits (no restart and no successful push of its `DELETE`)
- **THEN** the category and all prior Activity assignments are restored and no deletion is synchronized

#### Scenario: Undo through the system gesture

- **WHEN** the user invokes the system Undo gesture on Manage Categories (before the buffered deletion commits) and confirms
- **THEN** the most recent eligible category deletion is restored

#### Scenario: Restart commits buffered deletions

- **WHEN** the app restarts with a buffered category deletion
- **THEN** the deletion becomes final locally on cold launch and is queued for relay synchronization

#### Scenario: Successful push commits the buffered deletion

- **WHEN** a sync cycle successfully pushes the buffered deletion's `DELETE` for every snapshotted record
- **THEN** the buffer row is dropped and a later undo finds nothing to restore

#### Scenario: Backgrounding does not expire the buffer

- **WHEN** the app leaves the foreground with a buffered deletion and returns (without restarting and without a successful push of its `DELETE`)
- **THEN** the deletion is still restorable; nothing is finalized on any time boundary

#### Scenario: Delete confirmations carry timeless undo copy

- **WHEN** the user opens the entry-delete or category-delete confirmation in English or Russian
- **THEN** the undo sentence states only that shake-to-undo is available ("You can shake to undo." / "Отменить можно встряской.") with no sync, restart, or time bound

#### Scenario: Cancel category deletion

- **WHEN** the user cancels the destructive confirmation
- **THEN** the category and all of its Activity assignments remain unchanged
