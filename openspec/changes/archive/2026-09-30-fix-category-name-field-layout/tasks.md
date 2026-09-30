## 1. Spikes (confirm before building)

- [x] 1.1 Confirm wrapper-`.focused` does not reach the inner field: preview/simulator check that `CategoryEditorView.onAppear` focus and `EmailEntryView` autofocus rely on the wrapper binding, and record which screens are affected.
- [x] 1.2 Confirm the height delta: measure `TextFieldWithError` with × hidden vs shown (empty vs prefilled focused field) and record the jump against the 54pt/76pt estimate.

## 2. Shared component (`TextFieldWithError`)

- [x] 2.1 Add a `FocusState<Bool>.Binding` parameter and apply `.focused` to the inner `TextField`; remove reliance on caller-side wrapper `.focused`.
- [x] 2.2 Pin the inner `TextField` to `.frame(minHeight: Theme.minTapArea)` so × visibility never changes row height; keep padding, background, error-collapse, and all accessibility identifiers unchanged.

## 3. Call sites

- [x] 3.1 `CategoryEditorView`: pass `$isNameFocused` into `TextFieldWithError`, drop the wrapper `.focused`, and replace instant `onAppear` focus with a cancellable settle-delayed autofocus task (NamePicker precedent).
- [x] 3.2 `EmailEntryView`: rewire to the new binding parameter only if spike 1.1 confirms its autofocus is broken; otherwise leave untouched.
- [x] 3.3 Re-check `ClearButtonVisibility` behavior end-to-end (focused+non-empty shows ×, Done/unfocus hides it) with no height or content shift in either mode.

## 4. Verification

- [x] 4.1 `swiftlint lint --strict` clean; iOS build warning-free (warnings are errors per `project.yml`).
- [x] 4.2 Existing suites green (`CategoryManagementViewModelTests`, `ClearButtonVisibilityTests`, `LocalizationTests` if touched).
- [x] 4.3 Manual simulator pass: Manage Categories add + edit, iPhone SE + standard, EN + RU, default + larger Dynamic Type — field compact and fully in viewport with keyboard open; × toggles with no layout jump.
- [x] 4.4 Re-check the touched `Requirements/FURPS` rows and `Design/SCREENS/CategoryEditor.md` + `Design/INTERACTIONS.md`; update only if behavior text conflicts.
