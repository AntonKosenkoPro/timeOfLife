## 1. Design system: EntryRow component

- [x] 1.1 Add `EntryRow` to `Design/COMPONENTS.md` — signature, visual (Variant H layout: icon leading, spanning both lines, top-aligned with name; name + timespan line 1; categories + timeframe line 2; `questionmark` fallback), states (with/without categories, in-progress), requirements, accessibility, usage example
- [x] 1.2 Add `EntryRow` SwiftUI view to `Core/Components/` — uses `Theme` semantic colors only, `.title3` icon, `.headline` name + timespan, `.caption` categories + timeframe, `monospacedDigit()` on timing, `questionmark` fallback, `minTapArea` height, icon top-alignment constant
- [x] 1.3 Add `SectionHeader` day-group usage pattern to `Design/COMPONENTS.md` (existing component, new usage context)

## 2. Screen spec: History

- [x] 2.1 Create `Design/SCREENS/History.md` — screen description, layout (List with day-group sections, EntryRow per entry, EmptyState fallback, compact timer safeAreaInset), behaviors (load on appear, read-only), states (loading, empty, loaded), data model, implementation checklist, new localization keys (EN + RU)

## 3. Localization

- [x] 3.1 Add day-group keys to `en.lproj/Localizable.strings`: `history.day.today`, `history.day.yesterday`
- [x] 3.2 Add day-group keys to `ru.lproj/Localizable.strings`: `history.day.today` = "Сегодня", `history.day.yesterday` = "Вчера"
- [x] 3.3 Add keys to `L10n` enum: `historyDayToday`, `historyDayYesterday`
- [x] 3.4 Add in-progress indicator key (EN + RU): `history.inProgress` = "In progress" / "В процессе"

## 4. HistoryViewModel

- [x] 4.1 Create `HistoryViewModel` (`@MainActor`) in `Features/AppShell/ViewModels/` — loads entries via `LocalStore.entries()`, activities via `LocalStore.activities()`, categories via `LocalStore.categories()`; builds `activityID → [Category]` map; groups entries by calendar day of `startedAt` (newest day first, entries within day newest first); exposes `@Published var dayGroups: [DayGroup]` where `DayGroup` has a label (relative or absolute date) and `[TimeEntry]`
- [x] 4.2 Add day-label formatting: "Today" / "Yesterday" (localized via `L10n`) for the two most recent calendar days; `DateFormatter` with device locale for older days
- [x] 4.3 Add natural-language duration formatter: `33s`, `1m 20s`, `1h 12m`, `1d 12h` — pure function, unit-tested
- [x] 4.4 Add category-resolution helper: given an `activityID` and the activity→categories map, return `(icon: String, categoryNames: String)` — first category's `CatalogIcon.displaySymbol` for icon, comma-separated names; `questionmark` + empty string when no categories

## 5. HistoryView

- [x] 5.1 Create `HistoryView` in `Features/AppShell/Views/` — `ScrollView` or `List` with day-group sections (day header + `EntryRow` per entry), `EmptyState` when no entries, `accessibilityIdentifier("HistoryList")`
- [x] 5.2 Wire `HistoryView` into `AppShellView` History tab, replacing `DestinationPlaceholder`; preserve `compactTimerIfNeeded` safeAreaInset
- [x] 5.3 Ensure `HistoryView` is created with `LocalStore` from `AppContainer` (inject via init or `EnvironmentObject`)

## 6. Tests

- [x] 6.1 `HistoryViewModelTests` — day grouping (today, yesterday, older), ordering within day, empty state, category resolution (with/without categories, fallback icon), in-progress entry display
- [x] 6.2 Duration formatter tests — all natural-language cases: seconds, minutes, hours, days, mixed
- [x] 6.3 Day-label tests — relative for today/yesterday, absolute for older, locale-independent logic
- [x] 6.4 `EntryRow` accessibility — `accessibilityIdentifier("EntryRow(\(id))")`, row is a single button element, category names and timing folded into label

## 7. Build, lint, docs

- [x] 7.1 `xcodegen generate` + `swiftlint lint --strict` — zero findings
- [x] 7.2 `xcodebuild build` + `xcodebuild test` — green, no warnings (warnings are errors via `project.yml`)
- [x] 7.3 Re-read `Requirements/FURPS/Timetracking.md` rows — confirm alignment with U1 (source labels deferred), no conflicts
- [x] 7.4 Update `docs/project-context.md` — move "History/list UI for time entries" from "Incomplete / deferred" to implemented; note remaining deferred items from `docs/history-roadmap.md`
- [x] 7.5 Update `Design/README.md` screen index to include `SCREENS/History.md`
- [x] 7.6 `openspec validate --change history-entry-list` — passes

## 8. Post-implementation revisions (user testing feedback)

- [x] 8.1 Collapsing nav bar on History (D9): nav bar (inline "History" title + Profile button) visible at rest, collapses on scroll-down, restores at scroll-to-top. **Replaces** the prior permanent-hide approach; the app-shell baseline deviation no longer applies.
- [x] 8.2 Re-tune `EntryRow.iconTopAdjustment` so the icon's optical top aligns with the activity name's cap-height top (not the text frame top); verify on simulator against the spike variants.
- [x] 8.3 Add per-day total to `DayGroup` (D8): `HistoryViewModel` computes `total: String` as the natural-language sum of `durationSeconds` across the day's entries (in-progress entries contribute zero); expose on `@Published var dayGroups`.
- [x] 8.4 Update `SectionHeader` to support an optional trailing view **and column alignment** with `EntryRow` (day label flush to the icon column's leading edge; total flush to the duration/timeframe trailing edge); History shows the total only when the header is elevated (pinned at top).
- [x] 8.5 Add `history.tracked` localization key (EN "tracked" / RU "отслеживано") to `en.lproj`, `ru.lproj`, and `L10n`; update `LocalizationTests` count.
- [x] 8.6 Add day-total tests to `HistoryViewModelTests`: total sums known durations, in-progress entries contribute zero, empty day total is "0s".
- [x] 8.7 `xcodegen generate` + `swiftlint lint --strict` + `xcodebuild test` — green, zero findings.
- [x] 8.8 `openspec validate --changes history-entry-list` — passes.
- [x] 8.9 Gate the day-total display on the header's elevation state (pinned at top); in-list headers show only the day label.
- [x] 8.10 Implement the collapsing nav bar scroll-tracking in `HistoryView` (iOS 15+ compatible); verify Profile is reachable at rest and the bar collapses/restores correctly on scroll.
