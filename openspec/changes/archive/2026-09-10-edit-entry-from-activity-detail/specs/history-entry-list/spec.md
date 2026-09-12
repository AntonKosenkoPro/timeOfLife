## MODIFIED Requirements

### Requirement: Tapping a History entry row opens the activity detail sheet

The History list SHALL respond to a tap on an entry row by presenting the activity detail sheet for the entry's activity. The sheet is modal (a sheet, not a navigation push). History SHALL NOT offer swipe actions, long-press actions, or any edit/delete of entries. Tapping an entry row inside the detail sheet SHALL open the unified entry form (see entry-editor capability) as a full-screen cover.

#### Scenario: Tap opens the sheet

- **WHEN** the user taps a History entry row
- **THEN** the activity detail sheet for that entry's activity is presented

#### Scenario: No other row actions

- **WHEN** the user swipes or long-presses a History entry row
- **THEN** no action is offered and nothing happens

#### Scenario: Tap inside the detail sheet

- **WHEN** the user taps an entry row inside the activity detail sheet
- **THEN** the unified entry form opens for that entry — editable for `manual` entries, read-only (delete-only) for imported entries

## ADDED Requirements

### Requirement: History reflects entry edits and deletes

Edits saved in the entry form SHALL appear in the History list with updated values in the correct day group when the user returns to it. Entries deleted via the entry form SHALL disappear from the History list (removing the day group when it becomes empty, recomputing the day total) via the existing invalidate/reload chain.

#### Scenario: Edited entry shows new values

- **WHEN** the user edits an entry's interval and returns to History
- **THEN** the entry shows the new timeframe and duration in its day group

#### Scenario: Deleted entry disappears

- **WHEN** the user confirms deletion of an entry and returns to History
- **THEN** the entry is gone and its day group is removed when empty
