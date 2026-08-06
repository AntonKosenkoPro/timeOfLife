## 1. Backend additions (additive; gates delta sync + provenance)

- [ ] 1.1 Add `source TEXT` (nullable, default `'manual'`) and `source_ref TEXT` (nullable) columns to `entries` in a new migration; add `UNIQUE(user_id, source, source_ref)` partial index (only rows with non-null `source_ref`). Mirror in `sqlite_catalog.go` + `postgres_catalog.go`.
- [ ] 1.2 Extend `GET /activities` and `GET /entries` handlers to accept an optional `modified_since` query param (RFC 3339); filter on `updated_at > modified_since`. Empty/absent = full pull (current behavior).
- [ ] 1.3 Update `Entry` struct + `CreateEntry`/`UpdateEntry` to accept and persist `source`/`source_ref` (default `manual`/null on entries created without them, for back-compat with existing clients).
- [ ] 1.4 Add tests: `modified_since` filtering (sqlite + postgres parity), `source`/`source_ref` uniqueness, idempotent replay with provenance fields. Extend `openapi_test.go` contract check.
- [ ] 1.5 Append `source`, `source_ref`, `modified_since` to `backend/api/openapi.yaml` (bump to v1.2.0). Run `go test ./...`, `golangci-lint run`, `gofmt -l .` green.

## 2. iOS local database foundation (GRDB + App Group)

- [ ] 2.1 Add the App Group capability + entitlement (`group.com.antonkosenko.timeoflife`) to `project.yml`; regenerate the Xcode project with `xcodegen generate`.
- [ ] 2.2 Add GRDB.swift as a dependency (SPM via `project.yml` `dependencies:` / `packages:`); verify it builds on iOS + macOS targets.
- [ ] 2.3 Create `LocalStore` (actor) owning the GRDB `DatabaseQueue`/`DatabasePool` in the App Group container; open with `.completeUntilFirstUserAuthentication` (default); expose a typed schema (activities, categories, activity_categories, entries, timer_state, outbox, undo_buffer, sync_state) via `create(_:)` migrations.
- [ ] 2.4 Define GRDB `Record` types for each table mirroring the backend shapes + `source`/`source_ref` on entries + `sync_state` (resource PK, last_synced_at) + `outbox` (id, resource, record_id, op, payload, created_at, attempts) + `undo_buffer` (id, payload, deleted_at).
- [ ] 2.5 Implement the `LocalStore` chokepoint: all mutations (create/update/delete activity, category, entry; start/stop timer) write state + outbox row in one transaction. No raw GRDB writes outside `LocalStore`.
- [ ] 2.6 Replace `LocalTimerStore` usage; delete `TimerStoring`, `LocalTimerStore`, `TimerRepository`, `StubTimerRepository` (dead code per S5). Update `TimerService` to write only to `LocalStore`; remove the remote-push path.
- [ ] 2.7 Persist running timer state in `timer_state` (singleton row) on start/stop; read it on app launch to resume the UI after crash/relaunch.
- [ ] 2.8 Unit-test `LocalStore`: transactional outbox atomicity, durable undo buffer round-trip, timer_state persistence across a simulated relaunch (re-instantiate `LocalStore`).

## 3. Durable undo buffer + UI integration

- [ ] 3.1 Implement `UndoBufferStore` over `LocalStore`: `enter(pending deletion snapshot)` (tx: insert buffer row + delete records, no outbox), `undo(id)` (tx: restore from payload + delete buffer row), `commitExpired()` (tx: delete buffer row + insert outbox rows for the deletion).
- [ ] 3.2 Foreground reconciliation: on `UIApplication.willEnterForegroundNotification`, call `commitExpired()` for all buffer rows with `deleted_at + 30s < now`. No background timer.
- [ ] 3.3 `UndoToast` countdown driven by `deleted_at + 30s - now` (wall-clock), not a `Timer`; re-show the toast on foreground if the active buffer is still within the window and the user is on the affected screen.
- [ ] 3.4 Supersession (U7): only the most-recent buffer row is undoable via shake/toast; older rows commit on their own 30s expiry (checked at foreground).
- [ ] 3.5 Bulk-delete cap: deletes affecting > N records (default 50) bypass the buffer and confirm hard (reuse the F10 scope-confirm dialog); tune N per design open question.
- [ ] 3.6 Wire shake-to-undo per `Design/INTERACTIONS.md` (`ShakeHostingController` for iOS 15/16; `.onShake` for iOS 17+) into `performUndo()` on the manage screens.
- [ ] 3.7 Tests: undo within window restores + creates no outbox row; window-elapses-in-background commits on next foreground; supersession; bulk-delete bypass.

## 4. SyncController (optional, session-gated)

- [ ] 4.1 Create `SyncController: ObservableObject` (`@MainActor`) with `@Published status: SyncStatus` (`.inactive`/`.syncing`/`.idle(Date)`/`.error(String)`); `activate()`/`deactivate()` driven by `SessionStore.state`.
- [ ] 4.2 Implement `syncNow()`: drain outbox (POST/PATCH/DELETE per row, created_at order, idempotent replay) then delta pull (`GET /activities?modified_since=` + `GET /entries?modified_since=`).
- [ ] 4.3 First-sync (on `activate`): pull-first with `modified_since=nil` (full pull), merge server-wins on `updated_at`, then drain outbox.
- [ ] 4.4 LWW merge on pull: apply server record only if `server.updated_at > local.updated_at`; advance `sync_state.last_synced_at` to max `updated_at` received.
- [ ] 4.5 Conflict handling: 409 `conflict` → adopt server version + clear outbox row; 409 `activity_exists`/`category_exists` → remap local refs to winning id + clear outbox row; 404 on DELETE → treat as success + clear outbox row.
- [ ] 4.6 Triggers: `UIApplication.willEnterForegroundNotification`; `NWPathMonitor` `.satisfied`; manual `syncNow()` from Settings. Defer macOS timer-based trigger to the macOS target task.
- [ ] 4.7 Wire `SyncController` into `AppContainer.production()`; inject the existing `APIClient` and `Connectivity`. `SessionStore.state` changes call `activate()`/`deactivate()`.
- [ ] 4.8 Tests: first-sync pull-first ordering; delta pull advances cursor; LWW merge both directions; outbox drain idempotency; conflict adoption; trigger wiring (mock connectivity + lifecycle).

## 5. RootView + auth flow reframe (backend optional)

- [ ] 5.1 `RootView` always shows `TimerView`; remove the `.signedOut` → `AuthFlowView` branch. `SessionStore.state` now gates `SyncController`, not the root view.
- [ ] 5.2 Add an "Enable Sync" entry point (Settings destination or a toolbar action) that presents `AuthFlowView` as a sheet. The existing `AuthFlowView`/`EmailEntryView`/`OtpEntryView` flow is reused unchanged.
- [ ] 5.3 Add a "Sign out" action (where the interim toolbar Sign-Out lived) that calls `AuthService.signOut()` → `SessionStore.setSignedOut()` → `SyncController.deactivate()`. Local data and outbox are preserved.
- [ ] 5.4 Add "Erase local data" destructive action in Settings (confirm dialog) that wipes the App Group database (state + outbox + undo_buffer + sync_state).
- [ ] 5.5 Update `AuthFlowView` copy to frame sign-in as "Enable cross-device sync" (paid) rather than a required step; add EN + RU strings to `Localizable.strings` + `L10n`.
- [ ] 5.6 Update `RootView`/auth tests for the new launch-into-timer behavior; add a test that the app launches to `TimerView` with no session.

## 6. Entry provenance + user-visible source labels

- [ ] 6.1 `Entry` model: add `source` (default `manual`) + `source_ref` (nullable); thread them through `LocalStore` create/update and the outbox payload.
- [ ] 6.2 Entry detail / history views: show a localized "via <Source>" label for non-`manual` sources; `manual` shows nothing. Add EN + RU strings (`L10n.sourceScreenTime`, `L10n.sourceGarmin`, …).
- [ ] 6.3 Tests: provenance round-trips through `LocalStore` + outbox; uniqueness constraint rejects duplicate `(source, source_ref)`; source label visibility in the detail view.

## 7. Lock-screen Controls (iOS 18+)

- [ ] 7.1 Add a `ControlWidget` target/extension to `project.yml` (iOS 18+ deployment for the extension only; main app stays iOS 15).
- [ ] 7.2 Implement `StartStopTimerIntent: AppIntent` with `static var authenticationPolicy: .alwaysAllowed`; `perform()` writes to `LocalStore` (start most-recent activity, or stop if running) in one tx with an outbox row (`source='control'`).
- [ ] 7.3 Implement the `ControlWidgetToggle` UI: reads `timer_state` from the App Group DB; shows "Start <most-recent activity>" when idle, "Stop (mm:ss)" when running; graceful "please unlock" state when the DB open fails.
- [ ] 7.4 Handle first-use (no activities in local DB): Control displays a "open app to set up" state; no timer started.
- [ ] 7.5 Availability-guard all Control code with `if #available(iOS 18, *)`; verify the app still builds and runs on iOS 15–17 (Control absent).
- [ ] 7.6 Manual smoke test on an iOS 18 simulator: add the Control to Control Center, tap to start/stop, confirm the entry appears with `source='control'`.

## 8. Documentation + contracts

- [ ] 8.1 Update `AGENTS.md`: new architecture section (local-first, relay, outbox, durable undo buffer, SyncController, Controls), updated iOS repo layout, updated API contract table (modified_since, source/source_ref).
- [ ] 8.2 Update `Design/INTERACTIONS.md`: durable undo buffer (wall-clock window, commit-on-foreground, no background timer); sync-client section (triggers, manual sync, status).
- [ ] 8.3 Update `Design/BACKEND/Activity_Catalog_API.md`: `modified_since` on GET endpoints; `source`/`source_ref` on entries; the backend's role as relay (vs authority).
- [ ] 8.4 Populate `Requirements/FURPS/Timetracking.md` (currently empty) with the local-first/sync/Control rows that this change introduces.
- [ ] 8.5 Update `README.md` API contract + coverage sections to match the OpenAPI v1.2.0 additions.

## 9. Verification (per AGENTS.md S5)

- [ ] 9.1 `cd backend && go test ./... -cover && golangci-lint run && gofmt -l . && go vet ./...` all green.
- [ ] 9.2 `cd ios/TimeOfLife && xcodegen generate && swiftlint lint --strict` green.
- [ ] 9.3 `xcodebuild -scheme TimeOfLife -destination 'generic/platform=iOS Simulator' SWIFT_TREAT_WARNINGS_AS_ERRORS=YES GCC_TREAT_WARNINGS_AS_ERRORS=YES build` green.
- [ ] 9.4 `xcodebuild test` green (logic-layer coverage for `LocalStore`, `SyncController`, `UndoBufferStore`, provenance, RootView launch behavior).
- [ ] 9.5 Re-read `Requirements/FURPS/*.md` rows touched by this change; correct conflicts (Common R1/R2/R3, Timetracking rows).
- [ ] 9.6 Confirm no dead code remains (`TimerStoring`, `LocalTimerStore`, `TimerRepository`, `StubTimerRepository` deleted).