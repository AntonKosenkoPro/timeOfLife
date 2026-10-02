# Entry Editor Specification

## Purpose

Lets users correct and remove logged time with one shared surface: the entry form used for manual creation also edits a committed entry's activity and interval, or deletes it with confirmation and shake-to-undo — while imported entries stay read-only except for delete.
## Requirements

### Requirement: Unified entry form with CREATE, EDIT, and LOCKED modes
The app SHALL provide a single entry form with three modes sharing one layout — input cards in Name → Start → End → Categories → Notes order (Start and End as separate cards with date + time pills and inline single-open pickers; device locale and calendar) — and one validity gate (the confirm action is enabled only when the trimmed name is non-empty AND the end is strictly after the start; otherwise disabled with no error text). CREATE mode SHALL behave per the manual-entry capability (Log Time copy, X/✓ chrome, sheet presentation). EDIT mode SHALL be titled "Edit entry" (localized) with Back + checkmark actions in the navigation bar when pushed. LOCKED mode SHALL show the entry read-only with Back only and no confirm action. The form SHALL use Theme semantic colors only, with all user-facing strings localized (EN + RU). With any inline picker expanded, the form SHALL keep its card margins on 320 pt screens: no card goes edge-to-edge and no content clips at the screen edges. The Start and End cards SHALL stretch to the same full card width as the Name, Categories, and Notes cards in every mode, whether their inline picker is collapsed or expanded: a collapsed card SHALL NOT hug its date/time pills.

#### Scenario: Edit mode titles and actions
- **WHEN** the form opens for an existing `manual` entry
- **THEN** the title reads "Edit entry" (localized) with Back and a ✓ confirm action — the same Name/Start/End/Categories/Notes cards as creation

#### Scenario: Validity gate applies in edit mode
- **WHEN** the form holds an end equal to or before the start, or an empty trimmed name, in EDIT mode
- **THEN** the confirm action is disabled with no error text, matching creation behavior

#### Scenario: Locked mode titles and actions
- **WHEN** the form opens for an entry with a non-`manual` source
- **THEN** the title identifies the entry as imported with Back only and no confirm action

#### Scenario: Collapsed Start/End cards stretch full width
- **WHEN** the form opens (or all inline pickers are collapsed) in any mode
- **THEN** the Start and End cards span margin-to-margin exactly like the Name, Categories, and Notes cards, with the date + time pills leading-aligned inside

#### Scenario: Expanded picker stays inside the cards on small screens
- **WHEN** the user expands a date or time picker on a 320 pt screen in any mode
- **THEN** the cards keep their horizontal margins, the picker renders within the card width, and no text or control touches or clips at the screen edges
### Requirement: EDIT mode saves through last-write-wins update
EDIT mode SHALL prefill the Name, Categories, Notes, and Starts/Ends pills from the entry. Activating Save on a valid form SHALL persist the changes through the local store's last-write-wins entry update (bumping `updated_at`, enqueuing the sync outbox row in the same transaction), dismiss the form, and refresh the underlying lists so the entry appears with its new values in the correct day group. Overlapping entries and future end-times SHALL be allowed, matching creation. Retexting or retagging SHALL affect only this entry. When the record changed underneath (stale write), the app SHALL show a localized error with the draft intact and the form open.

#### Scenario: Successful edit
- **WHEN** the user changes the end time of a `manual` entry and activates Save
- **THEN** the form dismisses and the entry shows the new interval and derived duration in its day group

#### Scenario: Stale write keeps the draft
- **WHEN** Save loses the last-write-wins race (the entry changed underneath, e.g. by sync)
- **THEN** a localized error is shown, the draft is preserved, and the form stays open

#### Scenario: Reassignment moves the entry
- **WHEN** the user retexts or retags an entry and saves (reassignment is now per-entry text/category change, not a move between activities)
- **THEN** the entry shows the new values in History and no other entry with the old text changes

#### Scenario: Overlap is allowed in edit mode
- **WHEN** the edited interval overlaps another entry
- **THEN** Save stays enabled and saving succeeds
### Requirement: Entry delete needs confirmation and enters the undo buffer
EDIT and LOCKED modes SHALL offer a destructive Delete action at the bottom of the form (below the input cards, red destructive styling). Activating it SHALL present a destructive confirmation alert titled "Delete this entry?" with an entry-focused message naming the entry's text (never an activity — no activity entity exists); confirming SHALL remove the entry from all lists immediately, enter the durable undo buffer (full snapshot, no outbox row yet — the relay is never notified of an undone deletion), dismiss the form, and refresh the underlying lists. No UndoToast SHALL be shown in this change. The deletion SHALL stay restorable through the DEFAULT system Undo confirmation until the app restarts (no wall-clock window): shaking the device surfaces the system Undo prompt, and confirming restores exactly one entry — the most recent buffered deletion (the registration is cleared-then-single, so one shake+confirm can never restore two). Cold launch SHALL commit the deletion (outbox delete row) with no restore path afterwards. Only the most recent buffer row SHALL be restorable (supersession, including across surfaces — an entry delete followed by a category delete leaves only the category undoable on this surface). Dismissing the confirm alert SHALL leave the entry and the draft unchanged.

#### Scenario: Confirmed delete removes the entry
- **WHEN** the user confirms deletion of an entry
- **THEN** the form dismisses and History no longer shows the entry

#### Scenario: Delete confirmation cancels cleanly
- **WHEN** the user dismisses the delete confirmation without confirming
- **THEN** the entry is unchanged and the form draft is intact

#### Scenario: Shake offers the system Undo confirmation, confirm restores one entry
- **WHEN** the user shakes the device after confirming an entry deletion while the process is still alive
- **THEN** the system Undo confirmation is offered, and confirming restores the entry with its text and values back into its day group, with nothing synced (one shake+confirm restores at most one deletion — the most recent one)

#### Scenario: Expired deletion commits on foreground
- **WHEN** the buffered deletion is still present at restart (no wall-clock window — restorable until restart)
- **THEN** the deletion commits and syncs as a hard delete with no restore path

### Requirement: Imported entries are read-only except delete
Entries with a non-`manual` source SHALL open in LOCKED mode: the Activity row, Starts/Ends pills, and pickers SHALL be disabled (dimmed, non-interactive) and no Save action SHALL be present. The form SHALL show a read-only provenance note with the localized source name explaining that editing is disabled to avoid conflicts with the external source of truth. Delete (with confirmation, into the undo buffer) SHALL remain available in LOCKED mode.

#### Scenario: Locked controls cannot be changed
- **WHEN** the form opens for an entry with `source='garmin'`
- **THEN** Activity, Starts, and Ends are disabled and dimmed, no Save is offered, and a note names the source and states editing is disabled

#### Scenario: Imported entry can still be deleted
- **WHEN** the user deletes an imported entry and confirms
- **THEN** the entry enters the undo buffer exactly like a manual entry (restorable by shake within 30 s)

### Requirement: Entry-form name clear shows only when focused and non-empty
The entry-form Name row's trailing clear (`×`) button SHALL be visible only when the field is focused AND holds non-empty text and the form is editable (hidden in LOCKED mode, when unfocused, or when empty); one tap SHALL clear the draft name (categories, notes, and interval untouched; the validity gate re-evaluates). The button uses the Apple-standard trailing look (small dim `xmark.circle.fill`, 44 pt tap target).

#### Scenario: Name clear hidden when unfocused
- **WHEN** the entry-form name field holds text but is not focused
- **THEN** no clear button is shown

#### Scenario: Name clear clears the draft name
- **WHEN** the entry-form name field is focused, holds text, and the form is editable
- **THEN** a trailing `×` is visible, and one tap empties the field while categories, notes, and Start/End stay unchanged

### Requirement: Entry-form Notes row has a clear button
The entry-form Notes row SHALL offer a trailing clear (`×`) button with the same visibility rule (focused AND non-empty, editable only) and the same Apple-standard look. One tap SHALL clear the draft notes (name, categories, and interval untouched; the validity gate re-evaluates). The button carries the `EntryNotesClearButton` identifier and a "Clear notes" accessibility label.

#### Scenario: Notes clear clears the draft notes
- **WHEN** the Notes field is focused, holds text, and the form is editable
- **THEN** a trailing `×` is visible, and one tap empties the notes while name, categories, and Start/End stay unchanged

#### Scenario: Notes clear hidden when nothing to clear
- **WHEN** the Notes field is empty, unfocused, or the form is LOCKED (read-only)
- **THEN** no clear button is shown

### Requirement: Unified entry form field order
The unified entry form SHALL lay out its input cards in exactly this order in every mode (CREATE, EDIT, LOCKED): Activity name → Start time → End time → Categories → Notes. Start and Ends SHALL be separate cards (one `timeRow` each with its own date + time pills and inline single-open picker), not one combined Starts/Ends card. The validity gate, picker behavior (single-open, device locale/calendar), mode chrome (titles/actions/LOCKED dimming + provenance note), and bottom destructive Delete are unchanged.

#### Scenario: Card order in CREATE mode
- **WHEN** the Log Time sheet opens for a new entry
- **THEN** the cards read top-to-bottom: Name, Start, End, Categories, Notes

#### Scenario: Card order in EDIT mode
- **WHEN** the form opens for an existing `manual` entry
- **THEN** the cards read top-to-bottom: Name, Start, End, Categories, Notes with the same pills/pickers as creation

#### Scenario: Card order in LOCKED mode
- **WHEN** the form opens for an imported entry
- **THEN** the cards read top-to-bottom: Name, Start, End, Categories, Notes, disabled-dimmed with the provenance note and no Save action

### Requirement: All native gestures work in the entry form
The entry form SHALL NOT disable, block, or work around any system gesture to accommodate layout. Pull-down-to-scroll SHALL scroll the form with any picker open or closed; swipe-down-to-dismiss SHALL dismiss the sheet/cover presentation; the edge-back gesture SHALL pop the form wherever a back stack exists; tapping outside a focused text field SHALL dismiss the keyboard. If a presentation kills a system gesture, the presentation SHALL change (navigation push or interactive dismiss) rather than patching the gesture.

#### Scenario: Scroll with picker open
- **WHEN** a date or time picker is expanded and the user drags vertically starting outside the picker wheels
- **THEN** the form scrolls; the wheel picker never traps the scroll gesture

#### Scenario: Dismiss and back gestures
- **WHEN** the form is presented and the user swipes down (sheet/cover) or swipes back from the leading edge (pushed onto a navigation stack)
- **THEN** the form dismisses/pops with the draft discarded and no entry created or changed

#### Scenario: Keyboard dismissal
- **WHEN** the name or notes field is focused and the user taps outside the field or scrolls
- **THEN** the keyboard dismisses and the draft is preserved

### Requirement: Entry form shows a live duration subtitle in the navigation bar
The entry form SHALL show a live duration subtitle in the form's navigation bar in every mode (CREATE, EDIT, LOCKED): a `ToolbarItem(.principal)` VStack with the mode title (`Log Time` / `Edit entry` / `Imported entry`, localized) plus a footnote duration line. The duration line SHALL update live from the already-`@Published` `startsAt`/`endsAt`, formatted with the History natural-language duration (`33s`, `1m 20s`, `1h 12m`, `1d 12h`) prefixed by the localized `Duration` label. When the interval is invalid (End equal to or before Start, confirm disabled), the subtitle SHALL show a localized explanatory text (e.g. `End must be after Start`) in `Theme.danger` instead of a duration — it explains *why* the confirm action is disabled. The subtitle SHALL use `Theme` semantic colors only, with all user-facing strings localized (EN + RU); the footnote line SHALL be a single line (inline-mode truncation).

#### Scenario: Valid interval shows a live duration
- **WHEN** the form holds an end strictly after the start
- **THEN** the nav bar shows the mode title plus a footnote `Duration: <natural-language duration>` line that updates as Start/End change

#### Scenario: Invalid interval explains why the confirm is disabled
- **WHEN** the form holds an end equal to or before the start
- **THEN** the nav bar footnote shows the localized invalid-interval text in `Theme.danger` instead of a duration

#### Scenario: Locked mode keeps the read-only subtitle
- **WHEN** the form opens for an imported entry
- **THEN** the subtitle shows that entry's fixed interval duration (or the invalid text), never editable

### Requirement: Entry-form name row has autocomplete suggestions
(Clear-button behavior for this row — focused-AND-non-empty visibility, editable only — is owned by the "Entry-form name clear shows only when focused and non-empty" requirement.) The entry-form Name row SHALL open the shared dedicated name-picker page (`name-picker` capability) instead of rendering an inline suggestion list. Tapping the Name row in an editable form (CREATE or EDIT mode) SHALL push the picker prefilled with the current draft name. Picking a suggestion or completing with Done SHALL fill the field with that exact text and inherit that entry's full ordered categories (the Recents tap contract); suggestions SHALL cover every committed name (newest-first, uncapped) and SHALL never mutate committed history. LOCKED mode is unchanged: the Name row stays read-only and never opens the picker.

#### Scenario: Tapping the Name row opens the picker
- **WHEN** the user taps the entry-form Name row in CREATE or EDIT mode
- **THEN** the shared picker pushes prefilled with the current draft name

#### Scenario: Typing shows prefix suggestions
- **WHEN** the user types a non-empty prefix matching one or more committed names on the picker page
- **THEN** those names are suggested newest-first, including the exact text already in the field

#### Scenario: Picking a suggestion fills text plus categories
- **WHEN** the user picks a suggestion or completes with Done on the picker page
- **THEN** the field fills with that exact text and the ordered categories become that entry's categories; no committed entry changes

#### Scenario: Exact-text identity is case-sensitive
- **WHEN** committed names hold both `Gym` and `GYM` and the user types `g`
- **THEN** both are suggested; typing the exact `Gym` suggests `Gym` itself (plus longer prefix matches)
