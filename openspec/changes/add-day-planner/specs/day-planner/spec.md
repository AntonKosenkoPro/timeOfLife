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

A task SHALL hold a trimmed, valid timer name, an optional ordered category set, and optional notes; all three are edited in the task editor sheet. Task notes SHALL observe the same 2000-trimmed-rune bound as entry notes. Tasks with identical names SHALL have separate identities. The user SHALL be able to rename, reorder, complete, reopen, and delete visible tasks offline. Tapping a non-completed task SHALL open the task editor sheet — the manual entry form with the Start and End cards omitted (same Name entry behavior, Categories, Notes, order, cards, validation, and save gate); there SHALL be no inline renaming in the row. Tapping a completed task SHALL NOT open the editor. The sheet SHALL show an `In progress` subheader when editing the running task and offer delete at the bottom; delete SHALL be disabled for a running task, and tapping the disabled delete SHALL shake the subheader and play the reject haptic (NotesEditorPage overcount grammar) instead of deleting. New tasks SHALL prepend before existing Today rows. Completing or reopening a task SHALL keep its position and SHALL NOT start, stop, create, or modify a timer or time entry; completing a task SHALL play the success haptic. Completing or reopening a task SHALL NOT change the row's height or move sibling rows. Completed tasks SHALL NOT open the editor; a completed task is edited only after reopening it. The running linked task SHALL NOT be deletable — no swipe-to-delete affordance. The list SHALL NOT use an Edit button or edit-mode deletion UI; reordering SHALL run through a dedicated reorder control with no delete affordances. Each row SHALL show the task's ordered categories as small icon+name chips under the task name and a notes indicator when its notes are non-empty; the running task's row SHALL show a localized `In progress` label in the accent color instead of a Start button.

#### Scenario: Two tasks use the same name
- **WHEN** the user adds two tasks with the same valid name, then edits or removes one
- **THEN** the other row is unaffected

#### Scenario: Reopen a task after logging time
- **WHEN** the user reopens a task that was completed by Stop
- **THEN** the task becomes unfinished at its existing position, and the saved entry is unchanged

#### Scenario: Edit a task in the sheet
- **WHEN** the user renames a task and changes its categories and notes in the editor sheet and saves
- **THEN** the task updates in place with the new name, category set, and notes, and no saved entry changes

#### Scenario: Row shows categories and notes
- **WHEN** a task holds categories or non-empty notes
- **THEN** its row shows the ordered category icons and a notes indicator respectively, and VoiceOver announces both

#### Scenario: Running task reads In progress
- **WHEN** a task has an active linked timer
- **THEN** its row shows the localized `In progress` label and no Start button

#### Scenario: Toggle keeps the list still
- **WHEN** the user completes or reopens a task
- **THEN** the row keeps its exact height (the Start affordance slot is preserved in both states) and no other row moves

### Requirement: The composer supports repeated adds without dismissing the keyboard

The Today page SHALL use one inline composer fixed at the bottom of the screen with a single task list surface above it. The composer card SHALL carry a persistent leading affordance (plus icon) and a contrasting border so its purpose reads with and without typed text. While the keyboard is open, a single horizontally scrollable line of recent-activity chips drawn from newest-first Recents SHALL sit fixed between the composer and the keyboard; typing filters the chips by prefix; each chip shows its Recent's first category icon, and tapping a chip fills the composer with its exact text and stages that Recent's full category set for the created task. After a chip tap the line shows only the selected chip, rendered in the selected style (filled accent, matching the Track Recents selected presentation), until the user types again; the staged set persists until the draft clears or another chip is tapped. Submitting a valid draft SHALL play the system success haptic; tapping a chip SHALL play the selection haptic. The composer row SHALL offer a keyboard-dismiss control; Return on an empty draft SHALL dismiss the keyboard — the only submit-path resign allowed. Choosing a chip SHALL create no task and start no timer. Submitting a valid draft (keyboard Return key or the composer's Add accessibility action — there SHALL be no separate visible Add button) SHALL prepend one task at the top of the list with an expanding insertion, clear the composer, and keep the input focused with the keyboard open. When the draft matches no Recent, the chips line SHALL show a localized no-match placeholder instead of an empty strip. The field SHALL never resign first responder across a submit — no dismiss/reopen cycle of any duration. The composer SHALL suppress the Return key's default resign at dispatch (custom submit handling that never resigns), rather than restoring focus afterwards. Invalid or failed submission SHALL NOT append a row or discard the draft. Row changes SHALL use non-disruptive feedback and respect Reduce Motion.

#### Scenario: Add consecutive tasks
- **WHEN** the user adds a valid task with Return and then types and submits the next name
- **THEN** each submitted task appears at the top in reverse submission order (latest first), the composer keeps input focus without resigning, and the keyboard stays still throughout — no dismiss/reopen cycle of any duration

#### Scenario: New task expands in at the top
- **WHEN** the user submits a valid draft
- **THEN** the new row expands from zero to full height at the top of the list; under Reduce Motion the insertion uses a non-expanding transition instead

#### Scenario: Focus survives the save round-trip
- **WHEN** the user submits a valid draft
- **THEN** the draft clears and the same field stays focused through the store write and snapshot reload without ever resigning first responder; no list, suggestion, or empty-state change steals focus, and a resign/reopen flicker of any duration fails this requirement. The resign is prevented at dispatch — the field never leaves first responder — never repaired by refocusing.

#### Scenario: Chips filter as you type
- **WHEN** the user types with the keyboard open
- **THEN** the fixed chips line between the composer and the keyboard shows the prefix-filtered Recents, and an empty draft shows the full capped strip

#### Scenario: Fill from a chip
- **WHEN** the user taps a chip
- **THEN** its exact text fills the composer and its full category set is staged; the line shows only the selected chip in the selected presentation until typing resumes; no task is created, and no timer starts

#### Scenario: Submit carries staged categories
- **WHEN** the user submits a draft filled from a chip
- **THEN** the created task carries the staged full category set

#### Scenario: No matches show a placeholder
- **WHEN** the typed draft matches no Recent
- **THEN** the chips line shows the localized no-match placeholder instead of an empty strip

### Requirement: An open task starts the existing timer

Activating Start on an open task SHALL start that exact task in one tap when no timer is active and return to Track after a successful start. Starting a task SHALL copy its name, categories, and notes into the running draft; a task without categories SHALL fall back to the existing exact-text Recents inheritance for categories. While the run is active, category and notes edits SHALL converge live in both directions between the running draft and the linked task in the same chokepoint transaction; the locked timer name SHALL NOT change. Returning to Track after a successful start SHALL present the running timer immediately, with no further navigation required. The existing Track name and exact-text category inheritance rules SHALL apply. While a run is active, saving, or awaiting a Stop retry, the planner SHALL remain usable except for starting another task. A task rename SHALL NOT change the locked timer name.

#### Scenario: Track retag reaches the planner
- **WHEN** the user toggles categories while the linked timer runs
- **THEN** the planner task shows the same categories in place without navigation

#### Scenario: Planner edit reaches the running timer
- **WHEN** the user saves category or notes changes on the running task in the editor sheet
- **THEN** the running draft carries the same values with the ticker and locked name untouched, and Track refreshes in place without navigation

#### Scenario: Convergence is visible without navigating
- **WHEN** categories or notes change on either side while both Today and Track are loaded
- **THEN** each visible screen reflects the change in place without navigating away and back

#### Scenario: Track shows the running timer at once
- **WHEN** the user starts an open task from the planner and returns to Track
- **THEN** Track presents the running state for the started task immediately, with no extra navigation required

#### Scenario: Start without replacing a timer
- **WHEN** a task Start is invoked while another run is active
- **THEN** no replacement starts, the user can still edit the checklist, and the disabled Start shakes the subheader and plays the reject haptic instead of starting

#### Scenario: Start one of two identically named tasks
- **WHEN** an idle user starts one of two tasks with the same name and later successfully stops the timer
- **THEN** the ordinary timer saves its entry and only the explicitly selected task becomes done
