## Context

See `proposal.md` (Why) for motivation. Current state shaping this design:

- `LocalStore.createEntry(_:)` already persists an entry + outbox row in one transaction, is idempotent on `id`, and bumps `last_used_at`. Manual entries need no store, migration, backend, or OpenAPI work — this change is SwiftUI + view-model + L10n.
- Track owns the activity search + quick-create UX (`ActivitySearchSheet`, `ActivitySearchContentView`, `TrackViewModel.quickCreateFromSearch`, normalized-name collision rule). The Log Time sheet reuses that presentation rather than inventing a picker.
- `HistoryView` is a `ScrollView` + `LazyVStack` with a persistent nav bar (title + Profile from `AppShellView`'s toolbar); it reloads via `vm.invalidate()` + `loadIfNeeded()` and refreshes on Track saves through the same path the new sheet will use.
- `ActivityDetailView` already stacks the activity editor over itself; the Log Time sheet follows the same stacking pattern. Calendar add-event UX was verified live on-simulator (see proposal decisions): nav-bar Cancel/Add gate, title-over-value rows, inline single-open pickers, Calendar-row menu.
- Constraints: iOS 15+ (no `NavigationStack`, no iOS 16+-only pickers), `Theme` colors only, EN + RU strings via `L10n`, `@MainActor` view models, DI via `AppContainer`.

## Goals / Non-Goals

**Goals:**

- One shared Log Time sheet used from both entry points, with Calendar-grade date/time picking and Track-grade activity picking.
- Zero new persistence/sync machinery; the sheet is a thin validated front-end over `createEntry`.

**Non-Goals:**

- No refactor of Track's search internals beyond the minimum extraction needed for reuse.
- No entry editing/deletion surfaces; no conflict/overlap policy.

## Decisions

### D1: New `Features/ManualEntry` group — `LogTimeView` + `LogTimeViewModel`

A dedicated feature group (not code inside History/ActivityDetail) so both entry points share one sheet and one validation core. `LogTimeViewModel` is `@MainActor`, injected with `LocalStore` (and the activity catalog source Track uses), exposes `selectedActivityID`, `startsAt`, `endsAt`, `isAddEnabled`, and `save()`. Alternatives considered: duplicating a small form per entry point (rejected — two validation cores to drift), or putting the form in `Catalog` (rejected — it's a capture flow, not catalog management).

### D2: Native pickers — `.graphical` date + `.wheel` time, inline single-open

Starts/Ends rows keep Calendar's date-pill + time-pill grammar. The expanded picker is a SwiftUI `DatePicker` with `.datePickerStyle(.graphical)` (dates) / `.wheel` (times), shown inline below the pills; opening one collapses the other (single `expandedPicker` enum in the VM). Alternatives considered: one compact `.compact` DatePicker per row (rejected — its popover calendar doesn't match the observed inline Calendar UX and behaves inconsistently on iOS 15), custom month grid (rejected — new code for what the system provides).

### D3: Reuse `ActivitySearchSheet` for the Activity row

The Activity row opens the existing Track searchable sheet. Requires extracting the search + quick-create logic out of `TrackViewModel` into a reusable unit (e.g. an `ActivityPicking` view-model used by both Track and the Log Time sheet) — the minimal extraction that keeps Track behavior identical. Alternatives considered: a simple `Menu`/list of activities (rejected — breaks down with many activities and loses quick-create, which the specs require), duplicating search logic (rejected — collision-rule drift risk).

### D4: Duration preservation lives in the VM, not the view

`startsAt`/`endsAt` setters enforce: moving Start at/past End auto-advances End by the preserved duration; End never moves Start. `isAddEnabled = activity != nil && end > start`. Alternatives considered: clamping in the view layer (rejected — untestable), disabling Start past End (rejected — dead-end state Calendar avoids via auto-push).

### D5: Entry points are thin presentation + refresh hooks

- History `[+]` toolbar button presents the sheet; on save, `HistoryViewModel.invalidate()` + reload (same path as Track-save refresh).
- ActivityDetail `Log time` presents the sheet pre-filled (`initialActivityID`); on save, the detail VM reloads its entry list and total.
- Save failures surface as a non-field error in the sheet (draft preserved, sheet stays open), mirroring Track's preparation-failure recovery.

### D6: Sheet stacking follows the editor precedent

The Log Time sheet stacks over History / the detail sheet exactly like the activity editor stacks over the detail sheet today; the activity picker stacks over the Log Time sheet. Dismissal unwinds in reverse. No new navigation routes.

## Risks / Trade-offs

- [Risk] `DatePicker.graphical` on iOS 15 renders larger than on iOS 16+ and may crowd the sheet → Mitigation: sheet scrolls; verify on the iOS 15 simulator in tasks.
- [Risk] Extracting search logic from `TrackViewModel` regresses Track → Mitigation: extraction is move-only with Track's existing tests pinning behavior; manual Track smoke in tasks.
- [Risk] Wheel pickers + graphical calendar in one scrolling sheet cause layout jumps → Mitigation: single-open picker invariant bounds the height change; one expanded picker at a time is spec'd.
- [Risk] Floored-to-5-min default vs. device 12/24h locale → Mitigation: no custom formatting; system pickers and `HistoryViewModel`-style formatters only.

## Migration Plan

None — additive UI, no schema, no API, no migration. Rollback is reverting the change.

## Open Questions

None — all shaping decisions (defaults, duration preservation, overlap policy, empty catalog, create-only boundary) were resolved in explore and are spec'd.
