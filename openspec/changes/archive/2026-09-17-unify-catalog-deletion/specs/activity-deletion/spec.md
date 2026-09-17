## Purpose

Lets users delete an activity and its history from one consistent place — the activity editor — with confirmation, scope disclosure, and shake-to-undo, matching the entry deletion grammar.

## ADDED Requirements

### Requirement: Activity editor offers Delete with scope confirmation

The activity editor (edit mode) SHALL offer a destructive Delete action at the bottom of the form (below the input cards, red destructive styling), mirroring the entry form. Activating it SHALL present a destructive confirmation alert that names the activity and states its scope: the number of committed entries and their total tracked duration (e.g. "Delete *Running* and its 12 entries (3h 20m)? This removes the activity and its history. You can shake to undo until you restart the app."). Confirming SHALL remove the activity, its category assignments, and all its committed entries from all lists immediately, enter the durable undo buffer (full snapshot, no outbox row yet), dismiss the editor, and refresh the underlying surfaces. Dismissing the confirm alert SHALL leave the activity and the draft unchanged. The activity detail sheet itself SHALL offer no Delete action; the editor is the single deletion chokepoint for activities.

#### Scenario: Confirmed delete removes the activity and its entries

- **WHEN** the user confirms deletion of activity "Running" with committed entries
- **THEN** the editor dismisses, the activity is gone from Track search and recents, its entries are gone from History and the activity detail sheet, and totals are recomputed

#### Scenario: Delete confirmation cancels cleanly

- **WHEN** the user dismisses the delete confirmation without confirming
- **THEN** the activity, its entries, and the editor draft are unchanged

#### Scenario: Confirmation discloses scope

- **WHEN** the user activates Delete for an activity with committed entries
- **THEN** the confirmation names the activity and states the entry count and total duration before confirming

#### Scenario: No delete on the detail sheet

- **WHEN** the user views the activity detail sheet
- **THEN** no Delete action is offered there; deletion is reached only via "Edit activity"

### Requirement: Activity delete is blocked while its timer runs

Confirming deletion of the activity a timer is currently running against SHALL NOT delete anything: the editor stays open with the draft intact and shows a localized message explaining the running timer must be stopped first. The running `timer_state` SHALL never dangle referencing a deleted activity.

#### Scenario: Delete blocked for the running activity

- **WHEN** the user confirms deletion of the activity with the running timer
- **THEN** nothing is deleted, the editor stays open, and a localized message names the running timer as the blocker

### Requirement: Activity deletion is undoable through the system Undo confirmation

A buffered deletion SHALL stay restorable until the app restarts — there is no wall-clock window. Until then the deletion SHALL be restorable through the DEFAULT system Undo confirmation: shaking the device on the presenting surface surfaces the system Undo prompt, and confirming restores exactly one deletion — the most recent buffered one (the registration is cleared-then-single, so one shake+confirm can never restore two). Undo SHALL restore the same activity identity, values, category assignments, and all snapshotted entries; nothing is synced. No UndoToast SHALL be shown. An app restart SHALL commit every still-buffered deletion (outbox delete rows) on cold launch via the global reconciliation, never while the process is alive (foreground/background cycles expire nothing). Only the most recent buffer row SHALL be restorable (U7 supersession, including across surfaces — an activity delete followed by an entry delete leaves only the entry undoable on entry surfaces, and vice versa; the older row stays buffered until it is undone or the app restarts).

#### Scenario: Shake offers the system Undo confirmation, confirm restores activity and entries

- **WHEN** the user shakes the device after confirming an activity deletion (before restarting the app) and confirms the system prompt
- **THEN** the activity returns with its identity, values, category assignments, and entries, with nothing synced (one shake+confirm restores at most one deletion — the most recent one)

#### Scenario: Restart commits buffered deletions on cold launch

- **WHEN** the app restarts with buffered deletions (including across suspension or kill)
- **THEN** every buffered deletion commits on cold launch and syncs as hard deletes with no restore path

#### Scenario: Supersession across surfaces

- **WHEN** the user confirms an activity deletion and then an entry deletion
- **THEN** only the entry deletion is restorable via shake-to-undo; the activity deletion stays buffered until it becomes the most recent again or the app restarts

### Requirement: Presenters settle after activity deletion

Deleting the activity shown in the activity detail sheet (via its stacked editor) SHALL dismiss the detail sheet, since the sheet never shows an activity that no longer exists. Deleting the activity selected on Track SHALL clear the Track selection back to its idle state. Deleting any activity SHALL remove its entries from the History list.

#### Scenario: Detail sheet dismisses after its activity is deleted

- **WHEN** the user deletes the activity open in the detail sheet from the stacked editor
- **THEN** the editor dismisses and the detail sheet dismisses, returning to History without that activity's entries

#### Scenario: Track selection clears after its activity is deleted

- **WHEN** the user deletes the activity currently selected on Track from the refine editor
- **THEN** the editor dismisses and Track returns to its idle preparation state with no activity selected

### Requirement: Activity deletion is localized and accessible

All activity-deletion copy SHALL be available in English and Russian, the Delete button and confirmation SHALL expose stable accessibility identifiers, and the Delete button SHALL meet the 44×44 minimum tap target and use Theme semantic colors only (red destructive styling).

#### Scenario: Russian localization is active

- **WHEN** the app runs in Russian
- **THEN** the activity Delete button, scope confirmation, running-timer block message, and undo copy appear in Russian

#### Scenario: VoiceOver reaches Delete

- **WHEN** VoiceOver navigates the activity editor
- **THEN** it announces the Delete action and the confirmation options without relying on color alone
