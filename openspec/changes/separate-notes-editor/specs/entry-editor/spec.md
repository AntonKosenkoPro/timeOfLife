## MODIFIED Requirements

### Requirement: Entry-form Notes row has a clear button
The entry-form Notes row SHALL present a read-only multiline presenter instead of an inline editor: a `Text` label with a 1–5 line window that shows the localized notes placeholder when the draft notes are empty and truncates past 5 lines. The presenter SHALL carry the caption row with a trailing chevron in balanced corner margins (the caption row's top inset equals the card's trailing inset; approved spike variant B). Tapping the presenter SHALL push a dedicated Notes editor page carrying X (cancel/discard) and ✓ (save/commit) in the navigation bar with no system Back button (X is the sole cancel path; swipe-back still pops and discards). The editor SHALL be a multiline `TextEditor` where Return inserts a newline and never dismisses the keyboard (there is no keyboard Done key); dismissal and commit happen only through X/✓ (plus the system push-pop). X SHALL discard keystrokes and restore the pre-open draft; ✓ SHALL write the edited text back to the form draft (name, categories, and interval untouched; the validity gate re-evaluates) and pop. The 280-rune notes cap is unchanged. In LOCKED mode the presenter SHALL render multiline read-only (disabled and dimmed) with no editing and no navigation. All strings localized (EN + RU), `Theme` semantic colors only.

#### Scenario: Return inserts a newline
- **WHEN** the Notes editor page field is focused and the user presses Return
- **THEN** a newline is inserted, the keyboard stays open, and the page draft is preserved

#### Scenario: Three-line reserve is stable
- **WHEN** the form opens with empty or short notes at any Dynamic Type size
- **THEN** the presenter occupies its 1–5 line window with no vertical jump when the draft changes or the editor page opens

#### Scenario: Overflow scrolls inside the editor
- **WHEN** the draft notes exceed the presenter window
- **THEN** the presenter truncates past line 5 while the editor page holds and scrolls the full text

#### Scenario: Placeholder shows only when empty
- **WHEN** the draft notes are empty
- **THEN** the presenter shows the localized notes placeholder, and tapping it opens the editor page; the placeholder hides as soon as any text is present

#### Scenario: Notes clear clears the draft notes
- **WHEN** the editor page holds text and the user activates X
- **THEN** the page pops with the form draft notes unchanged (keystrokes discarded) while name, categories, and Start/End stay unchanged

#### Scenario: Notes clear keeps the keyboard open
- **WHEN** the user is editing on the Notes editor page
- **THEN** typing, newline insertion, and navigation keep the keyboard open until X/✓ or the system pop

#### Scenario: Notes clear hidden when nothing to clear
- **WHEN** the form is LOCKED (read-only)
- **THEN** no editing affordance is shown and the presenter offers no editor page

#### Scenario: Tap-away resigns but the clear button never does
- **WHEN** the user taps the Notes presenter in CREATE or EDIT mode
- **THEN** the dedicated editor page pushes prefilled with the current draft notes

#### Scenario: Chip taps still resign after the fix
- **WHEN** the user taps a category chip (or elsewhere on the form) rather than the Notes presenter
- **THEN** focus resigns exactly as before and the notes draft is untouched

#### Scenario: Locked notes render multiline read-only
- **WHEN** the form opens for an imported entry with multiline notes
- **THEN** the full notes render through the presenter read-only across lines, disabled and dimmed, with no editor page and no editing

#### Scenario: Save commits notes only
- **WHEN** the user edits notes on the editor page and activates ✓
- **THEN** the page pops, the form draft notes update to the edited text, and name, categories, and Start/End stay unchanged

## ADDED Requirements

### Requirement: Entry-form push rows share caption-row chevron grammar
The editable Name and Notes rows SHALL present as push rows with the navigation chevron on the caption row (caption plus trailing chevron with balanced corner margins) and the full-width value below — single-line truncated for Name, 1–5 line truncated for Notes. LOCKED mode SHALL show no chevron and no navigation on either row.

#### Scenario: Name row chevron sits on the caption row
- **WHEN** the form opens in CREATE or EDIT mode
- **THEN** the Name row shows its chevron trailing the caption, and the value fills the full row width below

#### Scenario: Notes presenter matches the Name row
- **WHEN** the form opens in CREATE or EDIT mode
- **THEN** the Notes presenter shows the same caption-row chevron grammar as the Name row

#### Scenario: Locked rows show no chevron
- **WHEN** the form opens for an imported entry
- **THEN** neither the Name nor the Notes row offers navigation or a chevron
