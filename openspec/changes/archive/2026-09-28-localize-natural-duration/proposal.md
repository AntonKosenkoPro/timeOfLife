## Why

The History natural-language duration (`HistoryViewModel.naturalDuration`) hardcodes Latin unit abbreviations (`33s`, `1m 20s`, `1h 12m`, `1d 12h`) regardless of device locale, so Russian-locale users see English units in History rows, day totals, Insights hero/rows, and the entry-form duration subtitle. The app otherwise ships full RU localization (EN+RU strings, `L10n` parity test), so the unlocalized durations are a visible gap in the RU experience.

## What Changes

- `HistoryViewModel.naturalDuration` becomes locale-aware: same two-component minute-granularity grammar, but unit abbreviations and pluralization follow the device locale (EN output unchanged: `33s`, `1m 20s`, `1h 12m`, `1d 12h`; RU output uses Russian abbreviations with correct plurals).
- All existing consumers inherit the fix with no call-site changes: History rows, elevated day-header totals (`"<duration> <tracked>"`), Insights hero/rows/accessibility labels, and the Log Time duration subtitle (`"Duration: <duration>"` — the `Duration` label itself is already localized).
- `NaturalDurationTests` + affected `HistoryViewModelTests` expectations become locale-pinned (EN assertions preserved; RU assertions added).
- Explicit non-goals: the live timer `HH:MM:SS` readout (`TimeFormatter.formattedDuration`) stays as-is — a universal stopwatch format, not language; timeframe captions (`14:00 – 15:20`), relative day labels, and `RelativeDateTimeFormatter` last-synced stay untouched (already localized); no new `Localizable.strings` keys (the formatter is locale-driven, not string-driven); no backend/OpenAPI changes.

## Capabilities

### New Capabilities
- None.

### Modified Capabilities
- `history-entry-list`: row durations and elevated day-header totals render in locale-aware natural language instead of fixed English abbreviations.
- `insights-breakdown`: hero total and breakdown rows reuse the same localized grammar.

The entry-form duration subtitle (specified in the still-active `feat-entry-duration-subtitle` change, not yet in the baseline) reuses the same shared helper and therefore inherits localization with no text change needed there; its English examples remain valid as the EN rendering.

## Impact

- Affected code: `HistoryViewModel.naturalDuration` (`Features/AppShell/ViewModels/HistoryViewModel.swift`); tests `NaturalDurationTests`, `HistoryViewModelTests` (and any snapshot of Insights/LogTime duration text — none assert formatted values today).
- No API, schema, store, or sync impact. No new dependencies (Foundation only).
- Spec examples quoting the English grammar (`2h 35m tracked`, `33s`/`1m 20s`/`1h 12m`/`1d 12h`) remain valid as the EN rendering; deltas clarify the units are locale-dependent.
