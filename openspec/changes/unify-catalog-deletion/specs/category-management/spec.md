## MODIFIED Requirements

### Requirement: Profile owns category management

The system SHALL provide a Categories destination from Profile to all users, regardless of account or connectivity state. It SHALL list categories alphabetically by localized name and allow the user to add and edit categories; deletion SHALL be initiated only from the category editor's Delete button — the list itself SHALL offer no swipe, context-menu, or other delete affordance. An empty catalog SHALL show guidance for creating a category and SHALL NOT block Activity creation or timing.

#### Scenario: Open categories while signed out and offline

- **WHEN** a signed-out user opens Profile and activates Categories without connectivity
- **THEN** the Manage Categories surface opens from local data with create and edit controls available, and deletion is reached through the editor

#### Scenario: Edit an existing category

- **WHEN** the user selects a category from the list
- **THEN** an editor opens with the category's current name and icon prefilled, offering Delete alongside Save

#### Scenario: Add a category

- **WHEN** the user activates Add from Manage Categories
- **THEN** a category editor opens with an empty name and the default `tag` icon selected, with no Delete action (create mode)

#### Scenario: Catalog is empty

- **WHEN** Manage Categories contains no category records
- **THEN** it shows a localized empty state that guides the user to Add while other app features remain usable

#### Scenario: List offers no direct deletion

- **WHEN** the user swipes a category row or long-presses it
- **THEN** no delete affordance appears; the row opens the editor, where Delete lives

### Requirement: Category deletion is undoable until the app restarts

A confirmed category deletion SHALL remain restorable until the app restarts — there is no wall-clock undo window. The category editor (edit mode) SHALL offer the destructive Delete action at the bottom of the form; confirming the destructive confirmation (which names the category and explains that Activity tags will be removed while entries remain available) SHALL enter the durable undo buffer, dismiss the editor, and refresh the list. Until a restart, the Manage Categories surface SHALL offer restore through the DEFAULT system Undo confirmation only: shaking the device surfaces the system Undo prompt, and confirming restores exactly one deletion — the most recent buffered one. No UndoToast SHALL be shown. No deletion SHALL be sent to the relay while it is buffered. Undo SHALL restore the same category identity, values, and Activity assignments.

#### Scenario: Undo from the visible affordance

- **WHEN** the user activates Undo from the system Undo confirmation before restarting the app
- **THEN** the category and all prior Activity assignments are restored and no deletion is synchronized

#### Scenario: Undo through the system gesture

- **WHEN** the user invokes the system Undo gesture on Manage Categories (before restarting the app) and confirms
- **THEN** the most recent eligible category deletion is restored

#### Scenario: Restart commits buffered deletions

- **WHEN** the app restarts with a buffered category deletion
- **THEN** the deletion becomes final locally on cold launch and is queued for relay synchronization

#### Scenario: Backgrounding does not expire the buffer

- **WHEN** the app leaves the foreground with a buffered deletion and returns (without restarting)
- **THEN** the deletion is still restorable; nothing is finalized without an app restart

#### Scenario: Cancel category deletion

- **WHEN** the user cancels the destructive confirmation
- **THEN** the category and all of its Activity assignments remain unchanged
