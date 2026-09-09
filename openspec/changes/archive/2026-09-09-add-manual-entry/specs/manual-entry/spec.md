## Purpose

Lets users log past time without the live timer: pick an activity, set a start and end, and save a committed manual entry — the recovery path for forgotten sessions.

## ADDED Requirements

### Requirement: Log Time sheet captures activity, start, and end

The app SHALL provide a Log Time sheet styled on the iOS Calendar add-event form, containing exactly three input rows: Activity (title-over-value, like Calendar's "Calendar" row), Starts (date pill + time pill), and Ends (date pill + time pill). The sheet SHALL have Cancel and Add actions in the navigation bar; no title, location, all-day, repeat, or alert fields SHALL be present.

#### Scenario: Sheet contents

- **WHEN** the Log Time sheet is open
- **THEN** it shows an Activity row, a Starts row with date and time pills, an Ends row with date and time pills, and Cancel/Add actions — and nothing else

#### Scenario: Cancel discards the draft

- **WHEN** the user activates Cancel
- **THEN** the sheet dismisses and no entry is created

### Requirement: Starts and Ends use inline expanding pickers

Tapping a date pill SHALL expand an inline graphical month picker below the pills; tapping a time pill SHALL expand an inline hour/minute/period wheel picker below the pills. Only one picker SHALL be open at a time — opening one collapses the other. The active pill SHALL show a selected tint. Pickers SHALL use the device locale and calendar.

#### Scenario: Expand the date picker

- **WHEN** the user taps the Starts date pill
- **THEN** a month-grid picker expands below the pills showing the currently selected date

#### Scenario: One picker at a time

- **WHEN** the date picker is open and the user taps a time pill
- **THEN** the date picker collapses and the wheel picker expands

### Requirement: Add is a validity gate

The Add action SHALL be enabled only when an activity is chosen AND the end is strictly after the start. Otherwise it SHALL be disabled. No error text or alert SHALL be shown for the disabled state.

#### Scenario: No activity chosen

- **WHEN** the sheet is open and no activity is chosen
- **THEN** Add is disabled

#### Scenario: End not after start

- **WHEN** the chosen end is equal to or before the start
- **THEN** Add is disabled

#### Scenario: Valid form

- **WHEN** an activity is chosen and the end is after the start
- **THEN** Add is enabled

### Requirement: Sheet opens with sensible defaults

The sheet SHALL open with Start set to the current time floored to 5 minutes and End set to Start plus one hour, unless the entry point supplies a day or activity context (ActivityDetail pre-fills the activity; no other defaults change).

#### Scenario: Default times

- **WHEN** the sheet opens from History at 2:37 PM
- **THEN** Start shows 2:35 PM and End shows 3:35 PM on the same day

#### Scenario: Pre-filled activity

- **WHEN** the sheet opens from an activity detail sheet
- **THEN** the Activity row shows that activity and the time defaults are unchanged

### Requirement: Moving Start preserves duration Calendar-style

When the user moves Start to a time at or after the current End, the End SHALL auto-advance to keep the previous duration. Moving Start earlier SHALL NOT move End. Moving End SHALL never move Start.

#### Scenario: Start pushed past End

- **WHEN** the form holds Start 2:35 PM / End 3:35 PM (1h) and the user moves Start to 4:00 PM
- **THEN** End auto-advances to 5:00 PM

#### Scenario: Start moved earlier

- **WHEN** the form holds Start 2:35 PM / End 3:35 PM and the user moves Start to 1:00 PM
- **THEN** End stays at 3:35 PM

### Requirement: Activity picking supports search and quick-create

Tapping the Activity row SHALL open the Track-style searchable activity sheet (browse, filter, quick-create with the normalized-name collision rule). Confirming an existing activity selects it; confirming quick-create creates the activity locally and selects it. Dismissing without confirming SHALL leave the previously selected activity (or none) unchanged. An empty catalog SHALL route directly to quick-create for the typed name with no dead end.

#### Scenario: Pick an existing activity

- **WHEN** the user confirms an existing activity in the picker
- **THEN** the picker dismisses and the Activity row shows that activity

#### Scenario: Quick-create from the picker

- **WHEN** the user confirms quick-create for an unmatched valid name
- **THEN** the activity is created locally, the picker dismisses, and the Activity row shows it

#### Scenario: Dismiss without choosing

- **WHEN** the user dismisses the picker without confirming
- **THEN** the Activity row is unchanged

### Requirement: Saving creates a committed manual entry

Activating Add SHALL persist a committed entry via `LocalStore.createEntry` with `source:"manual"` and null `source_ref` (client-generated UUID v7 id, `duration_seconds` derived from end minus start), enqueueing the sync outbox row in the same transaction and bumping the activity's `last_used_at`. The sheet SHALL dismiss and the underlying list SHALL refresh to include the entry in its day group. Overlapping entries and future end-times SHALL be allowed.

#### Scenario: Successful save

- **WHEN** the user activates Add on a valid form
- **THEN** a committed manual entry exists with the chosen activity, start, end, and derived duration, and the sheet dismisses

#### Scenario: Overlap is allowed

- **WHEN** the chosen interval overlaps an existing entry or a running timer session
- **THEN** Add stays enabled and saving succeeds
