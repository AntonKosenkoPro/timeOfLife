## 1. External docs + baseline

- [x] 1.1 Run ctx7 `library` → `docs` for SwiftUI `TextEditor` (library `/websites/developer_apple_swiftui`, queries `TextEditor multiline placeholder focus dismissal` + `TextEditor`; pin iOS 18+) and confirm placeholder/focus/insets behavior before coding — implementation tasks depend on this.
- [x] 1.2 Rebase onto #118 (`fix/67-notes-clear-no-resign`) or `main` post-merge so `FormCard` is the plain tap-away baseline; resolve the resign-sentence overlap in the delta if #118 merged first.

## 2. Notes row implementation (iOS only)

- [x] 2.1 Replace the single-line `TextField` in `LogTimeView.notesCard` with a `TextEditor` bound to the existing `focusedField == .notes` focus state and `vm.notes` (Return inserts newline; no submit/dismiss action).
- [x] 2.2 Add the placeholder overlay reusing `L10n.entryNotesPlaceholder` (`Theme.textSecondary`, non-interactive, visible only when notes empty); transparent editor chrome (`scrollContentBackground(.hidden)`, `.font(.body)`, `Theme` colors only).
- [x] 2.3 Fix the 3-line visible reserve at the current Dynamic Type (stable height empty/short/×-mounted; inner scroll past 3 lines; card height never moves).
- [x] 2.4 Pin the clear button top-trailing (`HStack(alignment: .top)`), keeping `ClearButtonVisibility` rule, `EntryNotesClearButton` identifier, "Clear notes" label, and clear-only `vm.clearNotes()` with focus retained; LOCKED mode renders multiline read-only (disabled + dimmed, no ×).

## 3. Tests

- [x] 3.1 Keep `ClearButtonVisibilityTests` green (rule unchanged); extend form tests to cover newline insertion, 3-line reserve stability, placeholder visibility, and × clear-keeps-focus on the editor.
- [x] 3.2 Verify new/updated tests fail if the behavior breaks (e.g. revert × to resign, or editor to single-line, and confirm red).

## 4. Verification + docs

- [x] 4.1 Run `swiftlint lint --strict` clean and the warning-as-error `xcodebuild` build + full test suite green (per `docs/ios-test-loop.md`: one `xcodebuild` at a time, booted-sim-by-ID).
- [x] 4.2 Record the sim battery (newline, 3-line reserve at default + xSmall type, overflow scroll, × top-right keeps keyboard open, tap-away/scroll-away dismiss, LOCKED read-only) plus a physical-device pass for focus claim and nested-scroll feel; check VoiceOver order (editor → clear button).
<!-- DONE 2026-10-06 on iPhone 17e sim (video in .argent/recordings/): newline input, exact 78pt/3-line reserve at Large (pixel-measured), reserve scales at xSmall, inner scroll past 3 lines, placeholder, × top-right + clear-keeps-focus with zero flicker, tap-away dismiss, AX order editor→×. Left for human stage-2: physical-device feel + LOCKED read-only visual (imported entry not seedable via UI). -->
- [x] 4.3 Re-check `Requirements/FURPS/Timetracking.md` F13 and `Activity_Catalog_and_Categories.md` U1 (280 unchanged); run `openspec validate --all` (expect 22/22 or updated count).
- [x] 4.4 Update docs only if the run surfaces a contract/visual change (`docs/project-context.md`, `Design/*.md` Notes field if introduced); no OpenAPI/backend change — confirm `gofmt`/`go test` untouched scope explicitly.
