## ADDED Requirements

### Requirement: Tapping a History entry row opens the activity detail sheet
The History list SHALL respond to a tap on an entry row by presenting the activity detail sheet for the entry's activity. The sheet is modal (a sheet, not a navigation push). History SHALL NOT offer swipe actions, long-press actions, or any edit/delete of entries. Tapping an entry row inside the detail sheet SHALL do nothing.

#### Scenario: Tap opens the sheet
- **WHEN** the user taps a History entry row
- **THEN** the activity detail sheet for that entry's activity is presented

#### Scenario: No other row actions
- **WHEN** the user swipes or long-presses a History entry row
- **THEN** no action is offered and nothing happens

#### Scenario: Tap inside the detail sheet
- **WHEN** the user taps an entry row inside the activity detail sheet
- **THEN** nothing happens