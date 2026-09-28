## 1. Formatter verification (spike)

- [x] 1.1 Print `DateComponentsFormatter` (`abbreviated`, max 2 units, drop leading zeros) output for the full `NaturalDurationTests` matrix (0, 33, 59, 60, 80, 3320, 3600, 4320, 43200, 86400, 129600, 259200, -5) under `en` and `ru` locales; confirm EN is byte-identical to today's strings and record the RU strings for tests.
- [x] 1.2 If any EN output differs, adjust the formatter flags (allowed units / zero behavior) until byte-identity holds; if byte-identity is unreachable, stop and re-propose (grammar change is out of scope).

## 2. Core implementation

- [x] 2.1 Rework `HistoryViewModel.naturalDuration` to `naturalDuration(_:locale:)` (`locale: Locale = .current`), per-call `DateComponentsFormatter` per design.md; no call-site changes.
- [x] 2.2 Update `NaturalDurationTests` to assert with explicit `en` locale (existing expectations unchanged) plus `ru` expectations from 1.1; update `HistoryViewModelTests` duration assertions to pass explicit `en` locale.
- [ ] 2.3 Run `swiftlint lint --strict`, the affected suites (`NaturalDurationTests`, `HistoryViewModelTests`, `LocalizationTests`, `InsightsViewModelTests`, `LogTimeViewModelTests`), then the full iOS suite green per `docs/ios-test-loop.md`.

## 3. Manual verification

- [ ] 3.1 Run the app in RU simulator: History rows, elevated day totals, Insights hero/rows, Log Time subtitle all show Russian units; EN simulator output unchanged (spot-check `1h 20m`, `2h 35m tracked`).
- [x] 3.2 Confirm no new `Localizable.strings` keys were needed and `LocalizationTests` parity still holds (228/228).

## 4. AI-review follow-ups (PR #62)

- [x] 4.1 Document the locale contract: in-progress indicator follows the app language (`durationText` Note); group headings follow the app language/calendar (`makeDayGroups` Note).
- [x] 4.2 Inline high-severity `.abbreviated`-vs-`short` claim verified as false positive (EN suite green locally and on CI) — no change.
- [x] 4.3 Per-call formatter construction kept over `NSCache` memoization (thread-safety in `nonisolated` context outweighs negligible per-row cost) — recorded in design.md.
