## MODIFIED Requirements

### Requirement: Log Time sheet captures name, categories, notes, start, and end
The app SHALL provide the Log Time sheet as the CREATE mode of the unified entry form (see entry-editor capability): containing Name (plain-text field), Categories (ordered TagSelector), Notes (plain-text field, empty by default), Starts (date pill + time pill), and Ends (date pill + time pill). CREATE mode SHALL keep the "Log time" title (localized) with Cancel and Add actions in the navigation bar, presented as a sheet from the existing entry points with unchanged defaults, gates, pickers, and save behavior. EDIT and LOCKED modes are defined by the entry-editor capability; no title, location, all-day, repeat, or alert fields SHALL be present in any mode.

#### Scenario: Sheet contents
- **WHEN** the Log Time sheet is open
- **THEN** it shows a Name row, a Categories row, a Notes row, a Starts row with date and time pills, an Ends row with date and time pills, and Cancel/Add actions — and nothing else

#### Scenario: Cancel discards the draft
- **WHEN** the user activates Cancel
- **THEN** the sheet dismisses and no entry is created

#### Scenario: Create mode keeps its presentation
- **WHEN** the sheet opens from History for logging new time
- **THEN** it presents as a sheet (not a full-screen cover) with the "Log time" title and Cancel/Add actions

### Requirement: Add is a validity gate
The Add action SHALL be enabled only when the trimmed name is non-empty AND the end is strictly after the start. Otherwise it SHALL be disabled. No error text or alert SHALL be shown for the disabled state.

#### Scenario: No activity chosen
- **WHEN** the sheet is open and the trimmed name is empty (no text has been entered)
- **THEN** Add is disabled

#### Scenario: End not after start
- **WHEN** the chosen end is equal to or before the start
- **THEN** Add is disabled

#### Scenario: Valid form
- **WHEN** a non-empty name is entered and the end is after the start
- **THEN** Add is enabled

### Requirement: Sheet opens with sensible defaults
The sheet SHALL open with Name empty (or the exact recent's text when opened with a text context), Categories empty (or that text's inherited ordered set when a text context is supplied), Notes empty, Start set to the current time floored to 5 minutes and End set to Start plus one hour.

#### Scenario: Default times
- **WHEN** the sheet opens from History at 2:37 PM
- **THEN** Start shows 2:35 PM and End shows 3:35 PM on the same day with empty name, categories, and notes

#### Scenario: Pre-filled activity
- **WHEN** the sheet opens from any entry point (History or otherwise)
- **THEN** no activity is pre-filled: the Name row is empty and categories and notes start empty, with only the time defaults applied

### Requirement: Saving creates a committed manual entry
Activating Add SHALL persist a committed entry via `LocalStore.createEntry` with `source:"manual"` and null `source_ref` (client-generated UUID v7 id, trimmed `activity_text`, ordered `category_ids`, `notes`, `duration_seconds` derived from end minus start), enqueueing the sync outbox row in the same transaction. The sheet SHALL dismiss and the underlying list SHALL refresh to include the entry in its day group. Overlapping entries and future end-times SHALL be allowed.

#### Scenario: Successful save
- **WHEN** the user activates Add on a valid form
- **THEN** a committed manual entry exists with the entered text, categories, notes, start, end, and derived duration, and the sheet dismisses

#### Scenario: Overlap is allowed
- **WHEN** the chosen interval overlaps an existing entry or a running timer session
- **THEN** Add stays enabled and saving succeeds

## REMOVED Requirements

### Requirement: Activity picking supports search and quick-create
**Reason**: No activity catalog exists; the Name row is a plain-text field with no picker.
**Migration**: Type the exact text directly; categories/notes are entered inline on the same form.
