## MODIFIED Requirements

### Requirement: Category management is localized and accessible
All category-management copy SHALL be available in English and Russian, all interactive controls SHALL expose stable accessibility identifiers and meaningful labels, and category icons SHALL include the category name as accessible context rather than relying on the symbol alone. Interactive category controls SHALL expose a tap target of at least 44×44 points, and category chip selection SHALL be indicated by a visible ordinal-or-check affordance rather than color alone: a single selected chip shows a checkmark, while two or more selected chips each show their 1-based selection ordinal.

#### Scenario: VoiceOver navigates Manage Categories
- **WHEN** VoiceOver focuses a category row or editor icon option
- **THEN** it announces the category or icon meaning and the available action without requiring visual interpretation of the symbol

#### Scenario: Russian localization is active
- **WHEN** the app runs in Russian
- **THEN** category management, validation, confirmation, error, empty-state, and undo copy appears in Russian

#### Scenario: Chip selection is visible without color
- **WHEN** exactly one category chip in the entry form or running timer selector is selected
- **THEN** the chip shows a checkmark in place of the category icon while unselected chips show their icon, so the selected state remains perceivable without relying on color

#### Scenario: Multiple chip selection shows order without color
- **WHEN** two or more category chips in the entry form or running timer selector are selected
- **THEN** every selected chip shows its 1-based selection ordinal in place of the category icon or checkmark while unselected chips show their icon, so both the selected state and the selection order remain perceivable without relying on color

#### Scenario: VoiceOver announces chip selection order
- **WHEN** VoiceOver focuses a selected category chip while two or more chips are selected
- **THEN** it announces the category name, the selected state, and the chip's ordinal position (e.g. selected, 2 of 3) in the active locale

#### Scenario: Category chips meet minimum touch targets
- **WHEN** the Activity editor renders the category selector
- **THEN** every chip's interactive area is at least 44×44 points

### Requirement: Entries support optional multiple category assignments
The unified entry form and the running timer's `TagSelector` SHALL display the available category catalog and allow zero, one, or multiple categories per entry with order preserved. Saving SHALL persist that entry's ordered category set. Category assignment SHALL remain optional. There is no activity entity and no Activity editor — category chips live on entry forms and the running timer only. Recents chips SHALL display only the icon of the first category of each exact text's newest entry and SHALL NOT display category names. Whenever two or more categories are selected, each selected chip SHALL display its 1-based position in the selection order (tap order; deselect-then-reselect appends at the end); deselecting any chip SHALL renumber the remaining selected chips to the dense sequence 1…n. Ordinal presentation SHALL cap at 99 (a third digit is impossible). Ordinal changes (select, deselect, renumber, checkmark↔ordinal swap) SHALL animate with a fade. Selecting or deselecting chips SHALL NOT change chip geometry: the ordinal glyph fits the existing fixed symbol slot (two-digit ordinals shrink to fit) so surrounding rows never re-pack.

#### Scenario: Assign multiple categories
- **WHEN** the user selects two or more categories for an entry and saves
- **THEN** the entry is associated with every selected category in the chosen order

#### Scenario: Selection order is visible on chips
- **WHEN** the user selects a second category (tap order C then A)
- **THEN** the first-tapped chip shows 1 and the second-tapped chip shows 2, and the previously single-selected chip swaps its checkmark for its ordinal with a fade

#### Scenario: Deselecting renumbers remaining chips
- **WHEN** the user deselects a selected chip while two or more others stay selected
- **THEN** the remaining selected chips renumber to the dense sequence 1…n preserving their relative tap order, with a fade

#### Scenario: Returning to one selection restores the checkmark
- **WHEN** deselecting leaves exactly one category selected
- **THEN** the remaining chip swaps its ordinal back to the checkmark with a fade

#### Scenario: Remove one assignment
- **WHEN** the user deselects one category while leaving others selected and saves
- **THEN** only the deselected association is removed

#### Scenario: Clear all assignments
- **WHEN** the user deselects every category and saves
- **THEN** the entry remains valid with no categories

#### Scenario: Selection does not move surrounding layout
- **WHEN** the user selects or deselects categories (including reaching a two-digit ordinal count)
- **THEN** chip positions, row wrapping, and everything above the selector stay pixel-identical apart from the glyph/fill change itself

#### Scenario: Assignment save fails
- **WHEN** the entry and its selected category set cannot be committed together
- **THEN** neither the entry fields nor its persisted category set changes and the draft remains available for retry

#### Scenario: Capture inherits but never requires
- **WHEN** the user starts a timer or opens the entry form
- **THEN** no category is required, no category name appears except on Recents icons, and inherited categories remain fully editable

#### Scenario: Categoryless entry chip has no icon
- **WHEN** a Recents chip's newest entry has no categories
- **THEN** the chip renders with the exact text and no icon
