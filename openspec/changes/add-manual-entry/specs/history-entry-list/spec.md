## ADDED Requirements

### Requirement: History offers manual entry creation

The History destination SHALL offer a `[+]` action in the navigation bar that opens the Log Time sheet (`manual-entry`). The `[+]` action SHALL remain reachable at all scroll positions, alongside the inline "History" title and Profile button. Saving from the sheet SHALL refresh the list to include the new entry in its day group.

#### Scenario: Open the Log Time sheet

- **WHEN** the user activates the `[+]` action in the History navigation bar
- **THEN** the Log Time sheet opens with default times and no pre-filled activity

#### Scenario: Action stays reachable

- **WHEN** the user scrolls the History list down and back up
- **THEN** the `[+]` action remains visible alongside the title and Profile button

#### Scenario: Saved entry appears

- **WHEN** the user saves a manual entry from the sheet opened via `[+]`
- **THEN** the sheet dismisses and the entry appears in its day group in the list
