## 1. Predecessors

- [x] 1.1 Archive `separate-notes-editor` FIRST (its presenter baseline folds in; this change's entry-editor delta already carries the merged text, so archive order is the only constraint) — implementation tasks depend on this.
- [x] 1.2 Run ctx7 `library` → `docs` for the shake animation (library `/websites/developer_apple_swiftui`, query `keyframeAnimator shake animation validation`; pin iOS 18+) and confirm trigger-keyed `keyframeAnimator` + `KeyframeTrack` before coding — done during proposal, output recorded there.

## 2. Relay bound (Go)

- [x] 2.1 Bump `maxNotesLen` 280 → 2000 in `internal/handlers/catalog_validators.go` (counting rule untouched) and the 422 message number ("Notes must be 2000 characters or fewer", wording kept).
- [x] 2.2 Bump `notes.maxLength` 280 → 2000 in all three OpenAPI schemas (EntryCreate, EntryUpdate, Entry read); keep spec version 2.0.0 (widening only).
- [x] 2.3 Update `entries_test.go` gate tests to the new bound plus boundary cases (2000 trimmed runes pass, 2001 fail, surrounding-whitespace-free case passes); run `gofmt -l .` empty, `go vet ./...`, `golangci-lint run`, and `go test ./...` (includes the `internal/contract` gate).

## 3. Client counter + shake (iOS)

- [x] 3.1 Add `L10n` keys `notes.editorSubtitle` (`<name> • <n>/2000`) and `notes.editorCounter` (`<n>/2000`) in both locales plus `allCases` coverage (U4).
- [x] 3.2 Add the pure `NotesCounter` helper (trim + `unicodeScalars.count` + `isOverLimit`) with unit tests (ASCII, trimmed whitespace, multibyte runes, 2000/2001 boundary).
- [x] 3.3 Extend `NotesEditorPage` with `entryName`, the principal-toolbar subtitle (red past bound, single-line truncation), and the trigger-keyed `keyframeAnimator` shake on over-limit ✓ (✓ stays enabled; failed attempt saves nothing and never pops; shake suppressed under Reduce Motion). `Theme` colors only.
- [x] 3.4 Pass the entry name at both call sites (form draft name, Track locked text).

## 4. Verification + docs

- [x] 4.1 Run `swiftlint lint --strict` clean and the warning-as-error `xcodebuild` build + full test suite green (per `docs/ios-test-loop.md`: one `xcodebuild` at a time, booted-sim-by-ID).
- [x] 4.2 Record the sim battery (counter live count, red + shake on over-limit ✓ at default and large Dynamic Type, X-discards/✓-commits unchanged within bound, both call sites show the right name) plus VoiceOver order (editor → subtitle → X/✓); boundary backend tests are the red/green pair (2000 passes, 2001 422s).
- [x] 4.3 Re-check `Requirements/FURPS/Activity_Catalog_and_Categories.md` U1 + Limits row (2000) and `Design/BACKEND/Entry_Catalog_API.md` (×2); run `openspec validate --all` green.
- [x] 4.4 Ship order: backend deploy first (widens acceptance; stuck rows self-heal on next drain), app release after; mixed versions are safe. Confirm no migration either side.
