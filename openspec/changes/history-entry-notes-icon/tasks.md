## 1. Row indicator + view model

- [x] 1.1 Add `hasNotes: Bool = false` to `EntryRow` and render the `note.text` icon in `Theme.accentPrimary` on line 2 (left of the timeframe) when true; exclude the glyph from the accessibility tree
- [x] 1.2 Add pure `HistoryViewModel.hasNotes(for:)` (trimmed non-empty check) and pass it through in `HistoryView`
- [x] 1.3 Fold the localized "has notes" segment into `EntryRow.accessibilityLabel` when `hasNotes` is true

## 2. Localization + tests

- [x] 2.1 Add the `historyHasNotes` string to both `en.lproj` and `ru.lproj` + the `L10n` enum and `LocalizationTests.allCases`
- [x] 2.2 Add unit tests: `hasNotes` empty / whitespace-only / newline-only / non-empty, and row label with/without the affordance
- [x] 2.3 Extend row previews with a notes-bearing entry and smoke-check narrow-width rendering on the smallest simulator

## 3. Design docs

- [x] 3.1 Document the notes icon (placement, symbol, color, `hasNotes` signature) in `Design/COMPONENTS.md` `EntryRow`
- [x] 3.2 Document the indicator rule in `Design/SCREENS/History.md`

## 4. Verification

- [x] 4.1 Run `swiftlint lint --strict`, warning-clean `xcodebuild` build, and the iOS test suite green
- [x] 4.2 Re-check the relevant `Requirements/FURPS` rows and confirm alignment

## 5. Placement follow-up (icon on line 2, left of timeframe, caption size)

- [x] 5.1 Move the notes glyph to line 2 before the timeframe in `EntryRow` and update design.md + `Design/COMPONENTS.md` + `Design/SCREENS/History.md`
- [x] 5.2 Re-verify (lint + build + tests) and redeploy the Release build to the iPhone
