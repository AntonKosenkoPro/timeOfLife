# Activity Detail Sheet Specification

## Purpose

Lets users see an activity in full from the History tab: tapping an entry row opens a sheet with the activity's identity (each field shown exactly once), a visually separated day-grouped entry list showing only entry data, and an edit-activity route.

## Requirements

### Requirement: Activity detail sheet presentation
The app SHALL present an activity detail sheet when the user taps a History entry row. The sheet SHALL start at the medium detent and be draggable to large. The sheet SHALL be dismissible by swipe or by the system dismiss affordance.

#### Scenario: Open from a History tap
- **WHEN** the user taps a History entry row
- **THEN** the activity detail sheet is presented at medium detent and can be dragged to large

#### Scenario: Dismiss the sheet
- **WHEN** the user swipes the sheet down
- **THEN** the sheet dismisses and History remains in its prior state

### Requirement: Sheet header shows each activity field exactly once
The sheet SHALL show the activity name as the toolbar title and the "Edit activity" action in the toolbar. The sheet body header SHALL show the activity's icon, a Categories line (each category with its own icon, prefixed by a localized "Categories" label), and the activity notes (description) when present — and SHALL NOT repeat the activity name. The Categories line SHALL always be shown; an activity with no categories SHALL show a localized "none" value. No activity field SHALL appear more than once on the sheet. The all-time total lives on the Entries section header, not in the activity header.

#### Scenario: Name and edit live in the toolbar
- **WHEN** the sheet opens for an activity
- **THEN** the toolbar shows the activity name as its title and an "Edit activity" action, and the body header contains no second copy of the name

#### Scenario: Header shows icon, categories, notes
- **WHEN** the sheet opens for an activity with two categories and notes
- **THEN** the header shows the activity icon, a "Categories" line with each category's icon and name, and the notes text — each exactly once

#### Scenario: Activity without categories
- **WHEN** the sheet opens for an activity with no categories
- **THEN** the header shows a "Categories: none" line (localized)

#### Scenario: Activity without notes
- **WHEN** the sheet opens for an activity with no notes
- **THEN** no description row is shown

### Requirement: Entry list is visually separated and day-grouped
A divider SHALL separate the activity header from the Entries section. The section SHALL list every committed entry of the activity grouped by the day each entry started on, newest day first, entries within a day newest first. Day-group headers SHALL use the same relative-then-absolute labels as the History list ("Today", "Yesterday", "Sep 3", "Oct 5, 2025") rendered slightly larger than entry-row text. The list SHALL be lazily loaded (no upfront cap). Each row in the sheet SHALL NOT respond to taps.

#### Scenario: Full history of the activity
- **WHEN** the sheet opens for an activity tracked on multiple days
- **THEN** all of its committed entries are shown, grouped by day like the History list, ordered newest day first, below a divider separating them from the activity header

#### Scenario: Lazy loading
- **WHEN** the user scrolls the entry list beyond the initially rendered portion
- **THEN** older entries load without a visible interruption

### Requirement: Entry rows show only entry data
Each entry row SHALL show only data belonging to the entry: the start–finish time range, the entry provenance (a shared sync icon plus the localized source name; nothing for `manual` entries), and the duration right-aligned. Rows SHALL NOT repeat the activity name, icon, or categories. An entry whose start and end fall on the same calendar day SHALL show bare times; an entry spanning midnight SHALL prefix both endpoints with their day labels.

#### Scenario: Same-day entry row
- **WHEN** the sheet shows an entry starting and ending today
- **THEN** the row shows bare times (e.g. "2:34 PM – 5:46 PM"), the provenance, and the duration — no activity name, icon, or categories

#### Scenario: Cross-midnight entry row
- **WHEN** the sheet shows an entry starting yesterday at 11:34 PM and ending today at 0:34 AM
- **THEN** the row shows both endpoints with day labels (e.g. "Yesterday, 11:34 PM – Today, 0:34 AM")

#### Scenario: Provenance on sheet rows
- **WHEN** the sheet shows an entry with `source='garmin'`
- **THEN** the row shows the shared sync icon plus the localized source name (e.g. "Garmin"), not the "via Garmin" caption form used in the History list

### Requirement: Entries section header shows the all-time total
The Entries section header SHALL show the "Entries" title and the activity's all-time tracked total (sum of committed entries' durations) as "Total: <duration>". The duration SHALL use the three-component format (up to three largest `w/d/h/m/s` components, largest first, zero components omitted, seconds always shown when minutes are shown even as `0s`, e.g. "2w 5d 11h", "1h 52m 31s", "1h 5m 0s"). Entry durations in rows SHALL use the same format. The running session (if this activity is being timed) SHALL NOT appear in the sheet or contribute to the total.

#### Scenario: Total with entries
- **WHEN** the sheet opens for an activity with committed entries totaling 12h 40m 5s
- **THEN** the Entries header shows "Total: 12h 40m 5s"

#### Scenario: Running session excluded
- **WHEN** a timer is currently running for this activity
- **THEN** the running session does not appear in the entry list and does not contribute to the total

### Requirement: Sheet routes to the activity editor
The sheet SHALL offer an "Edit activity" action that presents the existing activity editor stacked on top of the detail sheet. Dismissing the editor (via Save or Cancel) SHALL return to the detail sheet. Saved changes (name, icon, categories) SHALL be reflected in the sheet after the editor is dismissed.

#### Scenario: Edit activity
- **WHEN** the user taps "Edit activity" and renames the activity in the editor
- **THEN** the editor is stacked over the detail sheet, and after dismissing the editor the sheet shows the updated name

#### Scenario: Save closes the editor
- **WHEN** the user taps Save in the activity editor with valid changes
- **THEN** the editor dismisses and the detail sheet shows the saved values

#### Scenario: Return from editor
- **WHEN** the user cancels the activity editor
- **THEN** the detail sheet remains as it was

### Requirement: Sheet is unavailable for a deleted activity
An activity's committed entries die with the activity (cascade deletion). The sheet SHALL never show an activity that no longer exists; when the underlying activity is deleted while the sheet is open, the system SHALL dismiss the sheet.

#### Scenario: Activity deleted while sheet is open
- **WHEN** the activity shown in the sheet is deleted (e.g., from another surface in a future change)
- **THEN** the sheet dismisses and the History list no longer contains that activity's entries
