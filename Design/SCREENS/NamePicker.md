# Name Picker Page

Implements the `name-picker` capability (dedicated-name-picker): the shared dedicated name-picking page pushed from Track's name row (and reused by the entry form's name field). There is no search sheet and no catalog — the picker browses committed exact-text names only.

## View: NamePicker

- **File**: `ios/TimeOfLife/TimeOfLife/Core/Design/Components/NamePicker.swift`
- **Route**: pushed on the caller's `NavigationStack` (standard system Back is the cancel path — the local draft is discarded, the caller untouched; no chrome of its own)
- **Filter**: `NamePickerFilter.suggestions(for:in:)` — case-insensitive prefix over all committed exact-text names, newest-first; the exact match is included; empty trimmed input lists everything (browsable without typing)

### Layout

- `VStack(spacing: 0)`: autofocused entry field (`FieldCard`) pinned at the top + scrollable suggestion list below.
- Content width `Theme.maxContentWidth`, horizontal padding `Theme.screenHorizontalPadding`.
- Suggestion rows: first-position category icon + exact text (category names never shown); categoryless names render text-only.
- Empty state: caller-provided `emptyHint` (`timer.recentsEmptyHint`) when no recents and nothing typed.

### Behaviors

- Caller passes `initialText`, `recents` (newest-first, already capped — picker reads only), `categories` map, `placeholder`, `emptyHint`.
- Local `draft` state: keystrokes never touch caller state. Completion is exactly two caller-owned paths: row tap → `onCompleteSuggestion` (exact text + ordered categories); keyboard Done with non-empty text → `onCompleteText` (typed text, exact-match inheritance resolved by the caller). Done with empty text is a no-op. Back cancels for free.
- Field autofocuses on appear (after the push settles); VoiceOver focus is not forced.
- `Gym` ≠ `GYM` identity preserved by case-sensitive row identity.

### Implementation checklist

- [ ] All colors use `Theme.*` tokens.
- [ ] Field placeholder + empty hint via `L10n.*` (EN + RU).
- [ ] Suggestion rows expose stable identifiers.
- [ ] No inline creation, no category management here.
