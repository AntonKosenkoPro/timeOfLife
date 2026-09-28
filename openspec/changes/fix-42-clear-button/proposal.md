## Why

Issue #42 ("Add clear button to activity name text entry") shipped a trailing `×` on the Track name field and the entry-form name row, but the follow-up comment reopens three gaps: (1) the button shows whenever the field holds text, even unfocused — it must appear only when the field is focused AND contains text; (2) the Notes field in the entry-editing and Log Time forms has no clear button, and every other text entry in the app was never audited; (3) the current button styling (full `.body` glyph in `Theme.textSecondary` on a 44 pt frame) looks oversized and dark next to the field — the reference screenshot shows the Apple-standard trailing `×`: a small dim `xmark.circle.fill` tucked inside the field edge.

## What Changes

- Visibility rule: every clear button in the app shows only when its field is focused AND holds non-empty text (locked/read-only forms never show one). The rule lives in testable form (`ClearButtonVisibility.shouldShow(isFocused:text:isLocked:)`) so unit tests pin it.
- Audit + coverage: Track name, entry-form name, entry-form notes, and the category-editor name all get the button; email-OTP, one-time-code, and search (none exist) are deliberately excluded with reasons in `design.md`.
- Restyle `ClearTextButton` to the reference: 17 pt `xmark.circle.fill` in system `.secondary`, 44 pt tap target kept for accessibility, per-field accessibility label (`name.clear` for names, new `notes.clear` for notes, en+ru).
- Non-goals: toolbar/nav buttons (#50's agent), picker layout (#51's agent), icons, OpenAPI, store/sync.

## Capabilities

### New Capabilities

(none)

### Modified Capabilities

- `timer-capture-experience`: Track name clear gains the focused-AND-non-empty rule and the Apple-standard look.
- `entry-editor`: entry-form name clear gains the focus condition; Notes row gains a clear button + `clearNotes()`.
- `category-management`: category-editor name field gains a clear button through an opt-in on the shared field component.

## Impact

- `ios/TimeOfLife/TimeOfLife/Core/Design/Components/ClearTextButton.swift` (rule helper + restyle + per-field label), `TextFieldWithError.swift` (opt-in clear affordance, used only by the category editor).
- `TrackContent.swift` name region, `LogTimeView.swift` name + notes regions, `LogTimeViewModel.clearNotes()`, `CategoryEditorView.swift` name region.
- New `L10n` key `notes.clear` (en+ru) + `LocalizationTests` count bump. No store/sync/OpenAPI/backend changes.
