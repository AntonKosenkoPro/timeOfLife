## Purpose

Defines a local-first category catalog that users can manage from Profile and apply as optional, reusable tags to one or more Activities.

## ADDED Requirements

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
The system SHALL provide a Categories destination from Profile to all users, regardless of account or connectivity state. It SHALL list categories alphabetically by localized name and allow the user to add, edit, and initiate deletion of categories. An empty catalog SHALL show guidance for creating a category and SHALL NOT block Activity creation or timing.

#### Scenario: Open categories while signed out and offline
- **WHEN** a signed-out user opens Profile and activates Categories without connectivity
- **THEN** the Manage Categories surface opens from local data with create, edit, and delete controls available

#### Scenario: Edit an existing category
- **WHEN** the user selects a category from the list
- **THEN** an editor opens with the category's current name and icon prefilled

#### Scenario: Add a category
- **WHEN** the user activates Add from Manage Categories
- **THEN** a category editor opens with an empty name and the default `tag` icon selected

#### Scenario: Catalog is empty
- **WHEN** Manage Categories contains no category records
- **THEN** it shows a localized empty state that guides the user to Add while other app features remain usable

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

### Requirement: Category deletion preserves Activities and entries
Deleting a category SHALL remove that category from every associated Activity but SHALL NOT delete or otherwise modify any Activity, entry, or timer state. Before deletion, the system SHALL present a destructive confirmation that names the category and explains that Activity tags will be removed while entries remain available.

#### Scenario: Delete an assigned category
- **WHEN** the user confirms deletion of a category assigned to one or more Activities
- **THEN** the category disappears from the catalog and those Activities, while the Activities, their entries, and timer state remain intact

#### Scenario: Cancel category deletion
- **WHEN** the user cancels the destructive confirmation
- **THEN** the category and all of its Activity assignments remain unchanged

### Requirement: Category deletion is undoable for 30 seconds
A confirmed category deletion SHALL remain restorable for a wall-clock 30-second undo window. During that window, the Manage Categories surface SHALL offer Undo and the system Undo gesture SHALL target the most recent eligible deletion. No deletion SHALL be sent to the relay before the window expires. Undo SHALL restore the same category identity, values, and Activity assignments.

#### Scenario: Undo from the visible affordance
- **WHEN** the user activates Undo before the 30-second window expires
- **THEN** the category and all prior Activity assignments are restored and no deletion is synchronized

#### Scenario: Undo through the system gesture
- **WHEN** the user invokes the system Undo gesture on Manage Categories before the window expires
- **THEN** the most recent eligible category deletion is restored

#### Scenario: Undo window expires
- **WHEN** 30 wall-clock seconds pass without undo
- **THEN** the deletion becomes final locally and is queued for relay synchronization

#### Scenario: Window expires while backgrounded
- **WHEN** the app leaves the foreground during the undo window and returns after it expired
- **THEN** the deletion is finalized on foreground without relying on background execution

### Requirement: Activities support optional multiple category assignments
The shared Activity editor SHALL display the available category catalog and allow zero, one, or multiple categories to be assigned to an Activity. Saving SHALL replace that Activity's category set as part of the same committed Activity edit. Category assignment SHALL remain optional and SHALL NOT be shown in Track search results or recency suggestions.

#### Scenario: Assign multiple categories
- **WHEN** the user selects two or more categories in an Activity editor and saves
- **THEN** the Activity is associated with every selected category and the saved editor state reflects all selections

#### Scenario: Remove one assignment
- **WHEN** the user deselects one category while leaving others selected and saves
- **THEN** only the deselected association is removed

#### Scenario: Clear all assignments
- **WHEN** the user deselects every category and saves
- **THEN** the Activity remains valid with no categories and can still be prepared and timed

#### Scenario: Assignment save fails
- **WHEN** the Activity and its selected category set cannot be committed together
- **THEN** neither the Activity fields nor its persisted category set changes and the editor draft remains available for retry

#### Scenario: Capture remains category-free
- **WHEN** the user browses Track search results or recency suggestions
- **THEN** no category is required or displayed as part of selecting or quick-creating an Activity

### Requirement: Current assignments classify Activity history
Entries SHALL continue to reference their Activity rather than store a category snapshot. Any category representation of an entry SHALL resolve the Activity's current category set, so assignment edits reclassify existing history without rewriting entries.

#### Scenario: Add a category to an Activity with history
- **WHEN** the user adds a category to an Activity that already has entries
- **THEN** subsequent history or insights queries classify those entries under the Activity's updated category set

#### Scenario: Delete an assigned category
- **WHEN** an assigned category is deleted
- **THEN** existing entries cease to resolve that category while retaining their Activity and timing data

### Requirement: Category changes are local-first and synchronizable
Starter creation, category CRUD, deletion finalization, and Activity-category assignment changes SHALL commit to the local source of truth without requiring an account or network. When sync is active, category records and complete Activity category sets SHALL converge through the optional relay using the existing idempotent creation, last-write-wins update, and name-collision rules.

#### Scenario: Manage categories offline
- **WHEN** the user creates, edits, deletes, or assigns categories without connectivity
- **THEN** each successful action is immediately reflected locally and retained for later synchronization

#### Scenario: Synchronize category assignments
- **WHEN** an offline Activity-category edit later synchronizes successfully
- **THEN** another signed-in device receives the complete current category set for that Activity

#### Scenario: Cross-device category name collision
- **WHEN** two devices create categories with equivalent normalized names and the relay selects one winning identity
- **THEN** local Activity references are remapped to the winning category, the winning category is available locally, and no Activity or entry is lost

#### Scenario: Remote category deletion arrives
- **WHEN** a finalized category deletion from another device is received through synchronization
- **THEN** the category and its local Activity associations are removed while Activities and entries remain intact

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
