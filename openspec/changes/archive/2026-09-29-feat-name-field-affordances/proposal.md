## Why

Name entry is the highest-frequency text input in the app (Track field + entry-form name) and has no affordances: no way to clear a mistyped name in one tap (#42), and no suggestions from what the user already logs (#43). Track already has exact-text Recents chips (cap 6) — autocomplete should build on that history, not on a new activity entity (there is none by design).

## What Changes

- Clear button: a trailing `×` affordance on the name fields that need it (Track `TimerNameField`, entry-form `EntryNameRow`, and any other entry needing one found during implementation), clearing the draft text in one tap. Custom SwiftUI button (no native `clearButtonMode` in SwiftUI).
- Autocomplete: suggestions drawn from recent/committed entry texts as the user types (exact-text history, consistent with the Recents rule — `Gym` ≠ `GYM`); picking a suggestion fills the field (and inherits that entry's ordered categories, matching the Recents tap contract).
- Must not rewrite history: suggestions only fill the draft; committed entries are never mutated.
- Non-goals: icon work (see `feat-category-icons-lifedomains`), duration display (see `feat-entry-duration-subtitle`).

## Capabilities

### New Capabilities

(none)

### Modified Capabilities

- `timer-capture-experience`: Track name field gains clear + autocomplete over recent texts.
- `entry-editor`: entry-form name row gains the same affordances.

## Impact

- `ios/TimeOfLife/TimeOfLife/Features/TimeTracking/Views/TrackContent.swift`, `TrackViewModel` (recents source).
- `ios/TimeOfLife/TimeOfLife/Features/ManualEntry/Views/LogTimeView.swift` (+ view model draft wiring).
- New `L10n` strings (accessibility labels) in en+ru. No store/sync/OpenAPI changes.
