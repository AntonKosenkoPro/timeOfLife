## MODIFIED Requirements

### Requirement: Running timer hosts the category TagSelector
While a timer is running, Track SHALL show the shared ordered `TagSelector` (select-only from existing categories, zero allowed, order preserved) below the readout. The name SHALL be locked after Start; tags SHALL stay live until Stop. Toggles SHALL rewrite only the running draft (persisted `timer_state` snapshot) and SHALL never touch history. Notes edits SHALL rewrite only the running draft notes snapshot the same way. Stop SHALL save the entry with the final ordered categories, the final draft notes, and derived duration, plus a single outbox row.

#### Scenario: Toggle tags mid-run
- **WHEN** the user toggles a category while the timer runs
- **THEN** the draft selection updates, the persisted draft snapshot updates, and no entry or history row changes

#### Scenario: Name locked while running
- **WHEN** the timer is running
- **THEN** the name field is non-editable until Stop

#### Scenario: Category-less run allowed
- **WHEN** the user deselects every category mid-run
- **THEN** the run stays valid and Stop saves a category-less entry

#### Scenario: Stop saves final tags
- **WHEN** the user activates Stop
- **THEN** the entry is created with the trimmed locked text, the final ordered categories, the final draft notes, and derived duration, plus a single outbox row

## ADDED Requirements

### Requirement: Running Track offers a recording-only notes button
While a timer is running, the locked name row SHALL be paired with a trailing notes button that opens the shared Notes editor page bound to the running draft. The button SHALL be visible only while recording (running/error states with a persisted draft) and SHALL sit OUTSIDE the locked-name row as a standalone 44 pt `note.text` control at the screen's trailing padding beside the locked-name `FieldCard` — without changing the row height or moving the main action. The button's tint SHALL signal draft-notes presence (accent when non-empty, secondary when empty); no notes preview SHALL appear on Track. Saving on the editor page SHALL rewrite only the running draft notes snapshot (persisted `timer_state`); cancelling SHALL leave the draft untouched. Notes edits SHALL never touch history until Stop.

#### Scenario: Notes button visible only while recording
- **WHEN** a timer is running
- **THEN** the locked name row shows the trailing notes button at full tap target

#### Scenario: Notes button hidden when not recording
- **WHEN** Track is idle, ready, or saved (no running draft)
- **THEN** no notes button is shown

#### Scenario: Opening notes mid-run
- **WHEN** the user taps the notes button while running
- **THEN** the Notes editor page pushes prefilled with the current draft notes

#### Scenario: Saving running notes updates the draft only
- **WHEN** the user saves on the editor page while running
- **THEN** the running draft notes update, the persisted snapshot updates, and no entry or history row changes

#### Scenario: Cancelling running notes keeps the draft
- **WHEN** the user cancels on the editor page while running
- **THEN** the page pops and the running draft notes are unchanged
