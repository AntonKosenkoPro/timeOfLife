## 1. Chrome swap (`CategoryEditorView`)

- [x] 1.1 Replace the `EditorSheetScaffold` usage with a local `NavigationStack` + inline title + toolbar X (`xmark`, cancellationAction) / ✓ (`checkmark`, confirmationAction), mirroring `LogTimeView.chrome`; remove the text Cancel button and the pinned bottom Save bar.
- [x] 1.2 Gate ✓ on `vm.canSave` (valid name + `!isLoading`); keep X and swipe-down dismissal disabled while `isLoading` (`interactiveDismissDisabled` stays).
- [x] 1.3 Move `CategoryEditorCancelButton` / `CategoryEditorSaveButton` identifiers onto the toolbar items; add EN+RU VoiceOver labels (Log Time `entryDismissLabel`/`entryConfirmSaveLabel` analogues in `L10n` + `LocalizationTests` if enumerated).

## 2. Full-height presentation

- [x] 2.1 Present the editor as a plain full-height `.sheet` (no detents) from `ManageCategoriesView`; drop `usesMediumDetent: true` at the call site.
- [x] 2.2 Add `.scrollDismissesKeyboard(.interactively)` to the editor scroll content (Log Time parity); keep the settle-delayed autofocus task unchanged.

## 3. Verification

- [x] 3.1 `swiftlint lint --strict` clean; iOS build warning-free.
- [x] 3.2 Existing suites green (category editor, localization, ManageCategories view-model suites).
- [x] 3.3 Simulator E2E (signed-in, as in the prior change): open create + edit — sheet full-height, no resize/jump on keyboard appear/dismiss; X discards, ✓ disabled when empty/saving and saves when valid; content stays top-anchored with the field fully visible throughout.
- [x] 3.4 Re-check `Requirements/FURPS` rows and `Design/SCREENS/CategoryEditor.md` + `Design/INTERACTIONS.md` (D13/D21); update chrome/detent wording to the new contract.

## 4. Stage-1 review follow-up (PR #85)

- [ ] 4.1 Migrate `EmailEntryView` to field-level `focused:`; make the binding required (drop the fallback sink); update the DEBUG preview; re-verify email autofocus on simulator.
