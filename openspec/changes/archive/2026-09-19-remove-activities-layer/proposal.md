## Why

The activities entity layer forces retroactive inheritance: renaming an activity renames all history, retagging retags all history, and deleting an activity destroys its entries. Entries should own their label, categories, and notes outright so history never mutates retroactively.

## What Changes

- **BREAKING**: Remove the `activities` entity (table, `/activities*` API, catalog UI, search/resolve/quick-create machinery). Entries carry `activity_text` (trimmed, byte-exact, case-sensitive identity; `Gym` ≠ `GYM`), ordered `category_ids`, and `notes`.
- **BREAKING**: Re-anchor categories from activities to entries via `entry_categories(position)`; category CRUD stays, `ActivityEditor` and `activity_categories` go away.
- Track timer becomes plain-text capture: 6 exact-match recents chips (newest-first by that text's newest `started_at`, first-category icon), plain-text name field, Start gated on trimmed non-empty text. Start with an exact-recent match implicitly inherits its full ordered categories; otherwise categories start empty; notes start empty.
- Running timer hosts the shared ordered `TagSelector` (select-only, zero allowed): name locked after Start, tags live until Stop, draft persisted in transposed `timer_state`.
- Entry created once at Stop with final values + single outbox row; in-progress never syncs and never appears in History/Insights/Recents/totals.
- History row tap opens the unified entry form directly (EDIT/LOCKED); the Activity detail sheet is removed.
- Relay drops activity resources, collision remap, and parent-heal; entries sync with `activity_text + category_ids`.
- One-shot migration bakes each entry's current activity name, ordered categories, and activity notes; orphan activities vanish.

Non-goals: search-as-you-type filtering (plain text + chips only), bulk rename-all-text, Discard-running action (Stop-only; pocket entries deleted post-hoc), new entry-detail surface, lock-screen ControlWidget target.

## Capabilities

### New Capabilities

- None — this change removes and re-anchors; no new capability is introduced.

### Modified Capabilities

- `timer-capture-experience`: plain-text capture, exact recents, live TagSelector while running, draft-until-Stop.
- `manual-entry`: plain-text name field, no activity resolve.
- `entry-editor`: Name + ordered Tags + Notes rows, new validity gate, reassignment becomes retext/retag.
- `history-entry-list`: rows resolve categories from the entry itself; tap opens entry form directly.
- `local-first-store`: schema transposition (entries own text/cats/notes, `entry_categories`, transposed `timer_state`; drop `activities`/`activity_categories`).
- `sync-client`: entries-only sync payload, removal of activity collision/remap/heal/tombstone rules.
- `category-management`: categories attach to entries; editor/deletion semantics re-anchored.
- `insights-breakdown`: lenses group/attribute directly from entries.
- `app-shell`: compact timer + Profile management copy follow the entry-owned model.
- `lock-screen-controls`: most-recent subject becomes a string + category snapshot.
- `activity-detail-sheet`: REMOVED — capability retired with the detail sheet.
- `activity-deletion`: REMOVED — cascade activity deletion no longer exists (per-entry delete remains under `entry-editor`).

## Impact

- iOS: `TimeTracking` (TrackState, search, recents chips, TimerService, timer_state), `ManualEntry`/`entry-editor` form, `HistoryView`, `ActivityDetail` (deleted), `Catalog` (ActivityEditor deleted, models rewritten), `Insights`, `SyncController`/`RemoteCatalogRepository`, `LocalStore` migrations + queries, `TagSelector` re-parenting, EN+RU strings + `L10n`.
- Backend: migrations (drop activities/join, add entry text/notes/`entry_categories`), `Store` interface + sqlite/postgres impls, handlers/validators, routes, `openapi.yaml` (authoritative contract) + contract tests.
- Docs/specs: baselines above via deltas; `docs/project-context.md`, FURPS Activity_Catalog/Timetracking rows, `Design/DECISIONS.md` D20/D24 reversal.
