## MODIFIED Requirements

### Requirement: Entries support optional multiple category assignments
The unified entry form and the running timer's `TagSelector` SHALL display the available category catalog and allow zero, one, or multiple categories per entry with order preserved. Saving SHALL persist that entry's ordered category set. Category assignment SHALL remain optional. There is no activity entity and no Activity editor — category chips live on entry forms and the running timer only. Recents chips SHALL display only the icon of the first category of each exact text's newest entry and SHALL NOT display category names.

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
