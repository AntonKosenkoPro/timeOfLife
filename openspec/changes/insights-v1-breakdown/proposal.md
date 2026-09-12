## Why

The Insights tab is the only primary destination that promises something ("Patterns emerge after you have tracked a little time") and shows nothing — an honest empty state with no path forward. History answers "what did I do and when?"; nothing answers "where does my time actually go?". The Design system already assigns that job to Insights (categories deliberately belong to Activity management and Insights, never to capture), and the `activity-detail-sheet` proposal explicitly deferred period-based statistics to "a future Insights capability". That future is now: users with days of tracked time have no mirror for their habits.

## What Changes

- The Insights destination presents a **period breakdown of committed tracked time**: a hero period total plus proportional rows, replacing the `DestinationPlaceholder` empty state when data exists (the true-zero empty state is kept).
- A **period switch** (`Today | This week | All time`, default `This week`) scopes all numbers; a **lens toggle** (`By category | By activity`, default `By category`) switches the breakdown key.
- **Attribution rule**: each committed entry contributes its full duration to its activity (activity lens, sums to hero) and to **every** currently-attached category of that activity (category lens, rows may sum above the hero — overlap is inherent, not an error). Entries resolve the activity's *current* categories at query time (existing reclassification precedent).
- **Mirror only**: totals, durations, relative bars. No percentages, no targets, streaks, goals, deltas, comparisons, or judgments. Rows are not tappable; no drill-in, filtering, or export in this change.
- Bars scale to the **max row** (relative presence), never to the hero total; durations reuse the History natural-language format. A one-line footnote on the category lens names the full-credit rule.
- Per-period empty sentences ("Nothing tracked today / this week yet") replace skeleton charts when a period has no committed entries.

Non-goals: week-over-week trends, averages, charts library adoption (iOS 15 target — custom rounded-rect bars only), tap-through to detail/History, per-entry category snapshots (reclassification applies, documented), untracked-time display, goals/coaching, backend or OpenAPI changes (read-only over existing `LocalStore` fetches).

## Capabilities

### New Capabilities
- `insights-breakdown`: period breakdown of committed time — periods, lenses, full-credit category attribution, hero total, proportional rows, footnote, empty states, mirror-only rule.

### Modified Capabilities
- `app-shell`: the Insights destination changes from a permanent empty-state placeholder to the breakdown surface (still reachable unsigned, still hosts the compact timer while running).

## Impact

- iOS only: new `Features/Insights` view + view model (pure aggregation over existing `LocalStore.entries()` / `activities()` / `categories()` reads — no schema, migration, or new store query required for v1); `AppShellView` swaps the Insights placeholder for the new view.
- Localization: ~9 new keys in EN + RU + `L10n` cases (periods, lenses, hero caption, "Without category", footnote, per-period empty lines).
- No backend, sync, outbox, undo, timer, or History behavior changes. No new dependencies (Swift Charts not usable on iOS 15).
