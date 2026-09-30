## Why

Issue #69: the Track name-field autocomplete renders as a floating overlay that covers the Start button — even a single 44pt suggestion row overlaps the 24pt field-to-button gap, and up to 6 rows can bury Start entirely. The overlay approach (mandated by the current "without moving the main action (overlay, not layout)" sentence) trades one D10 goal (stationary action) against another (reachable action) and loses. A dedicated picker page removes the conflict by construction: typing and starting live on different screens, so there is nothing left to overlap.

## What Changes

- Add a shared dedicated name-picker page (push on the caller's `NavigationStack`): autofocused entry field pinned at top, scrollable suggestion list below, no confirm button in chrome.
- Completion is exactly two paths: tapping a suggestion row (fills exact text + that entry's full ordered categories, pops) or the keyboard Done/Return with non-empty trimmed text (keeps typed text, inheriting exact-match categories where applicable, pops). No dedicated ✓/Mark button.
- Cancel is the standard system Back (`< Track` / `< Log Time` / `< Edit entry`, chevron + edge-swipe gesture preserved): pops restoring the pre-push draft, applying nothing. Done with empty text is a no-op (gate holds); Back is always the exit, so no dead ends.
- Track idle: the name field becomes a push row (tap pushes the picker); Start stays Track-only and is never covered. Recents chips stay as the one-tap fast path.
- Entry form (CREATE sheet + EDIT push): the Name row taps into the same picker instead of the current inline suggestion list. LOCKED mode unchanged (name read-only, picker never opens).
- **BREAKING (spec-level):** the "autocomplete renders as overlay / inline list" requirements are replaced by the picker-page contract (see Modified Capabilities).

## Capabilities

### New Capabilities
- `name-picker`: the shared dedicated picker page — layout (pinned field + scrollable list), suggestion source/filter contract, completion/cancel semantics, accessibility, empty states.

### Modified Capabilities
- `timer-capture-experience`: Track name-field autocomplete requirement changes from floating overlay to pushing the shared picker; Track idle field becomes a push affordance; Start reachability guaranteed by construction.
- `entry-editor`: entry-form Name-row autocomplete requirement changes from inline list to pushing the same shared picker; gestures requirement confirmed (standard back + edge gesture preserved, no exception).

## Impact

- iOS only, no backend/API change (`openapi.yaml` untouched). Affected: `Features/TimeTracking/Views` (Track idle field, removal of `nameSuggestionsCard` overlay), `Features/ManualEntry/Views/LogTimeView` (removal of inline `nameSuggestions`), new shared `NamePicker` view + `Suggestion` mapping, `TrackViewModel`/`LogTimeViewModel` reuse of existing pure `nameSuggestions()` filters (no logic change), `L10n` + EN/RU strings for picker title/hints, previews + UI tests (push/pop steps).
- Non-goals: row metadata beyond text (+ first-category icon); changing the prefix-filter/exact-match-identity rules; un-capping recents beyond 6; LogTime picker nesting beyond one push; keyboard-avoidance rework.
