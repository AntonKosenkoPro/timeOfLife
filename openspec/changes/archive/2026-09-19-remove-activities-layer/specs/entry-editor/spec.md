## MODIFIED Requirements

### Requirement: Unified entry form with CREATE, EDIT, and LOCKED modes
The app SHALL provide a single entry form with three modes sharing one Calendar-grammar layout (Name plain-text row; Categories ordered TagSelector row; Notes plain-text row; Starts and Ends rows with date + time pills and inline single-open pickers; device locale and calendar) and one validity gate (the confirm action is enabled only when the trimmed name is non-empty AND the end is strictly after the start; otherwise disabled with no error text). CREATE mode SHALL behave per the manual-entry capability (Log Time copy, Cancel/Add, sheet presentation). EDIT mode SHALL be titled "Edit entry" (localized) with Cancel/Save actions in the navigation bar. LOCKED mode SHALL show the entry read-only with a Cancel action and no confirm action. The form SHALL use Theme semantic colors only, with all user-facing strings localized (EN + RU). With any inline picker expanded, the form SHALL keep its card margins on 320 pt screens: no card goes edge-to-edge and no content clips at the screen edges.

#### Scenario: Edit mode titles and actions
- **WHEN** the form opens for an existing `manual` entry
- **THEN** the title reads "Edit entry" (localized) with Cancel and Save actions — the same Name/Categories/Notes/Starts/Ends layout as creation

#### Scenario: Validity gate applies in edit mode
- **WHEN** the form holds an end equal to or before the start, or an empty trimmed name, in EDIT mode
- **THEN** Save is disabled with no error text, matching creation behavior

#### Scenario: Locked mode titles and actions
- **WHEN** the form opens for an entry with a non-`manual` source
- **THEN** the title identifies the entry as imported with a Cancel action and no Save action

#### Scenario: Expanded picker stays inside the cards on small screens
- **WHEN** the user expands a date or time picker on a 320 pt screen in any mode
- **THEN** the cards keep their horizontal margins, the picker renders within the card width, and no text or control touches or clips at the screen edges

### Requirement: EDIT mode saves through last-write-wins update
EDIT mode SHALL prefill the Name, Categories, Notes, and Starts/Ends pills from the entry. Activating Save on a valid form SHALL persist the changes through the local store's last-write-wins entry update (bumping `updated_at`, enqueuing the sync outbox row in the same transaction), dismiss the form, and refresh the underlying lists so the entry appears with its new values in the correct day group. Overlapping entries and future end-times SHALL be allowed, matching creation. Retexting or retagging SHALL affect only this entry. When the record changed underneath (stale write), the app SHALL show a localized error with the draft intact and the form open.

#### Scenario: Successful edit
- **WHEN** the user changes the end time of a `manual` entry and activates Save
- **THEN** the form dismisses and the entry shows the new interval and derived duration in its day group

#### Scenario: Stale write keeps the draft
- **WHEN** Save loses the last-write-wins race (the entry changed underneath, e.g. by sync)
- **THEN** a localized error is shown, the draft is preserved, and the form stays open

#### Scenario: Reassignment moves the entry
- **WHEN** the user retexts or retags an entry and saves (reassignment is now per-entry text/category change, not a move between activities)
- **THEN** the entry shows the new values in History and no other entry with the old text changes

#### Scenario: Overlap is allowed in edit mode
- **WHEN** the edited interval overlaps another entry
- **THEN** Save stays enabled and saving succeeds
