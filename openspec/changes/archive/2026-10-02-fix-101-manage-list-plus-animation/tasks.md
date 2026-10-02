## 1. Repro spike (diagnosis, no ship)

- [x] 1.1 Reproduce on a populated catalog: open Manage Categories with 2+ categories, enable slow animations, screen-record sheet open via navbar `+` (`ManageCategoriesAddButton`, `ManageCategoriesView.swift:68-76`). (Done with 7 seeded categories on iPhone 17 sim; Simulator slow-animations unavailable headless and `withAnimation(3s)` probe does not stretch the system sheet transition — diagnosed instead via 10fps frame montages of 30fps captures: `+` fades on press and lingers faded ~0.5s across the sheet rise.)
- [x] 1.2 Record the control path on the same build: empty-state Add (`:44-51`) → same `vm.addCategory()` → sheet; note that the list page itself has no autofocus. (Done after deleting all 7 via UI: capsule Add shows a brief instant press, clean sheet open, same editor + 400ms autofocus.)
- [x] 1.3 File both captures + slow-animation observation in the change (or linked issue #101 comment draft): confirm the weird plus animation appears only on the toolbar-plus path. (Montages: toolbar-plus shows the lingering fade + sheet-`✓` sweep-through; empty-state Add shows none. Videos under `.argent/recordings/`.)

## 2. Isolate keyboard vs transition (throwaway probes, revert after)

- [x] 2.1 Probe A — vary `FocusDelay` settle (`PresentationMetrics.swift:8-19`, 400ms) to a clearly different value; re-record toolbar-plus open and note whether the plus animation changes. (2000ms: identical `+` fade/restore completing well before the keyboard arrives — keyboard timing irrelevant.)
- [x] 2.2 Probe B — temporarily disable editor autofocus entirely; re-record toolbar-plus open and note whether the plus animation persists without any keyboard. (Autofocus off, zero keyboard: identical `+` sequence — keyboard ruled out.)
- [x] 2.3 Revert both probes (working tree clean of any `CategoryEditorView` / `PresentationMetrics.swift` edits); record the verdict: keyboard implicated or presenter-side confirmed. (Reverted; verdict: presenter-side confirmed — the button's press-highlight restore inherits the sheet-presentation transaction and lingers ~0.5s, then the sheet's own `✓` sweeps through the same top-right spot.)

## 3. Minimal presenter-side fix (visual-only)

- [x] 3.1 Apply the smallest presenter-side calm scoped to the toolbar-plus path (e.g. explicit transaction / animation-nil on the presenting button); touch no sheet, editor, FocusDelay, or `vm.addCategory()` semantics. (`.transaction { $0.disablesAnimations = true }` on the toolbar button only — the `pill` highlight precedent from `LogTimeView`; sheet/editor/FocusDelay/`addCategory()` untouched.)
- [x] 3.2 Verify `git diff` shows only the presenter hunk (no probe leftovers, no behavior edits).

## 4. Acceptance + regression gates

- [x] 4.1 Acceptance at default animation speed (simulator + physical device where available): navbar `+` sheet open shows no weird plus animation; empty-state Add, row-tap edit open, save/dismiss transitions animate normally. (Simulator only — paired physical iPhone tunnel disconnected. Post-fix montage: `+` stays dark, no lingering fade. 7× edit-row opens + 4× X-dismiss observed normal; save transition shares the verified dismiss path and save logic is unit-tested — on-sim text entry into the name field did not deliver keystrokes, so a typed-name save was not exercised on device.)
- [x] 4.2 Behavior parity: same destination, same create-mode editor (empty name, default `tag`, no Delete), same autofocus/keyboard contract per `editor-sheet-ux`; no new strings (EN+RU untouched), no accessibility-identifier changes. (All observed on device + confirmed in diff.)
- [x] 4.3 Run `swiftlint lint --strict`, warning-as-error `xcodebuild` build, and relevant `xcodebuild test` slice; re-check `Requirements/FURPS/Activity_Catalog_and_Categories.md` rows — fix conflicts, claim no behavior change. (Lint clean, build green, full suite 556 tests/54 suites green — one run hit 2 flaky SyncController timing tests, green on re-run and on the final full pass. No behavior change.)
- [x] 4.4 Confirm docs untouched as expected (`docs/project-context.md`, `README.md`, `Design/*`, `backend/api/openapi.yaml` unchanged); this visual-only change adds no spec deltas (`skip_specs: true`).
