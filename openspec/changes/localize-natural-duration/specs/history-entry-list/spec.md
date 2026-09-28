## MODIFIED Requirements

### Requirement: Each History row shows entry identity and timing
Each History row SHALL display the entry's own text (headline), the entry's start–end timeframe and natural-language duration (right-aligned), the entry's own comma-separated category names (left-aligned caption), and the first category's SF Symbol icon (leading, spanning both text lines, top-aligned with the name's cap-height top, not the text frame top). The duration SHALL render in the device locale's natural language with locale-correct unit abbreviations and plurals (e.g. English `1h 20m`; Russian uses Russian abbreviations). Rows with no categories SHALL render a `questionmark` fallback icon.

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

### Requirement: Day groups use relative-then-absolute labels; total shown when elevated
Day group headers SHALL use relative labels ("Today", "Yesterday") for the two most recent days and the regional-standard absolute date for older days. A header SHALL show only the day label while in its in-list scroll position. When the header is elevated (pinned at the top of the list), it SHALL also display the total tracked time for that day, right-aligned, formatted in the device locale's natural language with a localized "tracked" suffix (e.g. English "2h 35m tracked"). The day label SHALL be left-aligned to the `EntryRow` icon column's leading edge, and the total SHALL be right-aligned to the `EntryRow` duration/timeframe trailing edge.

#### Scenario: Today's entries
- **WHEN** entries exist for the current calendar day
- **THEN** their day group header reads "Today" (localized), and shows the total tracked time for that day, right-aligned, when the header is elevated

#### Scenario: Yesterday's entries
- **WHEN** entries exist for the previous calendar day
- **THEN** their day group header reads "Yesterday" (localized), and shows the total tracked time for that day, right-aligned, when the header is elevated

#### Scenario: Older entries
- **WHEN** entries exist for a day before yesterday
- **THEN** their day group header reads the absolute date formatted using the device's regional settings, and shows the total tracked time for that day, right-aligned, when the header is elevated

#### Scenario: In-list header shows only the day label
- **WHEN** a day group header is in its in-list scroll position (not pinned at the top)
- **THEN** the header shows only the day label, without the total tracked time

#### Scenario: Day with in-progress entries
- **WHEN** a day group contains an entry with no end time
- **THEN** the total counts only entries with a known `durationSeconds`; in-progress entries contribute zero to the total

#### Scenario: Elevated total follows the device locale
- **WHEN** the device locale is Russian and a header is elevated
- **THEN** the day total renders with Russian unit abbreviations followed by the localized "tracked" suffix
