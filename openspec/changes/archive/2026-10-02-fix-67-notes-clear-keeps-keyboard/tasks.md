## 1. Implement notes-only suppress-flag (B1)

- [x] 1.1 Add one-shot suppress-next-resign flag to `FormCard` (default off, consumed on next card-gesture fire) with a doc comment stating the card gesture exists for chip resign and only the notes `×` may set the flag.
- [x] 1.2 Set the flag on the notes `×` call-site / `clearNotes()` path (`LogTimeView.swift:295-321` notesCard) only; leave NamePicker `×` (`EditorChrome.swift:17-34` FieldCard), category `×` (`TextFieldWithError.swift:37-58`), `ClearTextButton.swift:23-60`, and `ClearButtonVisibility` untouched.
- [x] 1.3 Verify `git diff` shows only `FormCard.swift` + the notes call-site.

## 2. Acceptance + regression gates

- [x] 2.1 Acceptance: focus Notes with text → tap notes `×` → field empties, keyboard stays open, `×` hides per the unchanged focused-AND-non-empty rule; typing resumes immediately. (Verified on iPhone 17 Pro sim, fix build: "H" cleared, keyboard stayed up, `×` hidden.)
- [x] 2.2 Regression: chip taps (and tap-outside) still resign focus; NamePicker and category `×` still clear-and-keep-focus; LOCKED mode still hides `×`; validity gate re-evaluates with name/categories/interval untouched. (Verified: chip tap toggled + dismissed keyboard; other `×` sites untouched per diff; LOCKED/validity paths untouched.)
- [x] 2.3 Edge: rapid `×`-then-chip-tap still resigns (flag was one-shot); double-tap `×` leaves no stale suppress for the next resign. (Verified on device: `×` cleared, immediate chip tap toggled + dismissed keyboard. Drag-off stale documented in `FormCard` doc comment, self-heals on next fire.)
- [x] 2.4 Run `swiftlint lint --strict`, warning-as-error `xcodebuild` build, and relevant `xcodebuild test` slice; re-check `Requirements/FURPS/Timetracking.md` F13 (clear field only) plus #42 visibility rows — fix conflicts. (Lint clean, build green, full suite 556/54 green; F13 + visibility rule unchanged.)
- [x] 2.5 Confirm no docs drift beyond the change artifacts (`docs/project-context.md`, `README.md`, `Design/*`, `backend/api/openapi.yaml` unchanged unless the run steps prove otherwise).
