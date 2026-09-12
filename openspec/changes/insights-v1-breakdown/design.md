# Design: Insights v1 Breakdown

## Context

See `proposal.md` (Why) for motivation. Current state and constraints shaping the approach:

- Insights is a `DestinationPlaceholder` in `AppShellView` (`Features/AppShell/Views/AppShellView.swift:47-55`); the shell already pins the compact timer above it while running and keeps the persistent nav bar + Profile button. This change swaps the placeholder for a real view — shell chrome untouched.
- `LocalStore` (actor, GRDB) already exposes everything needed: `entries()` (all, newest-first with joined `activity_name`), `activities()` (with `categoryIDs`), `categories()`. No schema change, no migration, no outbox/sync involvement — a pure read surface.
- Precedents to reuse: `HistoryViewModel.makeDayGroups` (pure, unit-tested aggregation over in-memory rows) + `needsReload`/`invalidate()` lifecycle, `naturalDuration` formatting, first-category icon with `questionmark` fallback, device-calendar day bucketing by `startedAt`, committed-only totals (`endedAt != nil`, NULL → 0), `Theme` semantic colors only, `L10n` EN+RU strings, iOS 15 deployment target (no Swift Charts — iOS 16+; `Theme.color(_:alpha:)` helper instead of `Color.opacity`).

## Goals / Non-Goals

Goals: a shippable read-only breakdown honoring the four locked decisions (both lenses, full-credit categories, `This week` default, hero total) with an aggregation shape that v2 overlap work (shared-hours annotation, stacked bars, combination rows) can reuse without store changes.

Design-level non-goals: no new SQL aggregate queries (see D1), no navigation from rows (spec-mandated non-tappable), no charting dependency, no per-entry category snapshots.

## Decisions

### D1: In-memory pure aggregation, no new store queries
A `nonisolated static func makeBreakdown(entries:activities:categories:period:lens:)` (name TBD at implementation) filters committed entries by period, then buckets: by `activityID` (activity lens) or by each of the activity's current `categoryIDs` with full credit (category lens). Same three fetches History already does; personal datasets (hundreds/thousands of rows) make this trivially fast, and it keeps the change to zero migrations and zero `LocalStore` API surface.

*Alternative considered*: SQL `SUM … GROUP BY` with a date predicate — faster at scale we don't have, but splits the attribution logic across Swift/SQL, harder to unit-test, and the category join (many-to-many with full credit) is more awkward in SQL than in the join HistoryVM already does in memory. Optimize only if profiling ever justifies it.

### D2: Buckets carry entry-id sets, not just sums
Each bucket returns `{ key, totalSeconds, entryIDs }` (plus resolved display data: name, icon). Totals render from the sums; the id sets cost nothing now and are exactly what v2-a (shared-hours), v2-b (exclusive/shared stacked segments), and v2-c (combination rows) all need. Without them v2 would re-derive membership from scratch.

### D3: Full-credit honesty via omission + footnote (no percentages)
Category rows show duration only; bars render `row / maxRow` (guard: empty → hidden by the empty state, never divide by zero). The activity lens needs no caveat (sums to hero). Footnote under the category list only: *"An activity with several categories counts fully toward each."* (RU: *"Активность с несколькими категориями учитывается в каждой из них."*).

*Alternatives considered*: per-row "shared" badges (v2-a material — deferred to keep v1 to one new explanatory string); scaling bars to the hero (rejected — implies summation and makes the 9-vs-7 case look broken); showing percentages (rejected — same reason).

### D4: Custom rounded-rect bars, Theme-only
Rows: leading icon (category icon / first-category icon / `questionmark` fallback via existing `CatalogIcon` validation), name, natural-language duration, and a proportional track+fill bar built from `RoundedRectangle` in `Theme` colors (fill: `accentPrimary` at full or a secondary tone; track: `backgroundSecondary`/`hairline`). No Swift Charts (iOS 15 floor), no new color tokens. Honor Dynamic Type (bars are decorative: `accessibilityHidden`, values live in the row label).

### D5: Periods from `Calendar.current`
`Today`: `calendar.startOfDay(now)` → now. `This week`: `calendar.dateInterval(of: .weekOfYear, for: now)` (locale week start — Monday in RU, Sunday in US — matching the user's mental week and the hero label). `All time`: unfiltered. Bucketing key is `startedAt` (cross-midnight entries attribute to their start day, History precedent); future-dated manual entries count by `startedAt` with no special-casing.

### D6: Module shape mirrors History
New `Features/Insights/` (`InsightsView` + `InsightsViewModel`, `@MainActor`, `StateObject` owned by the view, `needsReload`/`invalidate()` guard, `loadIfNeeded` on appear, `invalidate` on disappear, same `refreshSignal` rewire so compact-timer stops refresh the numbers). `AppShellView` replaces the Insights `DestinationPlaceholder` branch; placeholder strings stay for the true-zero case (reused, not deleted). Period + lens held as `@State` in the view (view-local UI state, not VM-published — they need no persistence across tab switches beyond the view's lifetime; VM owns data only, same split as History).

### D7: Copy and formatting reuse
Durations via `HistoryViewModel.naturalDuration` (shared helper or a small shared formatter — implementation choice, but no second duration dialect on this screen; the detail sheet's three-component format stays sheet-local). Hero reuses the `history.tracked` caption pattern ("tracked this week"). New `L10n` keys (~9): three periods, two lenses, "Without category", footnote, two per-period empty lines.

## Risks / Trade-offs

- [Risk] Category rows summing above the hero confuses → Mitigation: D3 (no %, max-scaled bars, footnote); activity lens beside it demonstrates sane summation.
- [Risk] Week boundaries differ by locale (Sun vs Mon start) → Mitigation: `Calendar.current` does what the device's Calendar app does; documented in spec, no custom week logic.
- [Risk] Recategorization silently rewrites past breakdowns → Mitigation: spec-mandated documented behavior (existing `INTERACTIONS.md:249` precedent); no snapshot machinery in v1.
- [Risk] `This week` default shows an empty sentence on Monday morning → Mitigation: accepted trade-off from exploration (a week total is meaningful after day one; per-period empty copy keeps it from reading as failure). `Today` default would be empty every morning instead.
- [Risk] In-memory load grows with years of data → Mitigation: same profile as History (which already loads all entries); revisit with SQL aggregates if profiling justifies it.

## Migration Plan

None. Read-only change: no schema, no defaults migration, no user data touched. Rollback = restore the placeholder branch. The true-zero placeholder copy is retained, so a rollback leaves no dead strings (new keys simply go unused until the next archive cleans them, per repo string hygiene).

## Open Questions

None blocking. Footnote copy has a softer alternative ("Shared activities count toward every category") — the spec pins the normative meaning (full credit), so the final wording can be settled at implementation/review without changing behavior or tasks.
