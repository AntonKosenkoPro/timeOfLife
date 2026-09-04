## Purpose

Lets users see an activity in full from the History tab: tapping an entry row opens a sheet with the activity's identity, its all-time tracked total, an edit-activity route, and the complete day-grouped list of that activity's committed entries.

## ADDED Requirements

### Requirement: Activity detail sheet presentation
The app SHALL present an activity detail sheet when the user taps a History entry row. The sheet SHALL start at the medium detent and be draggable to large. The sheet SHALL be dismissible by swipe or by the system dismiss affordance.

#### Scenario: Open from a History tap
- **WHEN** the user taps a History entry row
- **THEN** the activity detail sheet is presented at medium detent and can be dragged to large

#### Scenario: Dismiss the sheet
- **WHEN** the user swipes the sheet down
- **THEN** the sheet dismisses and History remains in its prior state

### Requirement: Sheet shows activity identity and all-time total
The sheet header SHALL display the activity's icon, name, and comma-separated category names, plus the activity's all-time tracked total (sum of committed entries' durations) right-aligned opposite the activity name, in monospaced digits. The total SHALL count committed entries only. The running session (if this activity is being timed) SHALL NOT appear in the sheet or contribute to the total.

#### Scenario: Total with entries
- **WHEN** the sheet opens for an activity with committed entries totaling 12h 40m
- **THEN** the header shows "12h 40m" right-aligned opposite the activity name, in monospaced digits

#### Scenario: Running session excluded
- **WHEN** a timer is currently running for this activity
- **THEN** the running session does not appear in the entry list and does not contribute to the total

### Requirement: Sheet lists all committed entries, day-grouped
The sheet SHALL list every committed entry of the activity, grouped by the day each entry started on, newest first, using the same day-group labels and row layout as the History list. The list SHALL be lazily loaded (no upfront cap). Each row in the sheet SHALL NOT respond to taps.

#### Scenario: Full history of the activity
- **WHEN** the sheet opens for an activity tracked on multiple days
- **THEN** all of its committed entries are shown, grouped by day like the History list, ordered newest day first

#### Scenario: Lazy loading
- **WHEN** the user scrolls the entry list beyond the initially rendered portion
- **THEN** older entries load without a visible interruption

### Requirement: Sheet routes to the activity editor
The sheet SHALL offer an "Edit activity" action that presents the existing activity editor stacked on top of the detail sheet. Dismissing the editor SHALL return to the detail sheet. Saved changes (name, icon, categories) SHALL be reflected in the sheet after the editor is dismissed.

#### Scenario: Edit activity
- **WHEN** the user taps "Edit activity" and renames the activity in the editor
- **THEN** the editor is stacked over the detail sheet, and after dismissing the editor the sheet shows the updated name

#### Scenario: Return from editor
- **WHEN** the user cancels the activity editor
- **THEN** the detail sheet remains as it was

### Requirement: Sheet is unavailable for a deleted activity
An activity's committed entries die with the activity (cascade deletion). The sheet SHALL never show an activity that no longer exists; when the underlying activity is deleted while the sheet is open, the system SHALL dismiss the sheet.

#### Scenario: Activity deleted while sheet is open
- **WHEN** the activity shown in the sheet is deleted (e.g., from another surface in a future change)
- **THEN** the sheet dismisses and the History list no longer contains that activity's entries