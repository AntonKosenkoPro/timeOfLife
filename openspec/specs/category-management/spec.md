# Category Management Specification

## Purpose

Defines a local-first category catalog that users can manage from Profile and apply as optional, reusable tags to one or more Activities.
## Requirements

### Requirement: A starter category set is created once
The system SHALL create exactly one starter set for a new local dataset containing Work (`briefcase`), Hobby (`paintbrush`), Sport (`figure.run`), Education (`book`), Relax (`cup.and.saucer`), Sleep (`bed.double`), and Entertainment (`tv`). Starter names SHALL use the app's active supported language when the records are first created. Starter categories SHALL thereafter behave as ordinary user records and SHALL NOT be recreated merely because the user edits or deletes them.

#### Scenario: First launch in English
- **WHEN** a new local dataset is initialized while English is active
- **THEN** the seven starter categories are available with their English names and specified icons before category management or Activity editing is shown

#### Scenario: First launch in Russian
- **WHEN** a new local dataset is initialized while Russian is active
- **THEN** the same seven starter categories are available with localized Russian names and the same specified icons

#### Scenario: Initialization is retried
- **WHEN** starter initialization is attempted again after the starter set was committed
- **THEN** no starter category is duplicated or recreated

#### Scenario: User deletes every starter category
- **WHEN** the user deletes all starter categories and their undo windows expire
- **THEN** the category catalog remains empty until the user creates or synchronizes a category

#### Scenario: App language changes after seeding
- **WHEN** the app language changes after starter categories were created
- **THEN** existing category records retain their current user-editable names and are not silently renamed

### Requirement: Every category has a valid name and icon
Each category SHALL have a name that is non-empty after trimming surrounding whitespace and no longer than 60 characters, and exactly one icon from the supported catalog SF Symbol set. Category names SHALL be unique after trimming and case-insensitive comparison. Invalid input SHALL leave the persisted catalog unchanged and SHALL present one localized error for the affected field.

#### Scenario: Create a valid category
- **WHEN** the user enters a unique valid name, selects a supported icon, and saves
- **THEN** one category is created with the trimmed name and selected icon

#### Scenario: Name is empty
- **WHEN** the user attempts to save a category whose name contains only whitespace
- **THEN** no category is created or updated and a localized name-required error is shown beneath the name field

#### Scenario: Name exceeds the limit
- **WHEN** the user attempts to save a category whose name exceeds 60 characters
- **THEN** no category is created or updated and a localized name-length error is shown beneath the name field

#### Scenario: Name collides by case or whitespace
- **WHEN** the user attempts to create or rename a category to a name that differs from another category only by case or surrounding whitespace
- **THEN** neither category is overwritten or merged and a localized duplicate-name error permits correction

#### Scenario: Icon is unsupported
- **WHEN** a category save carries an icon outside the supported catalog
- **THEN** the save is rejected and the persisted category remains unchanged

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

### Requirement: Category edits are explicit and recoverable
The category editor SHALL preserve its draft until the user saves or cancels. Saving valid changes SHALL update the list and dismiss the editor. A persistence or synchronization-related conflict SHALL preserve or restore actionable user context rather than silently discarding an edit.

#### Scenario: Save succeeds
- **WHEN** the user saves a valid new or edited category
- **THEN** the editor dismisses and Manage Categories displays the persisted result

#### Scenario: User cancels
- **WHEN** the user cancels or dismisses the editor without saving
- **THEN** the persisted category catalog remains unchanged

#### Scenario: Local persistence fails
- **WHEN** a valid category cannot be persisted locally
- **THEN** the editor remains open with its draft intact and a localized error permits retry

#### Scenario: Newer remote edit wins
- **WHEN** synchronization reports that another device has a newer version of the category
- **THEN** the latest version becomes visible and the user receives a non-blocking localized conflict explanation

### Requirement: Category changes are local-first and synchronizable
Starter creation, category CRUD, deletion finalization, and entry-category assignment changes SHALL commit to the local source of truth without requiring an account or network. When sync is active, category records and complete per-entry category sets SHALL converge through the optional relay using the existing idempotent creation, last-write-wins update, and name-collision rules for category records themselves.

#### Scenario: Manage categories offline
- **WHEN** the user creates, edits, deletes, or assigns categories without connectivity
- **THEN** each successful action is immediately reflected locally and retained for later synchronization

#### Scenario: Synchronize category assignments
- **WHEN** an offline per-entry category edit later synchronizes successfully
- **THEN** another signed-in device receives the complete current category set for that entry

#### Scenario: Cross-device category name collision
- **WHEN** two devices create categories with equivalent normalized names and the relay selects one winning identity
- **THEN** local entry references are remapped to the winning category, the winning category is available locally, and no entry is lost

#### Scenario: Remote category deletion arrives
- **WHEN** a finalized category deletion from another device is received through synchronization
- **THEN** the category and its local entry associations are removed while entries remain intact
### Requirement: Category management is localized and accessible
All category-management copy SHALL be available in English and Russian, all interactive controls SHALL expose stable accessibility identifiers and meaningful labels, and category icons SHALL include the category name as accessible context rather than relying on the symbol alone. Interactive category controls SHALL expose a tap target of at least 44×44 points, and category chip selection SHALL be indicated by a visible check affordance rather than color alone.

#### Scenario: VoiceOver navigates Manage Categories
- **WHEN** VoiceOver focuses a category row or editor icon option
- **THEN** it announces the category or icon meaning and the available action without requiring visual interpretation of the symbol

#### Scenario: Russian localization is active
- **WHEN** the app runs in Russian
- **THEN** category management, validation, confirmation, error, empty-state, and undo copy appears in Russian

#### Scenario: Chip selection is visible without color
- **WHEN** a category chip in the Activity editor is selected
- **THEN** the chip shows a checkmark in place of the category icon while unselected chips show their icon, so the selected state remains perceivable without relying on color

#### Scenario: Category chips meet minimum touch targets
- **WHEN** the Activity editor renders the category selector
- **THEN** every chip's interactive area is at least 44×44 points

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

### Requirement: Category deletion preserves entries
Deleting a category SHALL remove that category's joins from every entry but SHALL NOT delete or otherwise modify any entry or timer draft. Before deletion, the system SHALL present a destructive confirmation that names the category and explains that entry tags will be removed while entries remain available.

#### Scenario: Delete an assigned category
- **WHEN** the user confirms deletion of a category assigned to one or more entries
- **THEN** the category disappears from the catalog and those entries, while the entries, their texts, notes, timings, and timer draft remain intact

#### Scenario: Cancel category deletion
- **WHEN** the user cancels the destructive confirmation
- **THEN** the category and all of its entry assignments remain unchanged
### Requirement: Entries support optional multiple category assignments
The unified entry form and the running timer's `TagSelector` SHALL display the available category catalog and allow zero, one, or multiple categories per entry with order preserved. Saving SHALL persist that entry's ordered category set. Category assignment SHALL remain optional. Recents chips SHALL display only the icon of the first category of each exact text's newest entry and SHALL NOT display category names.

#### Scenario: Assign multiple categories
- **WHEN** the user selects two or more categories for an entry and saves
- **THEN** the entry is associated with every selected category in the chosen order

#### Scenario: Remove one assignment
- **WHEN** the user deselects one category while leaving others selected and saves
- **THEN** only the deselected association is removed

#### Scenario: Clear all assignments
- **WHEN** the user deselects every category and saves
- **THEN** the entry remains valid with no categories

#### Scenario: Assignment save fails
- **WHEN** the entry and its selected category set cannot be committed together
- **THEN** neither the entry fields nor its persisted category set changes and the draft remains available for retry

#### Scenario: Capture inherits but never requires
- **WHEN** the user starts a timer or opens the entry form
- **THEN** no category is required, no category name appears except on Recents icons, and inherited categories remain fully editable

#### Scenario: Categoryless entry chip has no icon
- **WHEN** a Recents chip's newest entry has no categories
- **THEN** the chip renders with the exact text and no icon
### Requirement: Each entry snapshots its own categories
Entries SHALL store their own ordered category set at creation. Later category edits on other entries, renames of categories, or retags elsewhere SHALL NOT reclassify existing entries. Deleting a category SHALL strip it from all entries without touching their texts, notes, or timings.

#### Scenario: Retag affects one entry only
- **WHEN** the user changes one entry's categories
- **THEN** no other entry with the same text changes

#### Scenario: Delete an assigned category
- **WHEN** an assigned category is deleted
- **THEN** existing entries cease to list that category while retaining their text, notes, and timing data
