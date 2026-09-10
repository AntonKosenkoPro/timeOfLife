## MODIFIED Requirements

### Requirement: Log Time sheet captures activity, start, and end

The app SHALL provide the Log Time sheet as the CREATE mode of the unified entry form (see entry-editor capability): styled on the iOS Calendar add-event form, containing exactly three input rows — Activity (title-over-value, like Calendar's "Calendar" row), Starts (date pill + time pill), and Ends (date pill + time pill). CREATE mode SHALL keep the "Log time" title (localized) with Cancel and Add actions in the navigation bar, presented as a sheet from the existing entry points with unchanged defaults, gates, pickers, and save behavior. EDIT and LOCKED modes (titles, Save/locked rules, Delete button) are defined by the entry-editor capability; no title, location, all-day, repeat, or alert fields SHALL be present in any mode.

#### Scenario: Sheet contents

- **WHEN** the Log Time sheet is open
- **THEN** it shows an Activity row, a Starts row with date and time pills, an Ends row with date and time pills, and Cancel/Add actions — and nothing else

#### Scenario: Cancel discards the draft

- **WHEN** the user activates Cancel
- **THEN** the sheet dismisses and no entry is created

#### Scenario: Create mode keeps its presentation

- **WHEN** the sheet opens from History or from an activity detail sheet for logging new time
- **THEN** it presents as a sheet (not a full-screen cover) with the "Log time" title and Cancel/Add actions
