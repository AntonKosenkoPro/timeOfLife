## MODIFIED Requirements

### Requirement: Saving creates a committed manual entry
Activating Add SHALL persist a committed entry via the local mutation chokepoint with a client-generated UUID v7 id, trimmed `activity_text`, ordered `category_ids`, `notes`, and `duration_seconds` derived from end minus start, enqueueing the sync outbox row in the same transaction. It SHALL NOT assign producer provenance or an external import reference. The sheet SHALL dismiss and the underlying list SHALL refresh to include the entry in its day group. Overlapping entries and future end-times SHALL be allowed. “Manual entry” names the Log Time interaction, not a distinct stored entry kind.

#### Scenario: Successful save
- **WHEN** the user activates Add on a valid form
- **THEN** a committed entry exists with the entered text, categories, notes, start, end, and derived duration, without provenance fields, and the sheet dismisses

#### Scenario: Overlap is allowed
- **WHEN** the chosen interval overlaps an existing entry or a running timer session
- **THEN** Add stays enabled and saving succeeds

### Requirement: Log Time sheet captures name, start, end, categories, and notes
The app SHALL provide the Log Time sheet as the CREATE mode of the unified entry form (see entry-editor capability): cards in exactly this order — Name (plain-text entry-text field, never an activity picker), Start (date pill + time pill with inline single-open picker), End (date pill + time pill with inline single-open picker), Categories (ordered TagSelector), Notes (plain-text field, empty by default). An empty name SHALL mean no text is chosen and no entry text is pre-filled. CREATE mode SHALL keep the "Log time" title (localized) with an X dismiss action (`LogTimeDismissButton`) and a ✓ confirm action (`LogTimeAddButton`, localized VoiceOver labels, system-default toolbar tint) in the navigation bar, presented as a sheet from the existing entry points with unchanged defaults, gates, pickers, and save behavior. EDIT mode is defined by the entry-editor capability; no LOCKED mode SHALL exist, and no extra title, location, all-day, repeat, or alert input fields SHALL be present. The all-native-gestures-must-work rule (entry-editor capability) SHALL apply to CREATE and EDIT.

#### Scenario: Sheet contents
- **WHEN** the Log Time sheet is open
- **THEN** it shows an X dismiss button and a ✓ confirm button (with the Log time title and the unchanged Name/Start/End/Categories/Notes cards) — and no Cancel/Add text buttons

#### Scenario: Cross discards the draft
- **WHEN** the user activates the X button
- **THEN** the sheet dismisses and no entry is created

#### Scenario: Create mode keeps its presentation
- **WHEN** the sheet opens from History for logging new time
- **THEN** it presents as a sheet (not a full-screen cover) with the localized Log time title and X/✓ actions
