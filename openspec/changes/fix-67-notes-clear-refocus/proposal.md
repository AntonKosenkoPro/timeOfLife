## Why

Issue #67 is REOPENED: the first fix (#112, merged as `7d2cb13`) does not hold on real taps. #112 armed a one-shot `suppressNextResign` flag on touch-down via a zero-distance `DragGesture` on the notes `×`, so the card's simultaneous tap gesture would skip one resign. That mechanism demonstrably fails on real taps: the touch-down suppress flag does not reliably precede the card gesture's touch-up handler for a genuine finger tap (the drag's `onChanged` delivery is not guaranteed ahead of the tap's `onEnded` on-device), so the keyboard still dismisses when the user taps the notes `×`.

## What Changes

- Replace the touch-down suppress mechanism with a touch-up re-claim: the notes `×` action clears the draft notes, then re-claims Notes focus via `DispatchQueue.main.async { focusedField = .notes }`.
- Revert `FormCard.swift` to a plain simultaneous resign (`resignFocus()` unconditionally): the `suppressNextResign` binding, its doc comments, and the flag plumbing are deleted.
- Delete the `@State suppressNotesResign` flag and the zero-distance `DragGesture` from `LogTimeView.swift` (notes card only); the `×` action itself owns the async re-claim.
- Net effect: −36 lines across 2 files. The user-visible contract is unchanged (clear notes only, keyboard stays open, taps elsewhere still resign).

## Capabilities

### New Capabilities

(none)

### Modified Capabilities

- `entry-editor`: the "Entry-form Notes row has a clear button" requirement keeps its keep-keyboard contract but changes mechanism — from touch-down one-shot resign-suppress to post-action async focus re-claim. The one-shot-suppress scenarios are superseded.

## Impact

- `ios/TimeOfLife/TimeOfLife/Features/ManualEntry/Views/FormCard.swift` — delete `suppressNextResign` binding/param, restore unconditional resign; doc-comment cleanup.
- `ios/TimeOfLife/TimeOfLife/Features/ManualEntry/Views/LogTimeView.swift` — delete `@State suppressNotesResign` + zero-distance drag; notes `×` action clears then async re-claims `.notes` focus.
- Baseline spec `openspec/specs/entry-editor/spec.md` — keep-keyboard scenarios fold out on archive (contract unchanged, mechanism replaced).
- No backend, no store, no L10n, no `project.yml` changes.

## Verification (recorded)

- **Simulator repro (identical to #112's repro):** focus Notes with text → tap `×` → keyboard stays up, no flicker, draft notes emptied, name/categories/interval untouched. Videos exist.
- **`swiftlint lint --strict`:** clean.
- **Full `xcodebuild test -scheme TimeOfLife` suite:** green.
- **Physical device (iPhone 17, Release build):** PASS — keyboard stayed up after tapping notes `×`, zero data mutations (no entries created/changed).

## Non-goals

- No change to the Name-row `×`, category chips, or any other card's resign behavior.
- No new strings, colors, or API surface.
