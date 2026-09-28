## 1. Change artifacts

- [x] 1.1 Write delta spec (`specs/entry-editor/spec.md`: collapsed Start/End cards stretch full width) + `design.md` (proven root cause with three evidence lines, call-site fix, rejected alternatives, no-test rationale) + this `tasks.md`.
- [x] 1.2 `openspec validate fix-51-picker-width --strict` passes; fix all findings.

## 2. Implementation (`LogTimeView.swift` `timeRow` only)

- [x] 2.1 Add `.frame(maxWidth: .infinity, alignment: .leading)` to `timeRow`'s root `VStack` (covers `startCard` + `endCard`, collapsed + expanded). Do NOT touch `FormCard.swift`, toolbar/nav buttons, name/notes field internals, `CatalogIcon.swift`, `openapi.yaml`, `RootView.swift`, `TrackContent.swift`.
- [x] 2.2 Rebuild + reinstall on the repro sim; re-capture CREATE collapsed, CREATE date-picker expanded, EDIT collapsed; confirm card/pill frames start at x 0.080.

## 3. Tests

- [x] 3.1 No new unit tests per `design.md` (pure layout modifier, no logic, no view-test infra — a pin-the-modifier test cannot fail). Red evidence = pre-fix screenshots + frames (§2.2 before-state); green evidence = post-fix screenshots + frames.

## 4. Corner cases (all verified on sim, CREATE + EDIT)

- [x] 4.1 Wheel time picker expanded (start + end) — full card width, no clipping.
- [x] 4.2 Graphical date picker expanded (start + end) — full card width, card margins kept.
- [x] 4.3 Dynamic Type accessibility size — pills/cards keep margins, no edge clipping.
- [x] 4.4 EDIT mode (pushed) matches CREATE (sheet): shared `formContent` guarantees it; verified by screenshot, not by assumption.

## 5. Verification + docs (S5)

- [x] 5.1 `swiftlint lint --strict` clean; warning-as-error `xcodebuild` build green; full iOS suite green (serialized per `docs/ios-test-loop.md`). Backend untouched (no `go` run; `openapi.yaml` unmodified).
- [x] 5.2 Re-check `Requirements/FURPS/Timetracking.md` rows for the entry form; fix conflicts if any.
- [x] 5.3 Push + `gh pr create` targeting `main` (title references #51, body carries "Fixes #51" + repro steps + before/after screenshots + root cause with evidence + verification + corners). DO NOT merge. Post no `/review` comment.
