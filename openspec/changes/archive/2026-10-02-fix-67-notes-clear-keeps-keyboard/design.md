## Context

See `proposal.md` — Why (notes `×` dismisses the keyboard; FURPS Timetracking F13 says clear field only). Current state and constraints needed for the approach:

- Only the notes `×` lives inside a resigning card: `LogTimeView.swift:295-321` notesCard = `FormCard(EntryNotesRow)` with `.simultaneousGesture(Tap→focusedField=nil)` at `FormCard.swift:45`, intentional for TagSelector chips in `EntryCategoriesRow :278` (chip taps must resign so the chip grid — not a text field — takes over).
- The other `×` sites are already correct and stay untouched: NamePicker `×` in gesture-free `FieldCard` (`EditorChrome.swift:17-34`), category `×` in gesture-free `TextFieldWithError.swift:37-58`.
- `ClearTextButton.swift:23-60` never touches focus; `ClearButtonVisibility` = focused AND non-empty (#42 rule), never locked.
- Invariants from `docs/project-context.md` (preserved): LocalStore single mutation chokepoint (untouched — no persistence work); Theme semantic colors only; XcodeGen-managed; iOS strings EN+RU + `L10n` (no copy changes); no OpenAPI change; incomplete surfaces not claimed done.
- No external library/framework/SDK/API behavior is load-bearing (pure SwiftUI focus/gesture ordering) — no ctx7 fetch required.

## Goals / Non-Goals

- Goals: notes `×` tap empties notes with keyboard staying open; chip taps and tap-outside resign byte-identical; #42 visibility rule unchanged.
- Non-Goals (design-level): no change to NamePicker/category `×`, no change to `ClearTextButton`/`ClearButtonVisibility`, no change to validity gate, LOCKED-mode hiding, or tap-outside-to-dismiss.

## Decisions

- **B1 suppress-flag: one-shot suppress-next-resign on `FormCard`, set only by the notes `×` call-site (`clearNotes()` path).** Rationale: the resign comes from the card-level simultaneous gesture firing alongside the button tap — suppressing exactly one resign at the source fixes only the `×` tap while chip taps (which never set the flag) flow through the unchanged gesture. Alternative (move notes `×` out of `FormCard` / remove the card gesture) rejected — would break the intentional chip-tap resign the gesture exists for. Alternative (re-focus after resign, e.g. async `focusedField = .notes`) rejected — causes keyboard flicker (dismiss + re-present) instead of never dismissing.
- **Flag is consumed one-shot, default off.** Rationale: a sticky suppress would break the next legitimate resign (e.g. immediate chip tap after clearing); one-shot keeps the state machine trivial and reviewable. Alternative (pass focus binding into the button) rejected — wider coupling for a card-local gesture concern.
- **Doc-comment the flag on `FormCard`.** Rationale: the gesture's purpose (chip resign) is non-obvious; the comment records why the suppress exists and who may set it (notes `×` only).

## Risks / Trade-offs

- [Risk] Flag left set (e.g. clear tapped while already empty / double-tap races) suppresses a later legitimate resign → Mitigation: set the flag only on the effective `clearNotes()` path and consume it on the very next card-gesture fire regardless; verify rapid `×` then chip-tap still resigns.
- [Risk] SwiftUI gesture ordering differences by OS version → Mitigation: verify on iOS 18 simulator + physical device where available at default speed; keep the mechanism to ordering-independent one-shot consume, not timing.
- [Risk] Over-scoping to other `×` sites → Mitigation: `git diff` must show only `FormCard.swift` + notes call-site; FieldCard / TextFieldWithError / ClearTextButton untouched.

## Migration Plan

- No migration, no flags, no rollback beyond reverting the `FormCard` hunk. Normal app change; no persistence, sync, or API moves.

## Open Questions

- None.
