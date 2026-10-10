## Why

History rows give no signal whether an entry carries notes, so users must tap each entry open to discover them. A small glanceable indicator makes notes discoverable while keeping rows read-only and compact.

## What Changes

- Show a small blue notes icon (`note.text` SF Symbol, `Theme.accentPrimary`) on History `EntryRow`s whose entry has non-empty notes (whitespace-only counts as empty).
- Decide the icon placement during design (candidates: trailing end of line 1 next to duration, inline after entry text, or leading edge of line 2 caption) and apply it consistently, preserving the Variant H grid and day-header column alignment.
- Entries with empty notes render exactly as today (no icon, no layout shift beyond the reserved absence).
- VoiceOver folds a localized "has notes" affordance into the existing row label; no tap/long-press/swipe behavior changes.

## Capabilities

### New Capabilities

- None.

### Modified Capabilities

- `history-entry-list`: History rows indicate non-empty entry notes with a small blue icon + accessibility affordance.

## Impact

- iOS: `Core/Design/Components/EntryRow.swift` (new `hasNotes` input + icon), `Features/AppShell/Views/HistoryView.swift` (pass-through), `Features/AppShell/ViewModels/HistoryViewModel.swift` (pure `hasNotes(for:)` helper, unit-tested).
- Design docs: `Design/COMPONENTS.md` (`EntryRow` icon row) and `Design/SCREENS/History.md` (notes-indicator rule).
- Localization: one new string (`historyHasNotes` or a11y-only suffix) in both `en.lproj`/`ru.lproj` + `L10n` if the a11y wording is not reused from an existing key.
- No backend / OpenAPI / sync / storage changes; notes content itself never renders in the row.

### Non-goals

- No notes preview/excerpt text in the row; no tap on the icon with separate behavior (whole row still opens the entry form).
- No filtering/sorting by notes; no Insights change.
