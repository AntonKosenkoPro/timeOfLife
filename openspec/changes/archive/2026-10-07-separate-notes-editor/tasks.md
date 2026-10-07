## 1. External docs + baseline

- [x] 1.1 Run ctx7 `library` → `docs` for SwiftUI presenter/editor (library `/websites/developer_apple_swiftui`, queries `Text lineLimit multiline truncation` + `TextEditor newline input`; pin iOS 18+) and confirm `lineLimit(1...5)` truncation + `TextEditor` binding behavior before coding — implementation tasks depend on this.
- [x] 1.2 Confirm tree is on `main` post `multiline-notes-field` archive (no parallel `notesCard` branch); resolve any `FormCard` resign-topology drift before editing.

## 2. Running-draft notes plumbing (store + services)

- [x] 2.1 Extend `timer_state` singleton + `RunningTimerDraft` with `notes` (edited in place, no migration branch); `saveTimerDraft` writes notes at Start, focused update rewrites notes only, all through `LocalStore` chokepoint.
- [x] 2.2 Carry notes through `TrackState.Draft` + `TrackViewModel` (load restores notes, Start seeds empty, mid-run save persists snapshot) and `TimerService.stopTimerDraft` (entry created with final notes + single outbox row instead of `""`).
- [x] 2.3 Verify widgets/Controls `timer_state` readers ignore the notes column (no display change).

## 3. Shared Notes editor page + form presenter

- [x] 3.1 Build the shared Notes editor page (beside `NamePicker`/`EditorChrome`): `initialText` + `onSave`, `EditorToolbar` X/✓ chrome with the system Back hidden, `TextEditor` with Return=newline and no Done key, placeholder overlay reuse, `Theme` colors only.
- [x] 3.2 Replace `LogTimeView.notesCard` inline editor with the read-only presenter (`Text`, `lineLimit(1...5)`, placeholder when empty, truncation past 5) pushing the shared page; X discards, ✓ writes `vm.notes` only with validity-gate re-evaluate; LOCKED renders presenter read-only with no navigation.
- [x] 3.3 Confirm all editor/presenter copy reuses existing `L10n` keys (title, placeholder, X/✓ labels) with both locales already present — no new strings; no raw `Color` literals.

## 4. Track running notes button

- [x] 4.1 Add the standalone trailing notes button OUTSIDE the `TrackContent` locked-name `FieldCard` at the screen's trailing padding (recording-only visibility, stable row height, full 44pt tap target, tint signals notes presence, accessibility id/label); tap pushes the shared page prefilled from the running draft.
- [x] 4.2 Wire running ✓ to draft-notes + persisted snapshot rewrite (history untouched) and X to discard; `Stop` saves the entry with the final notes.

## 5. Tests

- [x] 5.1 Extend store tests: draft round-trip carries notes, notes-only update leaves text/categories/`started_at` untouched, `Stop` entry carries final notes; widgets query unchanged.
- [x] 5.2 Extend view-model/form tests: presenter 1–5 lines + truncation + placeholder, X-discards vs ✓-commits-notes-only, LOCKED read-only, running button visibility + draft-only save + cancel-keeps-draft.
- [x] 5.3 Verify new/updated tests fail if the behavior breaks (e.g. revert ✓ to live-bind, drop the notes column, or show the button idle, and confirm red).

## 6. Verification + docs

- [x] 6.1 Run `swiftlint lint --strict` clean and the warning-as-error `xcodebuild` build + full test suite green (per `docs/ios-test-loop.md`: one `xcodebuild` at a time, booted-sim-by-ID).
- [x] 6.2 Record the sim battery (presenter 1/5/6-line + placeholder, editor newline + X-discards + ✓-commits, Track button recording-only + mid-run save + Stop-carries-notes, crash-resume keeps notes, tap-away/scroll behavior on the page) plus a physical-device pass and VoiceOver order (presenter → editor → X/✓); LOCKED read-only visual covered by human stage-2 if unseedable via UI.
- [x] 6.3 Re-check `Requirements/FURPS/Timetracking.md` F13 and `Activity_Catalog_and_Categories.md` U1 (280 unchanged); run `openspec validate --all` green.
- [x] 6.4 Update docs only if the run surfaces a contract/visual change (`docs/project-context.md`, relevant `Design/*.md`, baselines via archive flow); confirm no backend/OpenAPI change — `gofmt -l .` empty and `go test ./...` untouched scope explicitly.
