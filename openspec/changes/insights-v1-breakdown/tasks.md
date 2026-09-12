## 1. Aggregation (pure, tested)

- [ ] 1.1 Add period enum (`today` / `week` / `all`) with `Calendar`-based interval resolution (`startOfDay`, `dateInterval(of: .weekOfYear)`), bucketing committed entries by `startedAt`.
- [ ] 1.2 Add pure `makeBreakdown(entries:activities:categories:period:lens:)` returning per-bucket `{ key, totalSeconds, entryIDs }` + display data: full-credit attribution to every current category (category lens), single-activity attribution (activity lens), "Without category" bucket, biggest-first ordering.
- [ ] 1.3 SwiftTesting coverage: period filtering (today/week/all boundaries), committed-only (in-progress excluded, NULL → 0), full-credit multi-category math, uncategorized bucket, ordering, empty input, entry-id sets usable for overlap.

## 2. View model

- [ ] 2.1 Add `InsightsViewModel` (`@MainActor`, `Features/Insights`): loads `entries()` / `activities()` / `categories()`, exposes hero total + rows per selected period/lens; `needsReload` / `invalidate()` / `loadIfNeeded()` lifecycle mirroring `HistoryViewModel`.
- [ ] 2.2 SwiftTesting coverage for the VM: hero equals committed sum per period, lens switch preserves period, reload/invalidate semantics, load failure keeps last good snapshot.

## 3. View

- [ ] 3.1 Build `InsightsView`: period segmented control (default `This week`), hero total (`naturalDuration` + tracked caption), lens toggle (default `By category`), proportional rows (icon + name + duration + max-scaled rounded-rect bar, `Theme` colors only, bars `accessibilityHidden`).
- [ ] 3.2 Add category-lens footnote (full-credit rule, localized) shown only on the category lens; rows non-tappable (no navigation, no selection state).
- [ ] 3.3 Add empty states: reuse true-zero placeholder copy for `All time` empty; period-specific one-line sentences for empty `Today` / `This week`.
- [ ] 3.4 Preserve shell contract: persistent nav bar title + Profile button scope untouched, `.safeAreaInset` compact timer slot kept on the Insights root.
- [ ] 3.5 VoiceOver + Dynamic Type pass: row labels announce name + duration; segmented controls are native `Picker`s; verify at accessibility sizes.

## 4. Shell wiring

- [ ] 4.1 Replace the Insights `DestinationPlaceholder` branch in `AppShellView` with `InsightsView` (same `refreshSignal` rewire as History so compact-timer stops refresh numbers); keep placeholder strings for the true-zero case.
- [ ] 4.2 Stable identifiers: Insights tab (`TabInsights` exists), breakdown list + controls get identifiers for future UI tests.

## 5. Localization

- [ ] 5.1 Add ~9 keys to `en.lproj` + `ru.lproj` + `L10n` cases: three periods, two lenses, "Without category", footnote, two per-period empty lines; extend `LocalizationTests` parity coverage.

## 6. Verification and docs

- [ ] 6.1 `swiftlint lint --strict` clean; `xcodebuild -scheme TimeOfLife -destination '<available simulator>' build` with zero app/test warnings; `xcodebuild test` green.
- [ ] 6.2 Re-check `Requirements/FURPS/Timetracking.md` + `Common.md` rows for conflicts; fix or reconcile.
- [ ] 6.3 Update `docs/project-context.md` (Insights scope line), `README.md` tab description if it names the placeholder, and `Design/SCREENS/AppShell.md` (Insights = breakdown); no OpenAPI/backend changes.
