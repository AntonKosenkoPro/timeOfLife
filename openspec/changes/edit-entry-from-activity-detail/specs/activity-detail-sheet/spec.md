## MODIFIED Requirements

### Requirement: Entry list is visually separated and day-grouped

A divider SHALL separate the activity header from the Entries section. The section SHALL list every committed entry of the activity (entries with an end time; in-progress entries without an end time SHALL NOT appear) grouped by the day each entry started on, newest day first, entries within a day newest first. Day-group headers SHALL use the same relative-then-absolute labels as the History list ("Today", "Yesterday", "Sep 3", "Oct 5, 2025") rendered slightly larger than entry-row text. The list SHALL be lazily loaded (no upfront cap). Tapping a row SHALL open the unified entry form (see entry-editor capability) as a full-screen cover: EDIT mode for `manual` entries, LOCKED mode for imported entries.

#### Scenario: Full history of the activity

- **WHEN** the sheet opens for an activity tracked on multiple days
- **THEN** all of its committed entries are shown, grouped by day like the History list, ordered newest day first, below a divider separating them from the activity header

#### Scenario: Lazy loading

- **WHEN** the user scrolls the entry list beyond the initially rendered portion
- **THEN** older entries load without a visible interruption

#### Scenario: In-progress entries are excluded

- **WHEN** the activity has a running timer session or an entry without an end time
- **THEN** neither appears in the entry list nor contributes to the all-time total

#### Scenario: Tap opens the entry form

- **WHEN** the user taps an entry row in the sheet
- **THEN** the unified entry form opens as a full-screen cover — editable for `manual` entries, read-only (delete-only) for imported entries

## ADDED Requirements

### Requirement: Sheet refreshes after the entry form dismisses

Dismissing the entry form after Save or Delete SHALL reload the sheet's identity, categories, entries, and all-time total. An entry reassigned to another activity SHALL disappear from this sheet's list without dismissing the sheet. Deleting the sheet's last entry SHALL leave an empty Entries section (the sheet stays open). The existing deleted-activity dismissal behavior is unchanged.

#### Scenario: Saved edit refreshes the sheet

- **WHEN** the user saves an entry edit from the form opened over the detail sheet
- **THEN** the form dismisses and the sheet shows the updated entry values and recomputed total

#### Scenario: Reassigned entry leaves the sheet

- **WHEN** the user reassigns an entry of activity "Running" to activity "Reading" and saves
- **THEN** the form dismisses and the "Running" sheet no longer lists the entry, with its total recomputed, while the sheet stays open

#### Scenario: Deleted entry refreshes the sheet

- **WHEN** the user confirms deletion of an entry from the form opened over the detail sheet
- **THEN** the form dismisses and the sheet's entry list and total no longer include the entry
