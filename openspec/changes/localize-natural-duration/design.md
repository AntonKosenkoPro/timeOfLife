## Context

`HistoryViewModel.naturalDuration(_:)` (`Features/AppShell/ViewModels/HistoryViewModel.swift:176`) is a pure `nonisolated static` helper with hardcoded Latin units (`33s`, `1m 20s`, `1h 12m`, `1d 12h`), minute-granularity above minutes (seconds dropped once hours appear). It is the single duration dialect for History rows, elevated day totals, Insights hero/rows/accessibility labels, and the Log Time subtitle (see proposal.md — Why). Tests (`NaturalDurationTests`, `HistoryViewModelTests`) pin the English strings exactly. No ctx7 fetch applies: the fix uses only Foundation (stdlib), which the repo's external-docs rule explicitly excludes.

## Goals / Non-Goals

**Goals:**
- Same grammar, locale-correct units: EN output byte-identical to today; RU output uses Russian abbreviations with correct plurals.
- Zero call-site changes: all consumers inherit the fix through the shared helper.
- Deterministic tests per locale (no dependence on the simulator's ambient locale).

**Non-Goals:**
- No grammar change (still two components, still minute-granularity above minutes — seconds-at-hour-granularity stays out).
- No new `Localizable.strings` keys, no `.stringsdict`, no backend/OpenAPI changes.

## Decisions

- **Per-unit `DateComponentsFormatter` (`unitsStyle: .abbreviated`) over whole-string formatting or hand-rolled plurals.** Spike result (task 1.1): a whole-string formatter cannot reproduce the grammar — `maximumUnitCount` + zero-dropping still emits `1h 0m 30s` / `1d 0h 0m 30s` where the grammar demands `1h` / `1d`. So the existing tier/selection logic stays exactly as-is and each selected component renders through a single-unit abbreviated formatter (`1h`→`1 ч`, `20s`→`20 с`, `1d`→`1 д.`), joined with a space. Foundation owns units and Russian plurals; our code owns the grammar. Alternative — custom RU unit tables + `.stringsdict` — was rejected: more code, more strings, same result. EN output is byte-identical to today by construction (same selection, EN units unchanged).
- **Keep the helper pure with an injected locale: `naturalDuration(_:locale:)` (`locale: Locale = .current`), threaded through `durationText(for:locale:)` and `makeDayGroups(..., locale:)` with the same default.** Defaults keep every production call site (`HistoryView`, `InsightsView`, `LogTimeView`, day totals) unchanged — they correctly follow the device locale; tests pass explicit `Locale(identifier: "en")` / `"ru"` so they never depend on ambient locale. Alternative — reading `Locale.current` inside with no parameter — was rejected as untestable per-locale.
- **Construct the formatter per call** (short-lived, configured from the passed locale). Rejected a shared cached instance: the helper is `nonisolated` and `DateComponentsFormatter` is not concurrency-safe to share without locking; per-call construction keeps the function pure and the cost is negligible at row counts.
- **Allowed units `.day, .hour, .minute, .second` with `maximumUnitCount = 2` and leading-zero dropping**, preserving today's shape (`12h` not `12h 0m`, `3d` not `3d 0h`). Exact flag combination is confirmed empirically in the implementation task.

## Risks / Trade-offs

- [Risk] `DateComponentsFormatter` RU abbreviations may include narrow no-break spaces or forms that look off in `.monospacedDigit()` rows → Mitigation: the implementation task prints actual RU outputs for the full test matrix and pins them in tests; visual check on History + Insights in RU simulator before merge.
- [Risk] Future third locale with surprising abbreviations → Mitigation: tests pin EN + RU only; any locale renders *something* sane via Foundation, which strictly dominates today's always-English.
- [Risk] VoiceOver reading of abbreviated units → Mitigation: no worse than today (abbreviations either way); RU VoiceOver reads native abbreviations better than Latin ones.
