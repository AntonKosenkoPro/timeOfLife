## MODIFIED Requirements

### Requirement: Each History row shows entry identity and timing
Each History row SHALL display the entry's own text (headline — the entry's identity; there is no activity identity), the entry's start–end timeframe and natural-language duration (right-aligned), the entry's own comma-separated category names (left-aligned caption), and the first category's SF Symbol icon (leading, spanning both text lines, top-aligned with the name's cap-height top, not the text frame top). The duration SHALL render in the device locale's natural language with locale-correct unit abbreviations and plurals (e.g. English `1h 20m`; Russian uses Russian abbreviations). Rows with no categories SHALL render a `questionmark` fallback icon.

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
