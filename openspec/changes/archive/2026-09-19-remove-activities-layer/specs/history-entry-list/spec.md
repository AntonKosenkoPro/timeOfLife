## MODIFIED Requirements

### Requirement: Each History row shows entry identity and timing
Each History row SHALL display the entry's own text (headline), the entry's start–end timeframe and natural-language duration (right-aligned), the entry's own comma-separated category names (left-aligned caption), and the first category's SF Symbol icon (leading, spanning both text lines, top-aligned with the name's cap-height top, not the text frame top). Rows with no categories SHALL render a `questionmark` fallback icon.

#### Scenario: Row with categories
- **WHEN** an entry has one or more categories
- **THEN** the row shows the first category's icon (leading), the entry text (headline), all category names comma-separated (caption, left-aligned), the start–end timeframe (caption, right-aligned), and the duration (headline, right-aligned, top line)

#### Scenario: Row with no categories
- **WHEN** an entry has no categories
- **THEN** the row shows a `questionmark` fallback icon (leading), the entry text (headline), no category names, the start–end timeframe (caption, right-aligned), and the duration (headline, right-aligned, top line)

#### Scenario: Entry with no end time
- **WHEN** an entry has a start time but no end time (duration not yet computed)
- **THEN** the row shows the start time and an in-progress indicator in place of the end time and duration

### Requirement: History offers no edit, delete, swipe, or long-press actions
History rows SHALL NOT offer edit, delete, swipe, or long-press actions. Tapping an entry row opens the unified entry form directly (see "Tapping a History entry row opens the entry form").

#### Scenario: No row actions
- **WHEN** the user swipes or long-presses a History entry row
- **THEN** no action is offered and nothing happens

### Requirement: Tapping a History entry row opens the entry form
The History list SHALL respond to a tap on an entry row by opening the unified entry form (see entry-editor capability) as a full-screen cover for that entry — editable for `manual` entries, read-only (delete-only) for imported entries. History SHALL NOT offer swipe actions, long-press actions, or any other edit/delete of entries.

#### Scenario: Tap opens the form
- **WHEN** the user taps a History entry row
- **THEN** the unified entry form opens for that entry — editable for `manual` entries, read-only (delete-only) for imported entries

#### Scenario: No other row actions
- **WHEN** the user swipes or long-presses a History entry row
- **THEN** no action is offered and nothing happens

### Requirement: History offers manual entry creation
The History destination SHALL offer a `[+]` action in the navigation bar that opens the Log Time sheet (`manual-entry`). The `[+]` action SHALL remain reachable at all scroll positions, alongside the inline "History" title and Profile button. Saving from the sheet SHALL refresh the list to include the new entry in its day group.

#### Scenario: Open the Log Time sheet
- **WHEN** the user activates the `[+]` action in the History navigation bar
- **THEN** the Log Time sheet opens with default times and empty name, categories, and notes

#### Scenario: Action stays reachable
- **WHEN** the user scrolls the History list down and back up
- **THEN** the `[+]` action remains visible alongside the title and Profile button

#### Scenario: Saved entry appears
- **WHEN** the user saves a manual entry from the sheet opened via `[+]`
- **THEN** the sheet dismisses and the entry appears in its day group in the list
