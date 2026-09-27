## Why

When creating or editing an entry you cannot see the resulting duration while picking Start/End (#36). Building an entry with a particular duration is guesswork — pick, save, reopen, adjust.

## What Changes

- Show a live `Duration: 1h 30m` subtitle in the form's navigation bar (Variant 3 as decided): a `ToolbarItem(.principal)` VStack with the mode title (`Log Time` / `Edit entry`) plus a footnote duration line.
- Updates live from the already-`@Published` `startsAt`/`endsAt`; reuses the natural-language duration formatting the History rows use.
- Invalid state (End ≤ Start, Save disabled) shows an explanatory subtitle (e.g. `End must be after Start` in `Theme.danger`) instead of a duration — it explains *why* Save is disabled.
- Non-goals: changing the Start/End auto-push behavior (`LogTimeViewModel` untouched), gesture work (see `fix-entry-form-gestures`).

## Capabilities

### New Capabilities

(none)

### Modified Capabilities

- `entry-editor`: the entry form displays a live duration subtitle in the nav bar.

## Impact

- `ios/TimeOfLife/TimeOfLife/Features/ManualEntry/Views/LogTimeView.swift` (toolbar principal item only).
- New `L10n` strings in en+ru (`Duration: …`, invalid-state text); `Theme` semantic colors only.
- No store, sync, or OpenAPI changes. Display-only over existing VM state.
