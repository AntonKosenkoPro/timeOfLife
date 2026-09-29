## 1. Reproduce + evidence (bugfix-process steps 1–3)

- [x] 1.1 Build `origin/main` (d7501da) for a booted simulator; confirm by code + on-device that (a) Track/entry-name clear shows unfocused, (b) notes has no clear, (c) styling is full-`.body` `Theme.textSecondary` vs the reference small dim ×.
- [x] 1.2 Download the issue reference image and view it before styling (design.md decision 4 records the values).

## 2. OpenSpec proposal (step 5)

- [x] 2.1 `proposal.md` → delta specs (`timer-capture-experience`, `entry-editor`, `category-management`) → `design.md` (audit table, restyle values) → this `tasks.md`.
- [x] 2.2 `openspec validate fix-42-clear-button --strict` passes; fix all findings.

## 3. Red tests first (step 6)

- [x] 3.1 New `ClearButtonVisibilityTests`: focused&&non-empty matrix (focused+text→show; unfocused+text→hide; focused+empty→hide; locked→hide) — MUST FAIL before the fix (no helper exists).
- [x] 3.2 `LogTimeViewModelTests`: `clearNotes()` empties notes only — MUST FAIL before the fix (no method exists).
- [x] 3.3 `LocalizationTests`: `notes.clear` en+ru parity — MUST FAIL before the strings exist.

## 4. Implementation (step 7; region-confined, parallel-agent-safe)

- [x] 4.1 `ClearTextButton.swift`: pure `ClearButtonVisibility` helper + restyle + per-field `accessibilityLabel` param (default `name.clear`). As-built (commit `2fa5608`, on `main`): 16 pt `Theme.textSecondary` at 55% opacity (spec'd 17 pt `.secondary` — 1 pt refinement, verified in 5.1/5.2 as-is); 44 pt target kept via `Theme.minTapArea`. Do NOT touch toolbar/nav (#50) or picker (#51) regions.
- [x] 4.2 `TrackContent.nameField`: visibility via helper with `nameFieldFocused`.
- [x] 4.3 `LogTimeView.nameCard` (focus condition) + `notesCard` (HStack + `EntryNotesClearButton` + focused-notes condition); `LogTimeViewModel.clearNotes()`.
- [x] 4.4 `TextFieldWithError` opt-in clear props (default off); `CategoryEditorView` opts in with `isNameFocused`.
- [x] 4.5 `L10n.notesClear` + en+ru `notes.clear`; bump `LocalizationTests` count.
- [x] 4.6 `swiftlint lint --strict` clean; warning-as-error build green; full iOS suite green (serialized per `docs/ios-test-loop.md`).

## 5. Re-verify + corners (steps 8–11)

- [x] 5.1 Re-run the step-1 repro on the fixed build (focused/unfocused × empty/text matrix on Track, entry name, notes, category editor) with screenshots.
- [x] 5.2 Corner cases: whitespace-only text (non-empty → shows; tap clears to truly empty), LOCKED form (never shows), running Track (never shows), VoiceOver labels per field, light/dark + EN/RU spot-check.
- [x] 5.3 Tests for the corners (whitespace, locked) in `ClearButtonVisibilityTests` + `LogTimeViewModelTests`.

## 6. PR (one PR targeting main)

- [x] 6.1 Push branch `fix/42-clear-button-conditions`; open PR targeting `main`, title per-issue with "Fixes #42", body with repro + red-test evidence + verification + corners. DO NOT merge. Post no `/review` comment. (Closed out 2026-09-29: landed on `main` as commit `2fa5608`; the local branch is stale and safe to delete.)
