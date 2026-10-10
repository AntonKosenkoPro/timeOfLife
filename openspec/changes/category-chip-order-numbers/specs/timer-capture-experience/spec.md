## MODIFIED Requirements

### Requirement: Running timer hosts the category TagSelector
While a timer is running, Track SHALL show the shared ordered `TagSelector` (select-only from existing categories, zero allowed, order preserved) below the readout. The name SHALL be locked after Start; tags SHALL stay live until Stop. Toggles SHALL rewrite only the running draft (persisted `timer_state` snapshot) and SHALL never touch history. Stop SHALL save the entry with the final ordered categories. The running selector SHALL render selection ordinals exactly as defined by the category-management capability (single selection shows a checkmark, multiple selections show 1-based ordinals with fade-animated renumbering) without moving the main action above it.

#### Scenario: Toggle tags mid-run
- **WHEN** the user toggles a category while the timer runs
- **THEN** the draft selection updates, the persisted draft snapshot updates, and no entry or history row changes

#### Scenario: Selection order is visible mid-run
- **WHEN** the user selects a second category while the timer runs
- **THEN** the selected chips show their 1-based ordinals with a fade and the Start/Stop action above keeps its exact frame

#### Scenario: Name locked while running
- **WHEN** the timer is running
- **THEN** the name field is non-editable until Stop

#### Scenario: Category-less run allowed
- **WHEN** the user deselects every category mid-run
- **THEN** the run stays valid and Stop saves a category-less entry

#### Scenario: Stop saves final tags
- **WHEN** the user activates Stop
- **THEN** the entry is created with the trimmed locked text, the final ordered categories, empty notes, and derived duration, plus a single outbox row
