## ADDED Requirements

### Requirement: Planner selection prepares only a name
Selecting a planner task SHALL fill its normalized text as the prepared Track name with empty categories and notes, dismiss the planner on successful selection, and leave Start as a separate explicit action. An exact match with Recents or a committed name SHALL NOT inherit categories through this path. Selection SHALL NOT write a running timer draft, create an entry, start timing, or change task completion. Existing Recents/name-picker inheritance behavior SHALL remain unchanged.

#### Scenario: Select a name with historical categories
- **WHEN** a stopped Track selects a planner task whose name exactly matches a prior categorized entry
- **THEN** Track becomes ready with that name and empty categories/notes; no time is recorded and the task's checkbox is unchanged

#### Scenario: Start preserves text-only preparation
- **WHEN** the user presses Start after planner selection without changing the prepared name
- **THEN** the timer starts with the prepared text and empty categories/notes without re-deriving categories from history

### Requirement: Planner selection cannot replace an active or saving run
Planner name-selection controls SHALL be disabled while Track is running, in a recoverable running error, or saving. Selection SHALL recheck eligibility when performed, not rely solely on presentation-time state. Checklist operations SHALL remain independent of these timer restrictions.

#### Scenario: State changes after sheet opens
- **WHEN** timing begins or saving is in progress after the planner was opened
- **THEN** a task-name action cannot overwrite the timer or prepare a queued next task, while permitted checklist operations still work
