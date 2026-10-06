## Why

The entry-form Notes row is a single-line `TextField`, so the 280-rune allowance (FURPS `Activity_Catalog_and_Categories.md` U1, `local-first-store` baseline) is unusable in practice: average prose wraps past one line and gets truncated visually. With the #118 keyboard-flicker fix holding (inversion: plain tap-away + clear-only ×), the row can now grow into a true multiline field without reopening the focus race.

## What Changes

- Entry-form Notes row (`LogTimeView.notesCard`) becomes a `TextEditor`: Return inserts a newline, no keyboard Done key; dismissal stays tap-away (card label/padding via `FormCard`) + scroll-away (`.scrollDismissesKeyboard(.interactively)`).
- Fixed 3-line visible reserve at the current Dynamic Type (no layout jump when empty, typed, or when × mounts); content past 3 lines scrolls inside the editor.
- Trailing clear (×) pins top-trailing (`HStack(alignment: .top)`), keeping the existing visibility rule (focused AND non-empty, editable only), `EntryNotesClearButton` identifier, and "Clear notes" label; one tap clears notes only and keeps focus with the keyboard open (FURPS Timetracking F13, unchanged).
- Manual placeholder overlay reusing `L10n.entryNotesPlaceholder` (TextEditor has no native placeholder); `Theme` semantic colors and `.font(.body)` only.
- Notes limit stays **280 runes** (no validator, OpenAPI, or store change in this change).

Non-goals (explicit): notes limit change (deferred — measure on Pro Max at xSmall if reopened); keyboard toolbar Done button (fallback only, tap/scroll-away is the grammar); History row rendering (EntryRow shows no notes); Name row or category editor (stay single-line); backend/OpenAPI/sync changes (notes stays a string, newlines count as runes as today).

## Capabilities

### New Capabilities

- None.

### Modified Capabilities

- `entry-editor`: Notes row multiline behavior — TextEditor with newline input, 3-line reserve with inner scroll, top-trailing clear, placeholder overlay, unchanged focus/clear guarantees.

## Impact

- Affected code: `ios/TimeOfLife/TimeOfLife/Features/ManualEntry/Views/LogTimeView.swift` (notesCard only), possibly `ClearTextButton` alignment context (no shared-component API change intended); `FormCard` untouched (inherits #118 plain tap-away).
- Authoritative docs: `openspec/specs/entry-editor/spec.md` (Notes clear requirement), `Requirements/FURPS/Timetracking.md` F13 + `Activity_Catalog_and_Categories.md` U1 (280-char cap, unchanged), `Design/COMPONENTS.md` (no Notes-field component spec today).
- Systems: iOS only. No backend, OpenAPI, sync, or storage change. LOCKED mode renders the same multiline text read-only (disabled + dimmed).
- External behavior (ctx7): SwiftUI `TextEditor` — library `/websites/developer_apple_swiftui`, queries `TextEditor multiline placeholder focus dismissal` + `TextEditor`; version pin iOS 18+ (repo floor, no availability guards).
