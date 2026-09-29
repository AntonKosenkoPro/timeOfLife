## MODIFIED Requirements

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
