# Entry Editor — Small-Screen Picker Containment Delta

## MODIFIED Requirements

### Requirement: Unified entry form with CREATE, EDIT, and LOCKED modes
The app SHALL provide a single entry form with three modes sharing one Calendar-grammar layout (Activity row opening the shared searchable activity picker; Starts and Ends rows with date + time pills and inline single-open pickers; device locale and calendar) and one validity gate (the confirm action is enabled only when an activity is chosen AND the end is strictly after the start; otherwise disabled with no error text). CREATE mode SHALL behave per the manual-entry capability (Log Time copy, Cancel/Add, sheet presentation). EDIT mode SHALL be titled "Edit entry" (localized) with Cancel/Save actions in the navigation bar. LOCKED mode SHALL show the entry read-only with a Cancel action and no confirm action. The form SHALL use Theme semantic colors only, with all user-facing strings localized (EN + RU). With any inline picker expanded, the form SHALL keep its card margins on 320 pt screens: no card goes edge-to-edge and no content clips at the screen edges.

#### Scenario: Edit mode titles and actions
- **WHEN** the form opens for an existing `manual` entry
- **THEN** the title reads "Edit entry" (localized) with Cancel and Save actions — the same Activity/Starts/Ends layout as creation

#### Scenario: Validity gate applies in edit mode
- **WHEN** the form holds an end equal to or before the start in EDIT mode
- **THEN** Save is disabled with no error text, matching creation behavior

#### Scenario: Locked mode titles and actions
- **WHEN** the form opens for an entry with a non-`manual` source
- **THEN** the title identifies the entry as imported with a Cancel action and no Save action

#### Scenario: Expanded picker stays inside the cards on small screens
- **WHEN** the user expands a date or time picker on a 320 pt screen in any mode
- **THEN** the cards keep their horizontal margins, the picker renders within the card width, and no text or control touches or clips at the screen edges
