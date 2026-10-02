## MODIFIED Requirements

### Requirement: Entry-form Notes row has a clear button
The entry-form Notes row SHALL offer a trailing clear (`×`) button with the same visibility rule (focused AND non-empty, editable only) and the same Apple-standard look. One tap SHALL clear the draft notes only (name, categories, and interval untouched; the validity gate re-evaluates) and SHALL keep the Notes field focused with the keyboard open. The button carries the `EntryNotesClearButton` identifier and a "Clear notes" accessibility label. Taps elsewhere in the card — including category-chip taps — SHALL still resign focus exactly as today; only the notes `×` tap suppresses the resign, once.

#### Scenario: Notes clear clears the draft notes
- **WHEN** the Notes field is focused, holds text, and the form is editable
- **THEN** a trailing `×` is visible, and one tap empties the notes while name, categories, and Start/End stay unchanged

#### Scenario: Notes clear keeps the keyboard open
- **WHEN** the user taps the Notes `×` while the Notes field is focused
- **THEN** the notes empty, the field stays focused, and the keyboard remains open for immediate typing

#### Scenario: Notes clear hidden when nothing to clear
- **WHEN** the Notes field is empty, unfocused, or the form is LOCKED (read-only)
- **THEN** no clear button is shown

#### Scenario: Chip taps still resign after the fix
- **WHEN** the user taps a category chip (or elsewhere in the card) rather than the notes `×`
- **THEN** focus resigns exactly as before — the one-shot suppress applies to the notes `×` tap only
