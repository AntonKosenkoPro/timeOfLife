## MODIFIED Requirements

### Requirement: Entry-form Notes row has a clear button
The entry-form Notes row SHALL be a multiline editor: Return inserts a newline and never dismisses the keyboard (there is no keyboard Done key — dismissal is tap-away on card label/padding plus scroll-away). The editor SHALL reserve a fixed 3-line visible height at the current Dynamic Type (identical height when empty, short, or when the clear button mounts) and SHALL scroll internally past 3 lines with a stable card height. When the draft notes are empty the row SHALL show the localized notes placeholder, hidden as soon as any text is present. The row SHALL offer a top-trailing clear (`×`) button with the same visibility rule (focused AND non-empty, editable only) and the same Apple-standard look. One tap SHALL clear the draft notes only (name, categories, and interval untouched; the validity gate re-evaluates) and SHALL keep the Notes field focused with the keyboard open. The button carries the `EntryNotesClearButton` identifier and a "Clear notes" accessibility label. Taps elsewhere in the card SHALL still resign focus exactly as today; the notes `×` tap SHALL never resign focus. In LOCKED mode the notes SHALL render multiline read-only (disabled and dimmed) with no clear button and no editing. The 280-rune notes cap is unchanged.

#### Scenario: Return inserts a newline
- **WHEN** the Notes editor is focused and the user presses Return
- **THEN** a newline is inserted, the keyboard stays open, and the draft is preserved

#### Scenario: Three-line reserve is stable
- **WHEN** the form opens with empty or short notes at any Dynamic Type size
- **THEN** the Notes row occupies its 3-line height, and typing or the clear button appearing causes no vertical jump

#### Scenario: Overflow scrolls inside the editor
- **WHEN** the draft notes exceed 3 lines
- **THEN** the editor scrolls internally while the card height stays fixed

#### Scenario: Placeholder shows only when empty
- **WHEN** the draft notes are empty
- **THEN** the localized notes placeholder is visible, and it hides as soon as any text is present

#### Scenario: Notes clear clears the draft notes
- **WHEN** the Notes field is focused, holds text, and the form is editable
- **THEN** a top-trailing `×` is visible, and one tap empties the notes while name, categories, and Start/End stay unchanged

#### Scenario: Notes clear keeps the keyboard open
- **WHEN** the user taps the Notes `×` while the Notes field is focused
- **THEN** the notes empty, the field stays focused, and the keyboard remains open for immediate typing

#### Scenario: Notes clear hidden when nothing to clear
- **WHEN** the Notes field is empty, unfocused, or the form is LOCKED (read-only)
- **THEN** no clear button is shown

#### Scenario: Tap-away resigns but the clear button never does
- **WHEN** the user taps card label/padding rather than the notes `×`
- **THEN** focus resigns exactly as before, while the notes `×` tap itself never resigns focus

#### Scenario: Chip taps still resign after the fix
- **WHEN** the user taps a category chip (or elsewhere in the card) rather than the notes `×`
- **THEN** focus resigns exactly as before — the notes `×` tap itself never resigns focus

#### Scenario: Locked notes render multiline read-only
- **WHEN** the form opens for an imported entry with multiline notes
- **THEN** the full notes render read-only across lines, disabled and dimmed, with no clear button
