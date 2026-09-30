## MODIFIED Requirements

### Requirement: Category-editor name field has a clear button
The category-editor name field SHALL offer a trailing clear (`×`) button visible only when the field is focused AND holds non-empty text, with the same Apple-standard look (small dim `xmark.circle.fill`, 44 pt tap target). One tap SHALL clear the draft name; field validation re-evaluates. The shared field component's clear affordance is opt-in per call site and defaults to off (the email-OTP field has none). The field's rendered height SHALL NOT change when the clear button appears or disappears: the text input SHALL carry a minimum height of 44 pt so the 44 pt button fits inside an already-44 pt row, and the input card SHALL use horizontal-only padding so the card stays compact (~44 pt, NamePicker parity) instead of ballooning with full padding. Focus state SHALL be bound to the text field itself (programmatic focus moves to the field; user focus updates the binding), never to a wrapper container. The editor SHALL autofocus the name field after the sheet presentation settles, and the focused field SHALL be fully inside the visible viewport (never partly clipped by the navigation bar, keyboard, or sheet edge) in both create and edit modes.

#### Scenario: Category name clear hidden when unfocused or empty
- **WHEN** the category-editor name field is empty or unfocused
- **THEN** no clear button is shown

#### Scenario: Category name clear clears the draft name
- **WHEN** the category-editor name field is focused and holds text
- **THEN** a trailing `×` is visible, and one tap empties the field

#### Scenario: Field height is stable when the clear button appears
- **WHEN** the user types the first character into the focused empty name field (create mode), or focuses the prefilled field (edit mode)
- **THEN** the trailing `×` appears with no change to the field's rendered height and no shift of the content below it

#### Scenario: Field height is stable when the clear button disappears
- **WHEN** the focused name field loses focus (e.g. keyboard Done) while holding text, or its text is cleared
- **THEN** the trailing `×` hides with no change to the field's rendered height

#### Scenario: Name field card is compact in both modes
- **WHEN** the category editor renders the name field in create or edit mode, with or without the clear button
- **THEN** the input card is ~44 pt tall (44 pt row with horizontal-only padding), matching the app's other plain-text fields

#### Scenario: Prefilled editor opens with a compact fully-visible field
- **WHEN** the category editor opens in edit mode (name prefilled, autofocused)
- **THEN** the name field renders at its compact single-line height, fully inside the visible viewport, with the keyboard open

#### Scenario: Programmatic focus reaches the text field
- **WHEN** the editor requests autofocus on appear
- **THEN** the name text field becomes first responder (caret visible, keyboard open) in both create and edit modes
