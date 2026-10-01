## Context

See proposal.md Why. Current state: `ProfileView.syncStatusRow` formats `.idle(date)` once per `sync.status` publication via `RelativeDateTimeFormatter(unitsStyle: .short)` (`ProfileView.relativeTime`); `SyncController` publishes `.idle(Date())` once per cycle end and never again, so the label freezes until the next event. The system *relative-time* formatter also owns unit choice and tense: a future-stamped date (clock skew/NTP step) renders future tense ("через 0 сек."), weeks appear from 8 days up, and the fragment bypasses L10n entirely (U4 violation in effect). Constraints: Theme-only colors; U4 (en + ru + L10n + key-parity tests); Swift 6 isolation (`SWIFT_STRICT_CONCURRENCY: complete` + warnings-as-errors bit us on PR #89 — test types touching view statics need `@MainActor`).

## Goals / Non-Goals

**Goals:**
- Self-advancing minute-bucketed label, future-clamped, 100% from L10n keys with correct RU plurals.
- Pure, unit-tested bucket helper (no clock in logic); thin view tick.

**Non-Goals:**
- No `SyncController`/cycle/outbox changes; no exact-timestamp surface; weeks/months/years never.
- No snapshot/ViewInspector tests; no new reusable component.

## Decisions

- **Pure helper `syncRelativeLabel(elapsed:)`, quantity via `DateComponentsFormatter`, glue via L10n.** The helper maps elapsed seconds → bucket (<60s / <60min / <24h / days, negative→just-now) and picks `allowedUnits` ([.minute] / [.hour] / [.day]) with `maximumUnitCount = 1`; the formatter renders the quantity, an L10n order-wrapper appends the ago-word, and under-a-minute is a plain `justNow` key. Verified by script (not assumed): restricted units truncate (7140s→"1 hour", 2240s→"37 minutes"), never escalate (400d→"400 days"), RU plurals correct out of the box (1 минута/2 минуты/5 минут/11 минут/21 минута; час/часа/часов; день/дня/дней). This keeps `RelativeDateTimeFormatter` (auto unit choice + tense) out while keeping system pluralization for every future locale: a new language translates 2 plural-free keys. Alternatives rejected: full-custom buckets + `.stringsdict` (per-language plural work forever, first-stringsdict tooling); `RelativeDateTimeFormatter` with quantized dates (can't suppress weeks, sub-minute gives "now" not the specced bucket).
- **Tests: bucket boundaries through the real formatter in en + ru calendar locales (1/2/5/11/21/22/25 spot-checks), future clamp, glue-key parity (existing `LocalizationTests`).** Rationale: formatter truncation and locale wiring are the behaviors most likely to rot silently.
- **Minute tick lives in the view, not `SyncController`.** Rationale: `TimelineView`-periodic (or `Timer.publish` gated to the visible idle state) re-renders only the status row; pushing a presentation cadence into the sync engine would couple cycle logic to UI refresh. No tick for syncing/error/inactive states.

## Risks / Trade-offs

- [Risk] `ago`-wrapper word order in future locales (most suffix, some prefix) → Mitigation: order lives in the per-locale format key (`"%@ ago"` / `"%@ назад"`), not in code.
- [Risk] Formatter truncation semantics drift (e.g. future OS rounds instead of floors) → Mitigation: boundary tests pin 59s→minutes-invisibility, 3599s→"59 minutes", 7140s→"1 hour"; failure points at the OS, fix by quantizing input.
- [Risk] Minute tick re-renders whole Profile section → Mitigation: tick state scoped to the status row view; Erase/categories rows unaffected (verify in smoke).
- [Risk] Backgrounded app crosses buckets while Profile open → Mitigation: timeline/timer fires on foreground; label corrects on next tick — spec needs only minute precision.
- [Risk] Swift 6 isolation on test/view boundary (PR #89 lesson) → Mitigation: `@MainActor` on test suite from the start.
