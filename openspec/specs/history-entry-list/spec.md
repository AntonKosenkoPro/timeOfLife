# History Entry List Specification

## Purpose

Lets users review their committed time entries as a read-only, day-grouped list in the History tab, showing activity identity, categories, timeframe, and duration.

## Requirements


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

### Requirement: History offers no edit, delete, swipe, or long-press actions
History rows SHALL NOT offer edit, delete, swipe, or long-press actions. Tapping an entry row opens the unified entry form directly (see "Tapping a History entry row opens the entry form").

#### Scenario: No row actions
- **WHEN** the user swipes or long-presses a History entry row
- **THEN** no action is offered and nothing happens
### Requirement: History preserves compact timer access with a persistent nav bar
The History destination SHALL keep the compact cross-tab running timer visible and stoppable, matching the app-shell "Running timer remains globally accessible" requirement. The History destination SHALL keep the navigation bar (inline "History" title and Profile button) permanently visible while History is on screen, regardless of list scroll position. The Profile button is reachable at all times on History.

#### Scenario: Compact timer on History
- **WHEN** a timer is running and the user selects History
- **THEN** the compact timer is visible at the bottom safe area and the entry list scrolls above it

#### Scenario: Navigation bar always visible
- **WHEN** the user scrolls the History list down and back up
- **THEN** the inline "History" title and Profile button remain visible at every scroll position

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
### Requirement: History reflects entry edits and deletes
Edits saved in the entry form SHALL appear in the History list with updated values in the correct day group when the user returns to it. Entries deleted via the entry form SHALL disappear from the History list (removing the day group when it becomes empty, recomputing the day total) via the existing invalidate/reload chain.

#### Scenario: Edited entry shows new values
- **WHEN** the user edits an entry's interval and returns to History
- **THEN** the entry shows the new timeframe and duration in its day group

#### Scenario: Deleted entry disappears
- **WHEN** the user confirms deletion of an entry and returns to History
- **THEN** the entry is gone and its day group is removed when empty
### Requirement: Tapping a History entry row opens the entry form
The History list SHALL respond to a tap on an entry row by opening the unified entry form (see entry-editor capability) as a full-screen cover for that entry — editable for `manual` entries, read-only (delete-only) for imported entries. History SHALL NOT offer swipe actions, long-press actions, or any other edit/delete of entries.

#### Scenario: Tap opens the form
- **WHEN** the user taps a History entry row
- **THEN** the unified entry form opens for that entry — editable for `manual` entries, read-only (delete-only) for imported entries

#### Scenario: No other row actions
- **WHEN** the user swipes or long-presses a History entry row
- **THEN** no action is offered and nothing happens

### Requirement: History pull-to-refresh triggers sync only
The populated History list SHALL offer a native pull-to-refresh gesture that runs a sync cycle only: it SHALL NOT perform an explicit local reload (the existing cycle-exit invalidate/reload remains the sole reload path). The empty state SHALL offer no pull gesture in this change. The native spinner SHALL tick exactly as long as the awaited cycle (fresh or joined) lasts.

#### Scenario: Pull with entries while signed in and online
- **WHEN** the user pulls on the populated History list while signed in and online with no cycle in flight
- **THEN** a sync cycle runs, the spinner ticks until it resolves, and the list reloads via the existing cycle-exit path

#### Scenario: Pull joins an in-flight cycle
- **WHEN** the user pulls while a cycle started by any other trigger is in flight
- **THEN** no second cycle starts; the spinner awaits the in-flight cycle's result

#### Scenario: Empty History has no pull
- **WHEN** History shows the empty state (no committed entries)
- **THEN** no pull-to-refresh gesture is offered

### Requirement: Signed-out pull shows a sign-in banner with link
A pull while signed out SHALL NOT start any sync network traffic. It SHALL present an inline notice below the navigation bar stating sign-in is required with a tappable sign-in link that opens the Enable Sync auth sheet (the existing auth flow, not a new entry point). The banner SHALL auto-dismiss after 5 seconds, reset its timer on re-pull, dismiss on navigation away, and dismiss early on successful sign-in (first-sync takes over).

#### Scenario: Signed-out pull
- **WHEN** the user pulls while signed out
- **THEN** no network traffic occurs and the signed-out banner with sign-in link appears

#### Scenario: Banner auto-dismiss
- **WHEN** the signed-out banner has been visible for 5 seconds without interaction
- **THEN** it dismisses on its own

#### Scenario: Sign-in link
- **WHEN** the user taps the sign-in link in the banner
- **THEN** the Enable Sync auth sheet opens; a successful sign-in dismisses the banner and starts first-sync

### Requirement: Offline pull shows an offline banner
A pull while signed in but offline SHALL NOT start a sync cycle. It SHALL present an inline notice in the same slot as the signed-out banner stating the device is offline (no action link), with the same 5-second auto-dismiss, re-pull reset, and dismiss-on-leave behavior. A connectivity loss mid-cycle (online at pull, offline during drain) SHALL surface as a cycle error dialog, not the offline banner.

#### Scenario: Offline pull
- **WHEN** the user pulls while signed in with no connectivity
- **THEN** no cycle starts and the offline banner appears in the banner slot

#### Scenario: Mid-cycle connectivity loss
- **WHEN** connectivity drops after a pull-started cycle began
- **THEN** the failure surfaces via the pull error dialog, not the offline banner

### Requirement: Pull-initiated sync failure shows an error dialog
A sync cycle awaited by a pull that ends in error SHALL present a modal dialog with a localized title, the captured secret-free error message as body, and a single OK button that dismisses it. Background cycle failures with no pull in flight SHALL NOT present the dialog (Profile status still reflects them).

#### Scenario: Failed pull shows dialog
- **WHEN** a pull-awaited cycle (fresh or joined) fails
- **THEN** the error dialog appears with the captured message and an OK button

#### Scenario: Background failure shows no dialog
- **WHEN** a foreground/connectivity cycle fails while History is visible with no pull in flight
- **THEN** no dialog appears over History
