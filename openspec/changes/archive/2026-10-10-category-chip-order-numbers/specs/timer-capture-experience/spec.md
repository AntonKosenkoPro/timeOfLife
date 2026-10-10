## MODIFIED Requirements

### Requirement: Running timer hosts the category TagSelector
While a timer is running, Track SHALL show the shared ordered `TagSelector` (select-only from existing categories, zero allowed, order preserved) below the readout. The name SHALL be locked after Start; tags SHALL stay live until Stop. The locked name card SHALL align its text to the leading edge, matching the idle/ready name-row grammar (icon + text pushed leading, never centered). Toggles SHALL rewrite only the running draft (persisted `timer_state` snapshot) and SHALL never touch history. Notes edits SHALL rewrite only the running draft notes snapshot the same way. Stop SHALL save the entry with the final ordered categories, the final draft notes, and derived duration, plus a single outbox row. The running selector SHALL render selection ordinals exactly as defined by the category-management capability (single selection shows a checkmark, multiple selections show 1-based ordinals with fade-animated renumbering) without moving the main action above it.

#### Scenario: Toggle tags mid-run
- **WHEN** the user toggles a category while the timer runs
- **THEN** the draft selection updates, the persisted draft snapshot updates, and no entry or history row changes

#### Scenario: Selection order is visible mid-run
- **WHEN** the user selects a second category while the timer runs
- **THEN** the selected chips show their 1-based ordinals with a fade and the Start/Stop action above keeps its exact frame

#### Scenario: Name locked while running
- **WHEN** the timer is running
- **THEN** the name field is non-editable until Stop

#### Scenario: Locked name aligns leading
- **WHEN** the timer is running and the locked name card shows the draft text
- **THEN** the text renders leading-aligned inside the card, matching the idle/ready name row, regardless of live elapsed-time ticks

#### Scenario: Category-less run allowed
- **WHEN** the user deselects every category mid-run
- **THEN** the run stays valid and Stop saves a category-less entry

#### Scenario: Stop saves final tags
- **WHEN** the user activates Stop
- **THEN** the entry is created with the trimmed locked text, the final ordered categories, the final draft notes, and derived duration, plus a single outbox row
