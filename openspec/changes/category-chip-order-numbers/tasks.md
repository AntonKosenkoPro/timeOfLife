## 1. Foundation

- [x] 1.1 Confirm the cited SwiftUI API (`contentTransition(.opacity)`, iOS 16+, explicit animation overriding ancestor nil-transaction) against the pinned SDK (Xcode 16+, iOS 18+) — ctx7 library `/websites/developer_apple_swiftui`, query "opacity transition and contentTransition for animating text changes" (already fetched during design; re-verify if SDK differs)
- [x] 1.2 Spike: render a two-digit ordinal in the fixed `symbolSlotSize` at default and largest Dynamic Type sizes and confirm no clipping and no `FlowLayout` re-pack

## 2. TagSelector ordinal rendering

- [x] 2.1 Change `TagSelector` input from `selected: Set<String>` to the ordered selection array; derive membership and `firstIndex + 1` ordinals from it
- [x] 2.2 Render checkmark for exactly-one-selected, 1-based ordinal `Text` for two-or-more-selected, category icon otherwise — all inside the existing fixed symbol slot with Theme colors only
- [x] 2.3 Shrink two-digit ordinals to fit the slot; enforce the 99 cap
- [x] 2.4 Animate every ordinal transition (select, deselect, renumber, checkmark↔ordinal swap) with a fade scoped to the chip label so Track's ancestor nil-transaction does not suppress it

## 3. Call sites

- [x] 3.1 Pass the ordered arrays directly at both call sites (`TrackContent` running selector from draft `categoryIDs`, `LogTimeView` categories card from `vm.categoryIDs`); remove the `Set(...)` wrappers
- [x] 3.2 Verify the Track running selector fade works despite `bottomFlow`'s nil-transaction and the Start/Stop swap stays instant and stationary

## 4. Localization and accessibility

- [x] 4.1 Add ordinal-position announcement strings (EN + RU) via `L10n` and wire `accessibilityValue` to announce position when 2+ selected; keep existing selected/not-selected values for single selection

## 5. Tests

- [x] 5.1 Add/extend unit tests for ordinal derivation and renumbering (select second chip → 1,2; deselect middle → dense renumber; back to one → checkmark state; reselect appends at end)
- [x] 5.2 Update any snapshot/UI assertions that expect a checkmark on multi-selected chips to the ordinal contract
- [x] 5.3 Run `swiftlint lint --strict` and the warning-as-error `xcodebuild` build green

## 6. Verification and docs

- [x] 6.1 Re-check `Requirements/FURPS/*.md` rows covering category selection and timer capture for conflicts; fix or record any found
- [x] 6.2 Manual smoke on device/simulator: single chip shows ✓; two chips show 1,2 with fade; deselect middle renumbers with fade; layout above selector never shifts; VoiceOver announces positions; RU locale correct
- [x] 6.3 Sync `Design/COMPONENTS.md` TagSelector block (ordinal rendering, fixed slot, fade) and run full test suites (`go test ./...` unaffected-check plus `xcodebuild test`) green
