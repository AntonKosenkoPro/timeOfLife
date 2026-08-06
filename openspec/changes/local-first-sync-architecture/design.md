## Context

See `proposal.md` (Why) and the four delta specs (local-first-store, sync-client, entry-provenance, lock-screen-controls) for the behavioral contract. This design covers *how*.

Current iOS state (pre-change): `LocalTimerStore` is a flat `timerQueue.json` of `TimeEntry` with a `synced` flag; `TimerService` pushes via a `StubTimerRepository` (no-op); `RootView` gates the app behind `AuthFlowView`. The backend (Go, 277 tests) already implements the catalog/entries CRUD, idempotent POST on `id`, LWW on `updated_at`, hard DELETE, and 409 `activity_exists`/`category_exists` remapping — all of which stay as the relay's merge rules.

Constraints that shape the design: solo dev (no team to specialize); low/uncertain revenue (infra baseline must trend to ~$0); macOS is the next concrete platform (Screen Time API); Android/Web are uncertain; iOS 15 deployment target must stay; the app must launch and work fully with no account.

## Goals / Non-Goals

**Goals:**
- Device as source of truth; backend demoted to optional relay; app works fully offline and unsigned.
- Single Swift codebase for iOS + macOS sync layer (shared via the App Group database and a `SyncController` written once).
- Lock-screen start/stop without Face ID on iOS 18+.
- Provenance (`source`/`source_ref`) and a uniqueness constraint that makes imports dedup-by-construction.
- Durable undo buffer that survives iOS lifecycle (suspension, kill, cold launch) — fixes the in-memory buffer bug.
- Transactional outbox: state change + "need to push" are atomic; deletes are first-class; sync queue survives relaunch.
- Delta pull-sync via `?modified_since=` so integrations (hundreds/thousands of entries) don't force full re-pull.
- Manual "Sync now" + visible sync status, to make the paid feature legible.

**Non-Goals:**
- Pure event sourcing / event-log-as-truth. The hybrid (CRUD + outbox) gives the integration/undo benefits without projection rebuild machinery. Revisit if "replay history to any timestamp" becomes a product need.
- CRDTs / Automerge. LWW is sufficient for single-user + optional-relay; re-evaluate if Android/Web becomes a firm goal and per-platform sync logic is the bottleneck.
- Android / Web clients. The design leaves the door open (the relay API is platform-agnostic), but no client work is in scope.
- Background sync via `BGTaskScheduler` on iOS (unreliable; not worth the complexity for a personal app). macOS timer-based sync is in scope for later.
- Server-side integration connectors (Garmin/Strava webhooks). The schema and outbox support them; the connectors themselves are a future change.
- Reversing the committed decisions: Go backend, SwiftUI iOS, passwordless auth, SQLite-for-tests. All stay.

## Decisions

### D1 — GRDB in the App Group shared container
**Choice:** SQLite via GRDB.swift, file in `group.com.antonkosenko.timeoflife` container, protection `.completeUntilFirstUserAuthentication` (default).

**Rationale:** GRDB is mature, typed, Swift-native, and works on iOS + macOS from one codebase. The App Group is required so widgets, the Screen Time extension, and lock-screen Control intents read/write the same database cross-process. `.completeUntilFirstUserAuthentication` (the default) makes the DB accessible to `alwaysAllowed` intents after first-unlock-since-boot, which is the realistic lock-screen case.

**Alternatives considered:**
- *SwiftData* — iOS 17+ only; we support iOS 15. Rejected.
- *Core Data* — heavy, opaque, CloudKit-coupled. Overkill and wrong fit for the "own your SQLite" stance.
- *Flat JSON files (current)* — no indexes; can't serve the catalog (lookups by `last_used_at`, joins for categories). Stopped scaling at ~500 records. Rejected.
- *In-app container (no App Group)* — widgets/extensions can't read it; lock-screen Controls can't write. Rejected.

### D2 — Transactional outbox (not per-record sync_state column)
**Choice:** A separate `outbox` table; every mutation writes the state change + an outbox row in one transaction. Outbox rows hold the *operation* (op, resource, record_id, payload, created_at), not current state.

**Rationale:** Deletes are first-class (the row persists after the record is gone — no tombstone table needed). Atomicity: state change and "need to push" commit together or not at all (no drift on crash). Maps directly to the backend's idempotent POST / LWW PATCH / hard DELETE — each outbox row is one HTTP call.

**Alternatives considered:**
- *Per-record `sync_state` column* — deletes need a separate tombstone table; two mechanisms. Rejected.
- *Event log (full event sourcing)* — projection rebuild + event versioning machinery not justified at personal scale. The outbox is "log for distribution, tables for truth," which is the hybrid.

### D3 — Durable undo buffer (not in-memory; wall-clock window)
**Choice:** `undo_buffer` table holding full serialized snapshots; window = `deleted_at + 30s` (wall-clock); commit-on-foreground for expired buffers; no background timer.

**Rationale:** The in-memory buffer + Timer design has three failure modes under iOS lifecycle (suspension kills the timer, memory pressure kills the buffer, background commit surprises the user). A durable buffer + wall-clock check on foreground fixes all three. Matches the existing U7 ("only most recent is restorable") with each deletion keeping its own window.

**Alternatives considered:**
- *Keep in-memory, add background task* — iOS background execution is unreliable; doesn't survive kill. Rejected.
- *Commit immediately, support server-side un-delete* — backend is hard-delete by design (R3); reversing it is scope creep. Rejected.

### D4 — Pull-first first-sync
**Choice:** On activation, pull the relay's current state (full, `modified_since=nil`), merge server-wins, then drain the local outbox.

**Rationale:** Lets the relay's ids arrive before local pushes, so cross-device name collisions (`activity_exists`) mostly resolve during merge rather than on push. The push-after-pull then either no-ops (idempotent on matching id) or pushes genuinely-new records.

**Alternatives considered:**
- *Push-first* — hits 409 `activity_exists` on name collisions with different ids, requiring remapping during push; more complex than letting pull bring ids down first. Rejected.

### D5 — Backend additions are additive only (no contract break)
**Choice:** Add `?modified_since=` (filter on `updated_at`) to `GET /activities` and `GET /entries`; add `source` + `source_ref` columns + `UNIQUE(user_id, source, source_ref)` to `entries` (migration). Auth, CRUD, LWW, idempotent POST, error envelope, OpenAPI shape all unchanged.

**Rationale:** The backend's role shifts from authority to relay, but the API contract is stable. Existing 277 tests stay valid; the change is purely additive (new optional query param + new nullable columns). This keeps the iOS ↔ backend contract continuous and avoids a flag-day.

### D6 — SyncController is a long-lived, optional, session-gated object
**Choice:** `SyncController` is `@MainActor`, owns the drain+pull loop, observes `SessionStore` and `Connectivity`. `activate()` on `.signedIn`, `deactivate()` on `.signedOut`. Triggers: foreground, connectivity-restored, manual. Exposes `@Published status` for Settings.

**Rationale:** Distinct from request-response services (`AuthService`, `TimerService`) — it's a background reconciler, not a per-action call. Session-gated because sync is the paid feature. Observes connectivity because drain should wait for `.satisfied`.

**Alternatives considered:**
- *Per-action push (current `TimerService` model)* — couples the timer to the network, can't batch, can't retry uniformly across surfaces. Rejected.
- *A separate sync daemon process* — iOS doesn't support that; the app process is the only option. Rejected.

### D7 — RootView launches into the timer; auth is a Settings action
**Choice:** `RootView` always shows `TimerView`; `AuthFlowView` is presented as a sheet/destination from Settings ("Enable Sync"). `SessionStore.state` gates `SyncController`, not the root view.

**Rationale:** "Backend optional" requires the app to be usable with no account. Zero-friction onboarding — the user tracks time immediately. Sign-in is a deliberate action for users who want sync (the paid feature).

**Trade-off:** lose email capture at install. Mitigation: the "Enable Sync" flow captures email at the moment the user has intent (they want sync), which is a better funnel than forcing it on everyone.

### D8 — Running timer state in GRDB (not just memory)
**Choice:** `timer_state` singleton row in GRDB (`activity_id`, `started_at`, `status`). `TimerService` reads/writes it; widgets and Controls read it to render.

**Rationale:** Forced by Controls needing to display running state cross-process; beneficial regardless — a timer app where the running timer survives a crash is more correct. The singleton row is simple (only one timer runs at a time).

### D9 — Lock-screen Controls via iOS 18 `ControlWidget` + `alwaysAllowed` intent
**Choice:** `ControlWidgetToggle` with an `AppIntent` (`authenticationPolicy = .alwaysAllowed`) that writes to the App Group DB. Availability-guarded at iOS 18; deployment target stays 15. Default Control action: toggle start/stop of the most-recently-used activity.

**Rationale:** `alwaysAllowed` is documented as running when locked without auth. The intent runs in the app process (background), sharing the app's GRDB access path — no extension coordination for Controls specifically. `.completeUntilFirstUserAuthentication` (D1) makes the DB accessible after first-unlock-since-boot, covering the realistic case; the post-reboot-pre-unlock case fails gracefully.

**Alternatives considered:**
- *Require auth* — defeats the "no Face ID" goal. Rejected.
- *Separate extension process for the intent* — Controls run intents in the app process; no extension to add. Rejected as inapplicable.
- *Pinned-activity Controls (one per activity)* — more flexible but more setup; defer as a later enhancement.

### D10 — Source labels are user-visible
**Choice:** `source` drives a localized "via <Source>" label in entry detail/history for non-`manual` sources; `manual` shows nothing.

**Rationale:** User confirmed they want provenance visible. It also helps users understand why an entry appeared (e.g., "via Screen Time" explains an entry they didn't manually create).

## Risks / Trade-offs

- **[App Group entitlement requires a paid Apple Developer account for distribution]** → Mitigation: the entitlement itself is free for dev builds; the paid account is already required for TestFlight (Epic 10). No new dependency for dev/CI.
- **[Two sources of truth (tables for now, outbox for distribution) can drift if a code path writes tables without an outbox row]** → Mitigation: a single `LocalStore` chokepoint owns all mutations and always writes both in one tx. Lint/review rule: no raw GRDB writes outside `LocalStore`.
- **[Undo buffer is unbounded for bulk deletes (activity + N entries)]** → Mitigation: cap undo to deletes affecting ≤ N records (e.g., 50); larger deletes confirm hard and bypass the buffer. Reuses the F10 scope-confirm dialog. N to be tuned.
- **[Delta pull relies on `updated_at` monotonicity across devices]** → Mitigation: `updated_at` is client-generated (UUID v7 timestamp-ordered) and the relay's LWW already depends on it; the existing design assumes this. Clock skew across devices is a known LWW limitation; acceptable at personal scale.
- **[`modified_since` is a new backend param — must be tested across sqlite + postgres parity]** → Mitigation: follows the existing dual-store test pattern (`sqlite_catalog.go` + `postgres_catalog.go` parity tests). Add to `openapi.yaml` (S10).
- **[Controls API is iOS 18+ — early-adopters-only surface]** → Mitigation: availability guard; the app's core value (timer, catalog, sync) works on iOS 15+. Controls are a power-user convenience, not a prerequisite.
- **[First-sync pull-then-push has a window where a second device could push and collide]** → Mitigation: idempotent POST + 409 remapping handle the residual collision; the window is small (seconds) and the recovery is defined.

## Migration Plan

This is an unreleased app (per AGENTS.md pre-release policy): no on-disk data in the wild, no backward-compat needed.

- **Local DB**: `timerQueue.json` is replaced in place by the GRDB database. Existing dev fixtures and test devices start fresh — no migration code.
- **Backend**: one new migration (`004_provenance.sql` or appended to `003_catalog.sql` if not yet shipped) adding `source` + `source_ref` + the unique constraint to `entries`; `modified_since` is a query param, no migration. Existing tests stay green (new columns nullable, new param optional).
- **OpenAPI**: additive — new query param, new nullable fields on the entry schema. Version bump to v1.2.0.
- **Rollback** (if needed before release): revert the iOS client to the previous build; the backend additions are additive and ignored by old clients. No data loss.

## Open Questions

- **Bulk-delete undo cap (N):** above what affected-record count should a delete bypass the undo buffer and confirm hard? Proposal: 50. Confirm during implementation; doesn't change the spec.
- **macOS background sync interval:** every 5 min while running is the proposal; confirm when the macOS target is built. Doesn't change the sync-client spec (the trigger is already named).
- **Control's "first use with no history" state:** exact UI copy and whether it deep-links the user into the app to create an activity. Deferrable to the Control implementation task.