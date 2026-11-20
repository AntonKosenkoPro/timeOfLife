## Purpose

Let signed-in users keep a lightweight device-local checklist for the day and prepare a task's name for time tracking without recording time or changing the running timer.

## ADDED Requirements

### Requirement: Planner is a separate resizable sheet
The planner SHALL open as a separate sheet from Track, with a title, explicit dismiss action, and system dismissal gestures. On supported iPhone layouts it SHALL support half-height and full-height presentation, with a scrollable task list. It SHALL NOT replace Recents or change the timer, primary action, or running category-selector layout. Task data SHALL load on demand without delaying the initial Track snapshot.

#### Scenario: Browse without changing Track
- **WHEN** the user opens and dismisses the planner without selecting a task
- **THEN** the prepared name, running timer, categories, notes, and entry history remain unchanged

#### Scenario: Long checklist
- **WHEN** the checklist exceeds the visible sheet height or large text increases row height
- **THEN** tasks remain reachable through scrolling/expansion without clipping controls or imposing Recents' item cap

### Requirement: Tasks have explicit plain-text creation and stable identity
The planner SHALL support adding trimmed, non-empty names of at most 60 characters through a plain input and explicit Add action. Invalid input SHALL NOT create a task. Each task SHALL have independent identity; duplicate text SHALL be allowed. Tasks SHALL display oldest-created first with a stable identity tie-breaker, and checking/unchecking SHALL NOT reorder them. Stage 1 SHALL offer no name suggestions, category input, scheduled dates, or manual reordering.

#### Scenario: Add an existing name
- **WHEN** the user adds valid text that matches a task or previously tracked name
- **THEN** a new independent unfinished task is durably created, without category inheritance, a time entry, or a timer change

#### Scenario: Invalid input
- **WHEN** the input is blank after trimming or exceeds 60 characters
- **THEN** Add cannot persist it and accessible validation feedback explains the invalid input

### Requirement: Completion and removal are independent of recorded time
Each task SHALL expose a separate manual checkbox. Checking SHALL record completion; unchecking SHALL clear it. Starting or stopping timing SHALL NOT change completion. A task SHALL offer confirmed permanent local removal naming its text. Cancellation SHALL preserve the task; removal SHALL NOT participate in entry/category shake-to-undo or change any prepared/running/saved time data. Renaming tasks is outside Stage 1.

#### Scenario: Check during timing
- **WHEN** a timer is running and the user checks or unchecks a task
- **THEN** only that task's completion changes and the running timer's name, categories, notes, and timestamps remain unchanged

#### Scenario: Timing is not completion
- **WHEN** the user selects, starts, and stops timing a task's name
- **THEN** the task remains in its manually chosen completion state

#### Scenario: Confirm or cancel removal
- **WHEN** the user requests removal
- **THEN** one destructive confirmation identifies the task; Cancel keeps it and confirmation removes only that task without altering the existing entry/category Undo buffer

### Requirement: Unfinished tasks carry forward and older completed tasks expire
Unfinished tasks SHALL persist across local calendar days. At reconciliation, completed tasks with a completion timestamp strictly earlier than the start of the current device-local calendar day SHALL be permanently removed. Tasks completed during the current day SHALL remain available to uncheck. Reconciliation SHALL occur on sheet open, on active-account foreground/resume when storage is usable, and at local-day changes while the sheet is open and active. Clock/time-zone changes SHALL re-evaluate the current local boundary. No background midnight execution or daily archive SHALL be promised.

#### Scenario: Overnight while the app is inactive
- **WHEN** the app next becomes active after one or more local day boundaries
- **THEN** reconciliation removes prior-day completed tasks, keeps all unfinished tasks and today's completed tasks, and does not create or delete any time entries

#### Scenario: Open sheet crosses midnight
- **WHEN** the local day changes while the planner is open and active
- **THEN** eligible completed tasks disappear after successful cleanup without requiring dismissal/reopening; unfinished tasks stay

#### Scenario: Completion exactly at the boundary
- **WHEN** a task's completion time equals the current local day's start
- **THEN** it is retained; eligibility uses a strict earlier-than comparison rather than a fixed elapsed 24 hours

#### Scenario: Uncheck before expiry
- **WHEN** the user unchecks a retained task and later a new day begins
- **THEN** that unfinished task is retained; a subsequent check establishes a new completion timestamp

### Requirement: Planner is persistent, account-bound, and device-local
Tasks SHALL live in the same account-local storage boundary as tracker data and function offline after sign-in. Ordinary sign-out SHALL preserve tasks; re-login on the same device SHALL reopen that account's tasks subject to day cleanup. Explicit local/account-file deletion SHALL remove that account's planner data without touching other accounts. Planner operations SHALL NOT create relay operations, tombstones, or sync cursors. Cross-device sync SHALL NOT copy or restore planner tasks in Stage 1. Auth/account changes SHALL dismiss the sheet and prevent stale loads, writes, or selections from crossing account boundaries.

#### Scenario: Account switch during a pending operation
- **WHEN** account A has a pending planner operation and the device switches to account B
- **THEN** A's operation cannot read/write B's tasks or prepare B's Track name, and A's content is not published into B's sheet

#### Scenario: Local erase and relay re-login
- **WHEN** account A's local data is explicitly erased and A later signs in and syncs again
- **THEN** A's planner is empty, relay entries can sync normally, and unrelated account B's local tasks are preserved

### Requirement: Planner failures never masquerade as successful changes
Loading, empty, and failed states SHALL be distinguishable. Task creation/completion/removal/cleanup SHALL be durable before successful UI state is confirmed. Failed writes SHALL preserve the last successful state and provide a retry path; failed Add SHALL preserve submitted input. Database suspension SHALL defer work until safe resume rather than clearing the checklist or claiming success.

#### Scenario: Save fails
- **WHEN** a task write fails
- **THEN** no partial successful change is shown, the sheet remains usable for retry, and timer/history data is unchanged

#### Scenario: Suspension interrupts cleanup
- **WHEN** the database becomes unavailable during reconciliation
- **THEN** uncommitted deletions are not presented as successful and reconciliation retries after safe resume

### Requirement: Checklist controls are accessible and localized
All planner copy SHALL be localized in the five supported locales. Checkbox and name-selection actions SHALL be independently discoverable and operable with VoiceOver, communicate completion without relying on color alone, support Dynamic Type, and provide at least 44pt touch targets. Styling SHALL use the application's semantic theme, and task controls SHALL expose stable per-task automation identity.

#### Scenario: Complete without selecting
- **WHEN** a VoiceOver user activates a task's completion control
- **THEN** completion changes and is announced without selecting a Track name, dismissing the sheet, or starting timing
