## Purpose

Lets users prioritize today's work, see what they have finished, and track time on a planned task without mixing the checklist into History.

## ADDED Requirements

### Requirement: Today is the only planner view

The planner SHALL show all unfinished tasks and tasks completed on the current local calendar date. Each completion SHALL retain the calendar date on which it was recorded by the device performing the action. Carry-forward SHALL be automatic, preserve task identity and order, and require no mutation or sync write. The planner SHALL refresh the visible day when it changes, including on foreground return. There SHALL be no other day view or carry-forward button.

#### Scenario: Return after missing multiple days
- **WHEN** the user returns several days later with unfinished tasks and tasks completed on earlier dates
- **THEN** every unfinished task appears once in its existing relative order, earlier completed tasks do not appear, and nothing is written just to show Today

#### Scenario: A completion stays in place for the rest of the day
- **WHEN** a task is completed and the current local calendar date is still its completion date
- **THEN** its checked row remains in place; when the date advances it no longer appears unless reopened

### Requirement: Planned tasks are an independently editable checklist

A task SHALL have a trimmed, valid timer name as its only user-entered field. Tasks with identical names SHALL have separate identities. The user SHALL be able to rename, reorder, complete, reopen, and delete visible tasks offline. New tasks SHALL append after existing Today rows. Completing or reopening a task SHALL keep its position and SHALL NOT start, stop, create, or modify a timer or time entry.

#### Scenario: Two tasks use the same name
- **WHEN** the user adds two tasks with the same valid name, then edits or removes one
- **THEN** the other row is unaffected

#### Scenario: Reopen a task after logging time
- **WHEN** the user reopens a task that was completed by Stop
- **THEN** the task becomes unfinished at its existing position, and the saved entry is unchanged

### Requirement: The composer supports repeated adds without dismissing the keyboard

The Today page SHALL use one inline composer with the task list and a bounded area for matching, newest-first Recents drawn from committed entries. Recents selection SHALL only fill the composer with the exact suggested text. Return on a valid draft SHALL append one task, clear the composer, and keep the input focused and the keyboard open without a layout jump. Invalid or failed submission SHALL NOT append a row or discard the draft. Row changes SHALL use non-disruptive feedback and respect Reduce Motion.

#### Scenario: Add consecutive tasks
- **WHEN** the user adds a valid task with Return and then types and submits the next name
- **THEN** both tasks append in submission order and the keyboard remains available without dismissing and reopening or moving the composer

#### Scenario: Fill from a matching Recent
- **WHEN** the user taps a matching Recent while composing
- **THEN** its exact text fills the draft for editing or submission, no task is created, and no timer starts

### Requirement: An open task starts the existing timer

Activating Start on an open task SHALL start that exact task in one tap when no timer is active and return to Track after a successful start. The existing Track name and exact-text category inheritance rules SHALL apply. While a run is active, saving, or awaiting a Stop retry, the planner SHALL remain usable except for starting another task. A task rename SHALL NOT change the locked timer name.

#### Scenario: Start without replacing a timer
- **WHEN** a task Start is invoked while another run is active
- **THEN** no replacement starts and the user can still edit the checklist

#### Scenario: Start one of two identically named tasks
- **WHEN** an idle user starts one of two tasks with the same name and later successfully stops the timer
- **THEN** the ordinary timer saves its entry and only the explicitly selected task becomes done
