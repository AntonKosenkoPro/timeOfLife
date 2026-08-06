## Why

The current iOS client treats the backend as the source of truth and the app as a cache that syncs to it. That model blocks three near-term goals: (1) macOS support with Screen Time integration, (2) lock-screen Controls that start a timer without Face ID, and (3) a free/paid split where the app works fully offline and sync is an optional paid feature. It also forces per-platform sync logic if Android/Web ever materialize (solo dev, can't maintain three sync codebases). We need to reframe the app as **local-first**: the device is the source of truth, the backend is an optional relay, and sync is a transport feature that activates on sign-in — not a prerequisite for using the app.

## What Changes

- **BREAKING**: The app launches into the timer without requiring sign-in. Auth becomes an optional action in Settings ("Enable Sync"), not a launch gate. `RootView` no longer routes to `AuthFlowView` on first launch.
- **BREAKING**: `LocalTimerStore` (flat `timerQueue.json`) is replaced by a real SQLite local database (GRDB) in an App Group shared container. This database is the source of truth.
- **BREAKING**: The `TimerRepository` / `StubTimerRepository` remote-push layer is removed. `TimerService` writes only to the local database. Remote propagation becomes the responsibility of a new background `SyncController`.
- New `SyncController` (optional, activates on sign-in): drains a transactional outbox to the backend relay and pulls deltas via `?modified_since=`. Conflicts resolve by last-write-wins on `updated_at` (existing design). Manual "Sync now" action and "Last synced" status in Settings.
- New **transactional outbox** table in the local database: every mutation (create/update/delete) writes the state change and an outbox row in one transaction. Deletes are first-class (the outbox holds the op even after the row is gone). Survives relaunch.
- New **durable undo buffer** table: deletions enter the buffer + remove the records in one transaction; the 30s window is wall-clock (`deleted_at + 30s`), not a `Timer`. Expired buffers commit to the outbox on the next foreground (not in the background). Robust to suspension, kill, and cold launch — fixes a real bug in the in-memory buffer design under iOS lifecycle.
- New **running-timer-state** persisted in the local database (not just in-memory): survives app crash; readable by lock-screen Controls and widgets to render "Stop (23 min)".
- New entry provenance: `source` + `source_ref` columns on entries (`manual`, `widget`, `siri`, `control`, `screentime`, `garmin`, ...). Provenance is visible to the user. `UNIQUE(user_id, source, source_ref)` prevents duplicate imports (e.g., Screen Time callback firing twice).
- Backend additions (already-built CRUD + LWW stays; only additive filters): `?modified_since=` on `GET /activities` and `GET /entries` for delta pull-sync.
- App Group shared container (`group.com.antonkosenko.timeoflife`): the local database, outbox, and undo buffer live here so widgets, Screen Time extension, and lock-screen Controls (app process, `alwaysAllowed` auth policy) can read/write cross-process.
- Entry-creation surfaces all funnel through the outbox: manual, widget tap (deep-link), Siri shortcut (in-app intent), lock-screen Control (background intent, iOS 18+), Screen Time extension. Sync drains them uniformly on foreground/connectivity.

## Capabilities

### New Capabilities
- `local-first-store`: The on-device SQLite (GRDB) store that is the source of truth — state tables (activities, categories, entries, activity_categories, timer_state), the transactional outbox, the durable undo buffer, and per-resource sync cursors. Lives in the App Group shared container. Accessible cross-process (widgets, extensions) and after first-unlock-since-boot (lock-screen Controls).
- `sync-client`: The optional background `SyncController` that activates on sign-in: drains the outbox to the backend relay, pulls deltas via `?modified_since=`, applies LWW merge locally, and exposes status + manual "Sync now". Pull-first on cold start; outbox survives sign-out.
- `entry-provenance`: The `source` / `source_ref` fields on entries and the uniqueness constraint that prevents duplicate imports. User-visible source labels.
- `lock-screen-controls`: iOS 18+ Controls (WidgetKit `ControlWidget`) that start/stop the timer from the lock screen without opening the app or requiring Face ID, via an `alwaysAllowed` App Intent that writes to the App Group database. Available on iOS 18+ with availability guards; absent on older OSes.

### Modified Capabilities
<!-- None — openspec/specs/ is empty (this is the first change). -->

## Impact

- **iOS app**: `RootView`, `AppContainer`, `TimerService`, `TimeEntry`, `SessionStore` change; `TimerRepository`/`StubTimerRepository` deleted; new `SyncController`, `LocalStore` (GRDB), `Outbox`, `UndoBuffer`, `TimerStateStore`. App Group capability + entitlement added to `project.yml`.
- **Backend**: additive `?modified_since=` query param on `GET /activities` and `GET /entries` (filter on `updated_at`); entries table gains `source` + `source_ref` + unique constraint (migration). Auth, CRUD, LWW, OpenAPI shape unchanged — the backend's role shifts from authority to relay, but the API contract is stable.
- **Dependencies**: GRDB.swift added (iOS/macOS). App Group entitlement. iOS 18+ `ControlWidget` API (availability-guarded).
- **Docs**: `AGENTS.md`, `Design/INTERACTIONS.md` (undo buffer durability, sync client), `Design/BACKEND/Activity_Catalog_API.md` (modified_since, source/source_ref), `backend/api/openapi.yaml` (additive params + fields), `Requirements/FURPS/Timetracking.md` (currently empty — to be populated).
- **Pre-release policy**: per `AGENTS.md`, no backward-compat for local on-disk formats; the flat `timerQueue.json` is replaced in place, existing dev fixtures start fresh.