## MODIFIED Requirements

### Requirement: Each History row shows entry identity and timing
Each History row SHALL display the entry's own text (headline — the entry's identity; there is no activity identity), the entry's start–end timeframe and natural-language duration (right-aligned), the entry's own comma-separated category names (left-aligned caption), and the first category's SF Symbol icon (leading, spanning both text lines, top-aligned with the name's cap-height top, not the text frame top). The duration SHALL render in the device locale's natural language with locale-correct unit abbreviations and plurals (e.g. English `1h 20m`; Russian uses Russian abbreviations). Rows with no categories SHALL render a `questionmark` fallback icon. Rows and their accessibility labels SHALL NOT display producer/source labels; notes indication and existing category/timing geometry are unchanged.

#### Scenario: Row with categories
- **WHEN** an entry has one or more categories
- **THEN** the row shows the first category's icon (leading), the entry text (headline), all category names comma-separated (caption, left-aligned), the start–end timeframe (caption, right-aligned), and the duration (headline, right-aligned, top line)

#### Scenario: Row with no categories
- **WHEN** an entry has no categories
- **THEN** the row shows a `questionmark` fallback icon (leading), the entry text (headline), no category names, the start–end timeframe (caption, right-aligned), and the duration (headline, right-aligned, top line)

#### Scenario: Entry with no end time
- **WHEN** an entry has a start time but no end time (duration not yet computed)
- **THEN** the row shows the start time and an in-progress indicator in place of the end time and duration

#### Scenario: Duration follows the device locale
- **WHEN** the device locale is Russian and an entry lasted 1 hour 20 minutes
- **THEN** the row duration renders with Russian unit abbreviations (not `1h 20m`)

#### Scenario: Notes search adds context below the normal row
- **WHEN** notes are in scope and contain a matching text term
- **THEN** the row retains its identity, categories, timing, duration, and icon and adds the contextual excerpt beneath them
- **AND** tapping either highlighted text or the excerpt performs the existing whole-row action

#### Scenario: Retired provenance is not displayed
- **WHEN** an entry is shown after syncing a row that previously carried provider metadata
- **THEN** neither the row nor its VoiceOver label contains a source suffix or imported-entry designation

### Requirement: Tapping a History entry row opens the entry form
The History list SHALL respond to a tap on any saved entry row by opening the unified entry form in EDIT mode on the History navigation stack (see entry-editor capability). Every saved entry SHALL be editable, regardless of its creation surface or retired provenance. History SHALL NOT offer swipe actions, long-press actions, or any other row-level edit/delete actions.

#### Scenario: Tap opens the form
- **WHEN** the user taps a History entry row
- **THEN** the unified entry form opens in EDIT mode with the entry's values prefilled and the normal validity-gated confirm action

#### Scenario: Live Activity saved entry is editable
- **WHEN** the user taps an entry saved through the app after a Live Activity Stop link
- **THEN** the same editable form opens with no imported/read-only mode

#### Scenario: No other row actions
- **WHEN** the user swipes or long-presses a History entry row
- **THEN** no action is offered and nothing happens
