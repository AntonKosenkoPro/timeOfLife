## ADDED Requirements

### Requirement: Sheet offers Log time for its activity

The activity detail sheet SHALL offer a `Log time` action that opens the Log Time sheet (`manual-entry`) pre-filled with the sheet's activity. Dismissing the Log Time sheet (via Add or Cancel) SHALL return to the detail sheet. A saved entry SHALL appear in the detail sheet's entry list.

#### Scenario: Open Log time

- **WHEN** the user activates `Log time` on the detail sheet for activity "Running"
- **THEN** the Log Time sheet opens with the Activity row showing "Running"

#### Scenario: Return from the Log Time sheet

- **WHEN** the user cancels the Log Time sheet opened via `Log time`
- **THEN** the detail sheet remains as it was

#### Scenario: Saved entry appears in the detail list

- **WHEN** the user saves a manual entry from the sheet opened via `Log time`
- **THEN** the Log Time sheet dismisses and the entry appears in the detail sheet's day-grouped entry list
