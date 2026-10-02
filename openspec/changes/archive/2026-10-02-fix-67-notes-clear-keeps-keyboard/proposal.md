## Why

Tapping the entry-form Notes `×` dismisses the keyboard along with clearing the field (issue #67). Per FURPS Timetracking F13 the clear button SHALL clear the field only — focus and keyboard must survive — so the user can keep typing notes immediately after clearing.

## What Changes

- Notes-only B1 suppress-flag: `FormCard` gains a one-shot suppress-next-resign flag set by the notes `×` call-site; the `clearNotes()` path sets it, so the card's tap-to-resign gesture skips exactly one resign while chip taps (which never set it) resign exactly as today.
- No other `×` site changes: NamePicker `×` (gesture-free `FieldCard`, `EditorChrome.swift:17-34`) and category `×` (gesture-free `TextFieldWithError.swift:37-58`) already keep focus correctly and stay untouched.
- `ClearTextButton.swift:23-60` still never touches focus; `ClearButtonVisibility` (focused AND non-empty, #42 rule) unchanged; `FormCard` doc comment updated to describe the one-shot flag.
- Only the notes `×` lives inside a resigning card (`LogTimeView.swift:295-321` notesCard = `FormCard(EntryNotesRow)` with `.simultaneousGesture(Tap→focusedField=nil)` at `FormCard.swift:45`, intentional for TagSelector chips in `EntryCategoriesRow :278`).

## Capabilities

### New Capabilities

- None.

### Modified Capabilities

- `entry-editor`: Entry-form Notes clear keeps focus — tap notes `×` empties notes, keyboard stays open, visibility rule unchanged; taps elsewhere in the card (incl. category chips) still resign as today.

## Impact

- Affected code: `FormCard.swift` (one-shot flag + doc comment), notes `×` call-site / `clearNotes()` path (`LogTimeView.swift:295-321`); `ClearTextButton.swift`, `ClearButtonVisibility`, `EditorChrome.swift` FieldCard, `TextFieldWithError.swift` untouched.
- No API, OpenAPI, sync, persistence, navigation, or validation-gate changes; name/categories/interval untouched by notes clear (existing contract).
- Non-goals (explicit): #42 visibility rule (focused AND non-empty) unchanged and never locked; no change to NamePicker/category `×`, chip-tap resign, tap-outside-to-dismiss, or LOCKED-mode hiding.
