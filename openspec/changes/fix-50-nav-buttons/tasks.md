## 1. Change artifacts

- [x] 1.1 Write proposal + delta specs (`specs/entry-editor/spec.md`: pushed Back+`✓` chrome; `specs/manual-entry/spec.md`: sheet `X`+`✓` chrome) + `design.md` (chrome-branch choice, symbol/placement/tint, identifier stability, 3 new a11y keys) + this `tasks.md`.
- [x] 1.2 `openspec validate fix-50-nav-buttons --strict` passes; fix all findings.

## 2. Red tests first (no view-test infra — precedent: fix-entry-form-gestures §3.1)

- [x] 2.1 Added `L10n` cases `entry.dismissLabel`, `entry.confirmAddLabel`, `entry.confirmSaveLabel` WITHOUT strings entries → `LocalizationTests` FAILED red (4 tests, 13 issues: en/ru resolve ×3, parity ×6, count 140≠143; EXIT=65; log `red-evidence.log`, PR body). Then added EN + RU strings, retired `logTime.add`/`entry.save`, bumped count 140 → 141 → green (full suite 505 passed).
- [x] 2.2 `LogTimeViewModelTests` gate/prefill/save coverage pins the unchanged validity behavior (no VM change; suite stayed green throughout).

## 3. Implementation (`LogTimeView.swift` `chrome()` toolbar region ONLY)

- [x] 3.1 Pushed (`embeddedInNavigationStack`): removed the `cancellationAction` item (EDIT + LOCKED); EDIT confirm is `checkmark` with `entry.confirmSaveLabel` VO label, same `save()` + `isAddEnabled` gate + `EntryEditSaveButton` id. LOCKED: Back only.
- [x] 3.2 Sheet (CREATE): leading is `xmark` with `entry.dismissLabel` VO label + `LogTimeDismissButton` id, same `dismiss()`; trailing is `checkmark` with `entry.confirmAddLabel` VO label, same `save()` + gate + `LogTimeAddButton` id. Placements + default tint unchanged.
- [x] 3.3 Grep-verified: `logTime.cancel` still used by the delete-confirm alert (kept); retired `logTime.add`/`entry.save` removed with their strings; `CatalogIcon.swift`, `openapi.yaml`, `RootView.swift`, `TrackContent.swift`, name/notes internals, picker layout untouched.

## 4. Re-verify on simulator (pre-fix build steps = §4.1; fixed build = §4.2)

- [x] 4.1 BEFORE (done, `origin/main` build d7501da): OTP sign-in → History → `[+]` → CREATE shows `Cancel`+`Add` text (`before-create.png`); name `Gym` → Add → tap row → pushed EDIT shows `<`+`Cancel`+`Save` (`before-edit.png`); AX trees recorded.
- [x] 4.2 AFTER (fixed build): repeated §4.1 → CREATE shows `X`+`✓` (`after-create.png`; AX: `Close`/`LogTimeDismissButton` + `Add entry`/`LogTimeAddButton`, `✓` disabled on empty name); pushed EDIT shows `<`+`✓` only (`after-edit.png`; AX: `BackButton` + `Save entry`/`EntryEditSaveButton`, no `Cancel`); cleared name → `✓` disabled gray (`after-edit-gate.png`); retyped → `✓` saved + dismissed to History. AX-tree assertions recorded in PR body.
- [x] 4.3 Manual corner checklist: LOCKED verified on-screen via a seeded `garmin` entry (direct sqlite insert into the sim's account DB, removed afterwards): `Imported entry` shows Back only + provenance note (`after-locked.png`); edge-back swipe pops the pushed form (no #50 regression); VO labels read Close/Add entry/Save entry in the AX tree (EN on-device, RU pinned by `LocalizationTests`). NOT run: dark mode, large Dynamic Type on-device, RU locale on-device — listed as PR follow-ups (glyphs are single SF Symbols, no truncation mechanism).

## 5. Verification + docs (S5)

- [x] 5.1 `swiftlint lint --strict` clean (0 violations, 137 files); warning-as-error `xcodebuild test` green; full iOS suite green — 505 passed / 0 failed. Serialized per `docs/ios-test-loop.md` (booted-sim-by-ID, log-file polling). Backend untouched (no `go` run needed; shared local server on :8080 only used for OTP sign-in during repro).
- [x] 5.2 Re-checked `Requirements/FURPS/Timetracking.md` F13 (gate semantics unchanged — still "gated on trimmed non-empty name + end > start") + `Common.md` (no conflicts); no FURPS edit needed (no row pins button text).
- [x] 5.3 Docs: `docs/project-context.md` History paragraph describes push + "Save via LWW update" action semantics (unchanged — `✓` performs the same save), so no edit; `Design/SCREENS/History.md` has no toolbar-grammar pins; no architecture/contract/run-step change. `AGENTS.md` untouched (short by policy).
- [ ] 5.4 Push branch `fix/50-nav-buttons` + `gh pr create` targeting `main` (title mentions #50; body "Fixes #50" + repro + red-test evidence + verification + corners). DO NOT merge. Post no `/review` comment. Remove the worktree after pushing.
