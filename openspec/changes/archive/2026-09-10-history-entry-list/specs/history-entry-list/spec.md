## Purpose

Lets users review their committed time entries as a read-only, day-grouped list in the History tab, showing activity identity, categories, timeframe, and duration.

## ADDED Requirements

### Requirement: History shows committed time entries
The History destination SHALL display committed `TimeEntry` records as a chronological list, newest first, grouped by the day each entry started on. The list SHALL NOT show running (uncommitted) timer sessions.

#### Scenario: History with entries
- **WHEN** the user selects History and at least one committed time entry exists
- **THEN** the app shows a list of time entries grouped by day, newest day first, with entries within each day ordered newest first

#### Scenario: History with no entries
- **WHEN** the user selects History and no committed time entries exist
- **THEN** the app shows the existing empty state (`historyEmptyTitle` / `historyEmptySubtitle`) and no list

#### Scenario: Running timer is not in History
- **WHEN** a timer is running and the user selects History
- **THEN** the compact timer remains visible but the running session does not appear as a History entry until the timer is stopped and saved

### Requirement: Each History row shows entry identity and timing
Each History row SHALL display the activity name (headline), the entry's start–end timeframe and natural-language duration (right-aligned), the activity's comma-separated category names (left-aligned caption), and the first category's SF Symbol icon (leading, spanning both text lines, top-aligned with the activity name's cap-height top, not the text frame top). Rows with no categories SHALL render a `questionmark` fallback icon.

#### Scenario: Row with categories
- **WHEN** an entry's activity has one or more categories
- **THEN** the row shows the first category's icon (leading), the activity name (headline), all category names comma-separated (caption, left-aligned), the start–end timeframe (caption, right-aligned), and the duration (headline, right-aligned, top line)

#### Scenario: Row with no categories
- **WHEN** an entry's activity has no categories
- **THEN** the row shows a `questionmark` fallback icon (leading), the activity name (headline), no category names, the start–end timeframe (caption, right-aligned), and the duration (headline, right-aligned, top line)

#### Scenario: Entry with no end time
- **WHEN** an entry has a start time but no end time (duration not yet computed)
- **THEN** the row shows the start time and an in-progress indicator in place of the end time and duration

### Requirement: Day groups use relative-then-absolute labels; total shown when elevated
Day group headers SHALL use relative labels ("Today", "Yesterday") for the two most recent days and the regional-standard absolute date for older days. A header SHALL show only the day label while in its in-list scroll position. When the header is elevated (pinned at the top of the list), it SHALL also display the total tracked time for that day, right-aligned, formatted in natural language with a localized "tracked" suffix (e.g. "2h 35m tracked"). The day label SHALL be left-aligned to the `EntryRow` icon column's leading edge, and the total SHALL be right-aligned to the `EntryRow` duration/timeframe trailing edge.

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

### Requirement: History is read-only
History rows SHALL not respond to taps in this capability. No edit, delete, or navigation action SHALL be available from the History list.

#### Scenario: Tap on entry row
- **WHEN** the user taps a History entry row
- **THEN** nothing happens

### Requirement: History preserves compact timer access and uses a collapsing nav bar
The History destination SHALL keep the compact cross-tab running timer visible and stoppable, matching the app-shell "Running timer remains globally accessible" requirement. The History destination SHALL show the navigation bar (inline "History" title and Profile button) at rest, collapse it out of view when the list scrolls down, and restore it when the user scrolls back to the top. The Profile button is reachable at rest on History.

#### Scenario: Compact timer on History
- **WHEN** a timer is running and the user selects History
- **THEN** the compact timer is visible at the bottom safe area and the entry list scrolls above it

#### Scenario: Navigation bar visible at rest
- **WHEN** the user selects History and the list is at the top
- **THEN** the inline "History" title and Profile button are visible

#### Scenario: Navigation bar collapses on scroll
- **WHEN** the user scrolls the list down
- **THEN** the inline navigation title and Profile button collapse out of view

#### Scenario: Navigation bar restores at top
- **WHEN** the user scrolls the list back to the top
- **THEN** the inline "History" title and Profile button restore into view