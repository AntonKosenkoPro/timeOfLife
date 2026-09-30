## 1. Shared picker component

- [x] 1.1 Add shared `Suggestion` value + generic `NamePicker` view (pinned autofocused field, scrollable rows with text + first-category icon, empty/zero-match states, `onComplete`/`onCancel` outputs, Theme colors only)
- [x] 1.2 Add EN + RU strings (`L10n`) for picker title, empty hint, zero-match hint; register identifiers for field and rows
- [x] 1.3 Add picker previews (matches, empty store, zero matches, large Dynamic Type) + unit tests for the suggestion mapping/filter purity

## 2. Track integration

- [x] 2.1 Convert Track idle/ready/saved name control into a push row opening the picker prefilled with the draft; wire completion through `select(_)` + ready sync and cancel through draft restore
- [x] 2.2 Delete `nameSuggestionsCard` overlay + `zIndex` plumbing; verify Start is never covered and the main-action frame is unchanged
- [x] 2.3 Update Track previews + UI tests (push/pop steps, row-tap and Done completion, Back-cancel restores draft)

## 3. Entry-form integration

- [x] 3.1 Convert LogTime Name row (CREATE + EDIT) into a push affordance opening the same picker; wire completion through `applySuggestion` and cancel through draft restore (LOCKED stays read-only)
- [x] 3.2 Delete `LogTimeView.nameSuggestions` inline list; verify pushed picker nests in the sheet stack (CREATE) and History stack (EDIT) with standard back titles
- [x] 3.3 Update entry-form previews + UI tests (push/pop steps, completion fills text + ordered categories, Back-cancel preserves draft)

## 4. Verification

- [x] 4.1 Run `swiftlint lint --strict`, `xcodebuild` build + test suite green (one `xcodebuild` at a time per `docs/ios-test-loop.md`)
- [x] 4.2 Manual smoke: SE + large text + dark mode across Track/CREATE/EDIT (autofocus, scroll under pinned field, row-tap/Done/Back paths, VoiceOver order)
- [x] 4.3 Run `openspec validate --all --strict` and re-check `Requirements/FURPS` rows for the touched flows

## 5. Test-findings follow-up (smoke round 1)

- [x] 5.1 Uncapped source: `LocalStore.allActivityNames()` + Track `allNames` + LogTime loads all; picker rows render lazily (`LazyVStack`)
- [x] 5.2 Exact match included in filter (misleading new-name hint gone); deleted superseded VM `nameSuggestions()` filters + their tests (behavior lives in `NamePickerFilter`)
- [x] 5.3 Pinned field: root `maxHeight: .infinity, alignment: .top`, one persistent `ScrollView`, uniform top spacing; spec + design + FURPS updated
## 6. Test-findings follow-up (smoke round 2)

- [x] 6.1 Fallback icon: rows always render the icon slot (`questionmark` when uncategorized, History/Insights convention; Dynamic-Type-scaled like chips)
- [x] 6.2 Push jump: autofocus waits out the push transition (~0.4s, task-cancelled on pop) so the keyboard no longer relayouts Track mid-push
## 7. Test-findings follow-up (smoke round 3)

- [x] 7.1 Pop jump: resign focus before applying + popping so keyboard dismissal runs concurrently with the pop transition
- [x] 7.2 Empty-Done applies (clears draft; Track→idle, form gate disables) instead of no-op — Done always applies, Back always discards; spec + design + proposal + FURPS updated, `completeTypedName` test updated
## 8. Revert: empty-Done applies (kept: resign-before-pop jump fix)

- [x] 8.1 Empty Done is a no-op again (code + `completeTypedName` test); spec + design + proposal + FURPS reverted with the rationale recorded
- [x] 8.2 Re-verify: lint clean, full suite green (525 tests / 51 suites), `openspec validate --all --strict` 19/19
