# Tasks: fix-67-notes-clear-no-resign

## 1. Reproduce (recorded, on current tree) — DONE

- [x] 1.1 Record Notes × on `main` (B1 merged): field clears, keyboard drops — B1 suppress never engages on real taps (video + screenshots).
- [x] 1.2 Confirm the async-refocus replacement flickers (keyboard dismisses then swiftly reappears) — compromise rejected.

## 2. Implement

- [x] 2.1 `FormCard`: `.simultaneousGesture` → plain `.onTapGesture { resignFocus() }`; rewrite the contract comment (explicit-resign rule).
- [x] 2.2 Name row: NO resign — pushed `NamePicker` autofocuses its own field, so focus transfers directly (resigning first would replay the flicker).
- [x] 2.3 Categories `onToggle` + shared `toggle(_:)`: set `focusedField = nil` alongside the state change.
- [x] 2.4 Notes ×: plain `vm.clearNotes()` action; delete B1 binding/`@State`/drag and any refocus.
- [x] 2.5 Audit all five `FormCard` sites for interactive children; FURPS Timetracking F13 re-check.

## 3. Verify

- [x] 3.1 `swiftlint lint --strict`, build, full `xcodebuild test` green (docs/ios-test-loop.md).
- [x] 3.2 Record the identical repro + regression battery (× stays with no flicker; chip/label resign; pill expands; name pushes with focus transfer).
- [x] 3.3 Device verify on the physical iPhone (Release build + reinstall) with the identical repro.
- [x] 3.4 `openspec validate --all`.
