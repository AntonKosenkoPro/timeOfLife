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

A task SHALL have a trimmed, valid timer name as its only user-entered field. Tasks with identical names SHALL have separate identities. The user SHALL be able to rename, reorder, complete, reopen, and delete visible tasks offline. New tasks SHALL append after existing Today rows. Completing or reopening a task SHALL keep its position and SHALL NOT start, stop, create, or modify a timer or time entry. Completing or reopening a task SHALL NOT change the row's height or move sibling rows.

#### Scenario: Two tasks use the same name
- **WHEN** the user adds two tasks with the same valid name, then edits or removes one
- **THEN** the other row is unaffected

#### Scenario: Reopen a task after logging time
- **WHEN** the user reopens a task that was completed by Stop
- **THEN** the task becomes unfinished at its existing position, and the saved entry is unchanged

#### Scenario: Toggle keeps the list still
- **WHEN** the user completes or reopens a task
- **THEN** the row keeps its exact height (the Start affordance slot is preserved in both states) and no other row moves

### Requirement: The composer supports repeated adds without dismissing the keyboard

The Today page SHALL use one inline composer fixed at the bottom of the screen with a single task list surface above it. While the keyboard is open, a single horizontally scrollable line of recent-activity chips drawn from newest-first Recents SHALL sit fixed between the composer and the keyboard; typing filters the chips by prefix, and tapping a chip fills the composer with its exact text. Choosing a chip SHALL create no task and start no timer. Return on a valid draft SHALL append one task at the end of the list with an expanding insertion, clear the composer, and keep the input focused with the keyboard open. The field SHALL never resign first responder across a submit — no dismiss/reopen cycle of any duration. The composer SHALL suppress the Return key's default resign at dispatch (custom submit handling that never resigns), rather than restoring focus afterwards. Invalid or failed submission SHALL NOT append a row or discard the draft. Row changes SHALL use non-disruptive feedback and respect Reduce Motion.

#### Scenario: Add consecutive tasks
- **WHEN** the user adds a valid task with Return and then types and submits the next name
- **THEN** each submitted task appears at the end in submission order, the composer keeps input focus without resigning, and the keyboard stays still throughout — no dismiss/reopen cycle of any duration

#### Scenario: New task expands in at the end
- **WHEN** the user submits a valid draft
- **THEN** the new row expands from zero to full height at the end of the list; under Reduce Motion the insertion uses a non-expanding transition instead

#### Scenario: Focus survives the save round-trip
- **WHEN** the user submits a valid draft
- **THEN** the draft clears and the same field stays focused through the store write and snapshot reload without ever resigning first responder; no list, suggestion, or empty-state change steals focus, and a resign/reopen flicker of any duration fails this requirement. The resign is prevented at dispatch — the field never leaves first responder — never repaired by refocusing.

#### Scenario: Chips filter as you type
- **WHEN** the user types with the keyboard open
- **THEN** the fixed chips line between the composer and the keyboard shows the prefix-filtered Recents, and an empty draft shows the full capped strip

#### Scenario: Fill from a chip
- **WHEN** the user taps a chip
- **THEN** its exact text fills the composer for editing or submission, no task is created, and no timer starts

### Requirement: An open task starts the existing timer

Activating Start on an open task SHALL start that exact task in one tap when no timer is active and return to Track after a successful start. Returning to Track after a successful start SHALL present the running timer immediately, with no further navigation required. The existing Track name and exact-text category inheritance rules SHALL apply. While a run is active, saving, or awaiting a Stop retry, the planner SHALL remain usable except for starting another task. A task rename SHALL NOT change the locked timer name.

#### Scenario: Track shows the running timer at once
- **WHEN** the user starts an open task from the planner and returns to Track
- **THEN** Track presents the running state for the started task immediately, with no extra navigation required

#### Scenario: Start without replacing a timer
- **WHEN** a task Start is invoked while another run is active
- **THEN** no replacement starts and the user can still edit the checklist

#### Scenario: Start one of two identically named tasks
- **WHEN** an idle user starts one of two tasks with the same name and later successfully stops the timer
- **THEN** the ordinary timer saves its entry and only the explicitly selected task becomes done
