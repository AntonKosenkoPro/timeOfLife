## MODIFIED Requirements

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

## REMOVED Requirements

### Requirement: Current assignments classify Activity history
**Reason**: Query-time resolution through activities is replaced by per-entry snapshots.
**Migration**: Entries carry their own ordered categories; no reclassification pass exists.
